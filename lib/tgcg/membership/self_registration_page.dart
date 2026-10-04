import 'package:flutter/material.dart';

import '../evidence/device_evidence_service.dart';
import '../media/device_media.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'membership_store.dart';
import 'pvc_recognition_service.dart';

/// Public member onboarding.
///
/// Membership is the permanent identity. Registration itself grants no
/// operational role or module access. Roles and assignments are attached later
/// by authorized coordinators.
class SelfRegistrationPage extends StatefulWidget {
  const SelfRegistrationPage({super.key});

  @override
  State<SelfRegistrationPage> createState() => _SelfRegistrationPageState();
}

class _SelfRegistrationPageState extends State<SelfRegistrationPage> {
  final _recognizer = PvcRecognitionService();
  final _evidence = DeviceEvidenceService();
  final _name = TextEditingController();
  final _vin = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  PvcRecognitionResult? _scan;
  CapturedEvidence? _selfie;
  String? _selectedLgaId;
  String? _selectedPollingUnitId;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _vin.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _evidence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final membership = MembershipOperations.of(context);
    _selectedLgaId ??= membership.geography.lgas.first.id;

    final pollingUnits = membership.geography.pollingUnits
        .where((item) => item.scope.lgaId == _selectedLgaId)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(
        title: const Text('Member Registration'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          children: [
            const TgcgPageHeader(
              eyebrow: 'MEMBER FIRST',
              title: 'Register as a USESF member',
              subtitle:
                  'Scan your PVC, confirm the extracted identity and home polling unit, capture a live selfie and create your password. Registration does not assign a role.',
              trailing: TgcgStatusPill(
                label: 'SELF REGISTRATION',
                color: TgcgColors.primary,
                icon: Icons.person_add_alt_1_rounded,
              ),
            ),
            const SizedBox(height: 16),
            _RegistrationPrinciple(),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final scanCard = _CaptureCard(
                  scan: _scan,
                  selfie: _selfie,
                  busy: _busy,
                  onScanPvc: _scanPvc,
                  onCaptureSelfie: _captureSelfie,
                );
                final form = _RegistrationForm(
                  name: _name,
                  vin: _vin,
                  phone: _phone,
                  email: _email,
                  password: _password,
                  confirmPassword: _confirmPassword,
                  selectedLgaId: _selectedLgaId!,
                  selectedPollingUnitId: _selectedPollingUnitId,
                  lgas: membership.geography.lgas,
                  pollingUnits: pollingUnits,
                  scan: _scan,
                  selfie: _selfie,
                  busy: _busy,
                  onLgaChanged: (value) => setState(() {
                    _selectedLgaId = value;
                    _selectedPollingUnitId = null;
                  }),
                  onPollingUnitChanged: (value) =>
                      setState(() => _selectedPollingUnitId = value),
                  onSubmit: () => _register(membership),
                );
                if (constraints.maxWidth < 980) {
                  return Column(
                    children: [
                      scanCard,
                      const SizedBox(height: 16),
                      form,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: scanCard),
                    const SizedBox(width: 16),
                    Expanded(flex: 6, child: form),
                  ],
                );
              },
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: TgcgColors.warning.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(TgcgRadius.md),
                  border: Border.all(
                    color: TgcgColors.warning.withValues(alpha: .22),
                  ),
                ),
                child: Text(
                  _message!,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _scanPvc() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await _recognizer.captureAndRecognize();
      if (!mounted || result == null) return;

      final membership = MembershipOperations.of(context, listen: false);
      final matched = result.pollingUnitCode == null
          ? null
          : membership.geography.pollingUnitByOfficialCode(
                  result.pollingUnitCode!,
                ) ??
              membership.geography.pollingUnit(result.pollingUnitCode!);

      setState(() {
        _scan = result;
        if ((result.fullName ?? '').trim().isNotEmpty) {
          _name.text = result.fullName!.trim();
        }
        if ((result.voterId ?? '').trim().isNotEmpty) {
          _vin.text = result.voterId!.trim();
        }
        if (matched != null) {
          _selectedLgaId = matched.scope.lgaId;
          _selectedPollingUnitId = matched.code;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'PVC capture could not be completed: ${describeDeviceError(error)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _captureSelfie() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final selfie = await _evidence.captureSelfie();
      if (!mounted || selfie == null) return;
      setState(() => _selfie = selfie);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message =
            'Live selfie could not be captured: ${describeDeviceError(error)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register(
    MembershipOperationsController membership,
  ) async {
    final scan = _scan;
    final selfie = _selfie;
    final vin = _vin.text.trim();
    final name = _name.text.trim();
    final password = _password.text;
    final pollingUnitId = _selectedPollingUnitId;

    if (scan == null) {
      setState(() => _message = 'Scan your PVC before registering.');
      return;
    }
    if (vin.length < 6) {
      setState(() => _message = 'A valid PVC/VIN is required.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _message = 'Confirm your full name.');
      return;
    }
    if (pollingUnitId == null) {
      setState(() => _message = 'Confirm your home polling unit.');
      return;
    }
    if (selfie == null || (selfie.path ?? '').isEmpty) {
      setState(() => _message = 'Capture a live selfie before registering.');
      return;
    }
    if (password.length < 8) {
      setState(
        () => _message = 'Create a password with at least 8 characters.',
      );
      return;
    }
    if (password != _confirmPassword.text) {
      setState(() => _message = 'The two passwords do not match.');
      return;
    }

    final unit = membership.geography.pollingUnit(pollingUnitId);
    if (unit == null) {
      setState(() => _message = 'The selected polling unit is unavailable.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final member = await membership.createMember(
        fullName: name,
        phoneNumber: _phone.text.trim(),
        email: _email.text.trim(),
        pvcVin: vin,
        selfieReference: selfie.path,
        registrationScope: unit.scope,
        homePollingUnitId: unit.code,
        pvcPollingUnitCode: scan.pollingUnitCode,
        linkedBy: 'SELF',
      );

      await membership.setPvcCredential(
        memberId: member.id,
        voterId: vin,
      );
      await membership.setMemberPassword(
        memberId: member.id,
        password: password,
      );

      if (!mounted) return;
      final session = TgcgSession.of(context, listen: false);
      session.signIn(
        role: TgcgRole.member,
        operatorName: member.fullName,
        accessId: member.id,
        scope: unit.scope,
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message?.toString() ?? error.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Registration could not be completed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _RegistrationPrinciple extends StatelessWidget {
  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'One identity first',
        subtitle:
            'You become a member first. Authorized coordinators can add roles and assignments later.',
        child: const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TgcgStatusPill(
              label: '1 PVC',
              color: TgcgColors.info,
              compact: true,
            ),
            TgcgStatusPill(
              label: '2 LIVE SELFIE',
              color: TgcgColors.primary,
              compact: true,
            ),
            TgcgStatusPill(
              label: '3 MEMBER ACCOUNT',
              color: TgcgColors.success,
              compact: true,
            ),
            TgcgStatusPill(
              label: '4 WAIT FOR ROLE / ASSIGNMENT',
              color: TgcgColors.accentStrong,
              compact: true,
            ),
          ],
        ),
      );
}

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    required this.scan,
    required this.selfie,
    required this.busy,
    required this.onScanPvc,
    required this.onCaptureSelfie,
  });

  final PvcRecognitionResult? scan;
  final CapturedEvidence? selfie;
  final bool busy;
  final VoidCallback onScanPvc;
  final VoidCallback onCaptureSelfie;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Identity capture',
        subtitle:
            'The PVC image is used for extraction only and is not retained. The live selfie is kept for internal human review.',
        child: Column(
          children: [
            _CaptureStep(
              icon: Icons.credit_card_rounded,
              title: 'PVC',
              detail: scan == null
                  ? 'Scan your PVC to extract identity and polling-unit information.'
                  : 'PVC captured • ${scan!.voterId ?? 'VIN needs confirmation'}',
              complete: scan != null,
              actionLabel: scan == null ? 'Scan PVC' : 'Scan again',
              onPressed: busy ? null : onScanPvc,
            ),
            const SizedBox(height: 12),
            _CaptureStep(
              icon: Icons.face_retouching_natural_outlined,
              title: 'Live selfie',
              detail: selfie == null
                  ? 'Capture a current face photo for internal identity review.'
                  : 'Selfie captured • ${selfie!.fileName}',
              complete: selfie != null,
              actionLabel: selfie == null ? 'Capture selfie' : 'Retake selfie',
              onPressed: busy ? null : onCaptureSelfie,
            ),
          ],
        ),
      );
}

class _CaptureStep extends StatelessWidget {
  const _CaptureStep({
    required this.icon,
    required this.title,
    required this.detail,
    required this.complete,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool complete;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: complete
              ? TgcgColors.success.withValues(alpha: .05)
              : TgcgColors.surfaceRaised,
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          border: Border.all(
            color: complete
                ? TgcgColors.success.withValues(alpha: .24)
                : TgcgColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  complete ? Icons.check_circle_rounded : icon,
                  color: complete ? TgcgColors.success : TgcgColors.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              detail,
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(actionLabel),
            ),
          ],
        ),
      );
}

class _RegistrationForm extends StatelessWidget {
  const _RegistrationForm({
    required this.name,
    required this.vin,
    required this.phone,
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.selectedLgaId,
    required this.selectedPollingUnitId,
    required this.lgas,
    required this.pollingUnits,
    required this.scan,
    required this.selfie,
    required this.busy,
    required this.onLgaChanged,
    required this.onPollingUnitChanged,
    required this.onSubmit,
  });

  final TextEditingController name;
  final TextEditingController vin;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController confirmPassword;
  final String selectedLgaId;
  final String? selectedPollingUnitId;
  final List<CanonicalLga> lgas;
  final List<CanonicalPollingUnit> pollingUnits;
  final PvcRecognitionResult? scan;
  final CapturedEvidence? selfie;
  final bool busy;
  final ValueChanged<String> onLgaChanged;
  final ValueChanged<String?> onPollingUnitChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Confirm member profile',
        subtitle:
            'Phone and email are optional at registration. Email can be verified later for password recovery.',
        child: Column(
          children: [
            TextField(
              controller: name,
              enabled: !busy && scan != null,
              decoration: const InputDecoration(
                labelText: 'Full name from PVC',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: vin,
              enabled: !busy && scan != null,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'PVC / VIN',
                helperText:
                    'Stored with the member profile and used to prevent duplicate registration.',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: selectedLgaId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'LGA from PVC',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              items: lgas
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        '${item.name} • ${item.senatorialDistrictName}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: busy || scan == null
                  ? null
                  : (value) {
                      if (value != null) onLgaChanged(value);
                    },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'self-register-pu-$selectedLgaId-$selectedPollingUnitId',
              ),
              initialValue: pollingUnits.any(
                (item) => item.code == selectedPollingUnitId,
              )
                  ? selectedPollingUnitId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Home polling unit from PVC',
                helperText: scan?.pollingUnitCode == null
                    ? 'Confirm the polling unit'
                    : 'Detected PVC code: ${scan!.pollingUnitCode}',
                prefixIcon: const Icon(Icons.place_outlined),
              ),
              items: pollingUnits
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.code,
                      child: Text(
                        '${item.displayCode} • ${item.scope.pollingUnitName ?? item.scope.label}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: busy || scan == null ? null : onPollingUnitChanged,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              enabled: !busy && scan != null,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number (optional)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: email,
              enabled: !busy && scan != null,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
                helperText:
                    'Verify later before it can be used for password recovery.',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: password,
              enabled: !busy && scan != null,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                helperText: 'Use at least 8 characters.',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmPassword,
              enabled: !busy && scan != null,
              obscureText: true,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_reset_rounded),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy || scan == null || selfie == null
                    ? null
                    : onSubmit,
                icon: busy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(busy ? 'Registering...' : 'Create member account'),
              ),
            ),
          ],
        ),
      );
}
