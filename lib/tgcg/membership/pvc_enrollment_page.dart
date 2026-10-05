import 'package:flutter/material.dart';

import '../access/access_policy.dart';
import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'membership_store.dart';
import 'pvc_recognition_service.dart';

class PvcEnrollmentPage extends StatefulWidget {
  const PvcEnrollmentPage({
    super.key,
    this.onOpenAssignments,
  });

  final VoidCallback? onOpenAssignments;

  @override
  State<PvcEnrollmentPage> createState() => _PvcEnrollmentPageState();
}

class _PvcEnrollmentPageState extends State<PvcEnrollmentPage> {
  final _recognizer = PvcRecognitionService();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _voterId = TextEditingController();
  final _password = TextEditingController();
  PvcRecognitionResult? _scan;
  bool _reading = false;
  TgcgMember? _created;
  String? _selectedLgaId;
  String? _selectedPollingUnitId;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _voterId.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = MembershipOperations.of(context);
    final membershipScopes = TgcgAccessPolicy.scopesFor(
      context,
      TgcgCapability.manageMembership,
    );
    final authorizedUnits = store.geography.pollingUnits
        .where(
          (unit) => membershipScopes.any(
            (scope) => TgcgPermissionPolicy.scopeAllows(scope, unit.scope),
          ),
        )
        .toList(growable: false);
    final authorizedLgaIds =
        authorizedUnits.map((unit) => unit.scope.lgaId).whereType<String>().toSet();
    final authorizedLgas = store.geography.lgas
        .where((lga) => authorizedLgaIds.contains(lga.id))
        .toList(growable: false);
    if (authorizedLgas.isNotEmpty &&
        !authorizedLgas.any((lga) => lga.id == _selectedLgaId)) {
      _selectedLgaId = authorizedLgas.first.id;
      _selectedPollingUnitId = null;
    }
    final lgaPollingUnits = authorizedUnits
        .where((unit) => unit.scope.lgaId == _selectedLgaId)
        .toList(growable: false);
    final canManage = TgcgAccessPolicy.allows(
      context,
      TgcgCapability.manageMembership,
    );
    final membershipRole = TgcgAccessPolicy.roleFor(
      context,
      TgcgCapability.manageMembership,
    );
    final canCreateWithoutPvc =
        membershipRole == TgcgRole.stateCoordinator ||
        membershipRole == TgcgRole.stateAdministrator;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'PVC IDENTITY ENROLMENT',
          title: 'Member Enrolment',
          subtitle:
              'Create the permanent member identity and home polling-unit relationship. Normal registration uses PVC; State Coordinator may create a member manually without it.',
          trailing: TgcgStatusPill(
            label: '${store.members.length} MEMBERS',
            color: TgcgColors.primary,
            icon: Icons.groups_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(store: store),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final scanner = _ScannerPanel(
              scan: _scan,
              reading: _reading,
              canManage: canManage,
              onCamera: () => _scanPvc(camera: true),
              onGallery: () => _scanPvc(camera: false),
            );
            final form = _IdentityForm(
              name: _name,
              phone: _phone,
              email: _email,
              voterId: _voterId,
              password: _password,
              lgas: authorizedLgas,
              pollingUnits: lgaPollingUnits,
              selectedLgaId: _selectedLgaId!,
              selectedPollingUnitId: _selectedPollingUnitId,
              onLgaChanged: (value) => setState(() {
                _selectedLgaId = value;
                _selectedPollingUnitId = null;
              }),
              onPollingUnitChanged: (value) =>
                  setState(() => _selectedPollingUnitId = value),
              scan: _scan,
              created: _created,
              enabled: canManage && (_scan != null || canCreateWithoutPvc),
              canCreateWithoutPvc: canCreateWithoutPvc,
              onCreate: () => _createMember(store),
              onReset: _reset,
            );
            if (constraints.maxWidth < 980) {
              return Column(
                children: [scanner, const SizedBox(height: 16), form],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: scanner),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: form),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _RecentMembers(store: store),
        const SizedBox(height: 16),
        _AssignmentNextStepPanel(
          onOpenAssignments: widget.onOpenAssignments,
        ),
      ],
    );
  }

  Future<void> _scanPvc({required bool camera}) async {
    setState(() {
      _reading = true;
      _created = null;
    });
    try {
      final result = camera
          ? await _recognizer.captureAndRecognize()
          : await _recognizer.pickAndRecognize();
      if (!mounted || result == null) return;
      final store = MembershipOperations.of(context, listen: false);
      final matchedUnit = result.pollingUnitCode == null
          ? null
          : store.geography.pollingUnitByOfficialCode(
                  result.pollingUnitCode!,
                ) ??
              store.geography.pollingUnit(result.pollingUnitCode!);
      setState(() {
        _scan = result;
        _name.text = result.fullName ?? '';
        _voterId.text = result.voterId ?? '';
        if (matchedUnit != null) {
          _selectedLgaId = matchedUnit.scope.lgaId;
          _selectedPollingUnitId = matchedUnit.code;
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PVC scan could not be completed: $error')),
      );
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _createMember(MembershipOperationsController store) async {
    final session = TgcgSession.of(context, listen: false);
    final membershipRole = TgcgAccessPolicy.roleFor(
      context,
      TgcgCapability.manageMembership,
      listen: false,
    );
    final canCreateWithoutPvc =
        membershipRole == TgcgRole.stateCoordinator ||
        membershipRole == TgcgRole.stateAdministrator;
    final voterId = _voterId.text.trim();
    final hasPvc = _scan != null;

    if ((!hasPvc && !canCreateWithoutPvc) ||
        _name.text.trim().isEmpty ||
        _selectedPollingUnitId == null ||
        (hasPvc && voterId.length < 6) ||
        _password.text.length < 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              canCreateWithoutPvc
                  ? 'Confirm the member name, home polling unit and a password of at least 8 characters.'
                  : 'Scan the PVC, confirm the member details and create a password of at least 8 characters.',
            ),
          ),
        );
      }
      return;
    }

    final unit = store.geography.pollingUnit(_selectedPollingUnitId!);
    if (unit == null) return;

    try {
      final member = await store.createMember(
        fullName: _name.text.trim(),
        phoneNumber: _phone.text.trim(),
        email: _email.text.trim(),
        pvcVin: voterId.isEmpty ? null : voterId,
        registrationScope: unit.scope,
        homePollingUnitId: unit.code,
        pvcPollingUnitCode: _scan?.pollingUnitCode,
        linkedBy:
            session.accessId.isEmpty ? session.operatorName : session.accessId,
      );

      if (voterId.isNotEmpty) {
        await store.setPvcCredential(
          memberId: member.id,
          voterId: voterId,
        );
      }
      await store.setMemberPassword(
        memberId: member.id,
        password: _password.text,
      );
      if (!mounted) return;
      setState(() => _created = member);
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on ArgumentError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message?.toString() ?? error.toString())),
      );
    }
  }

  void _reset() {
    setState(() {
      _scan = null;
      _created = null;
      _name.clear();
      _phone.clear();
      _email.clear();
      _voterId.clear();
      _password.clear();
      _selectedPollingUnitId = null;
    });
  }


}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.store});
  final MembershipOperationsController store;

  @override
  Widget build(BuildContext context) {
    final withVin =
        store.members.where((member) => member.pvcVin != null).length;
    final pendingReview = store.members
        .where((member) => member.identityReview == MemberIdentityReview.pending)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 520
                ? 2
                : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            TgcgMetricCard(
              width: width,
              label: 'Members',
              value: '${store.members.length}',
              detail: 'Permanent member identities',
              icon: Icons.groups_outlined,
              tone: TgcgMetricTone.info,
            ),
            TgcgMetricCard(
              width: width,
              label: 'PU linked',
              value: '${store.membersWithHomePollingUnit}',
              detail: '${store.membersWithoutHomePollingUnit} without home PU',
              icon: Icons.location_on_outlined,
              tone: store.membersWithoutHomePollingUnit == 0
                  ? TgcgMetricTone.success
                  : TgcgMetricTone.warning,
            ),
            TgcgMetricCard(
              width: width,
              label: 'PVC / VIN stored',
              value: '$withVin',
              detail: 'PVC image itself is not retained',
              icon: Icons.badge_outlined,
              tone: TgcgMetricTone.success,
            ),
            TgcgMetricCard(
              width: width,
              label: 'Identity review',
              value: '$pendingReview',
              detail: 'Pending backend human review',
              icon: Icons.person_search_outlined,
              tone: TgcgMetricTone.neutral,
            ),
          ],
        );
      },
    );
  }
}

class _ScannerPanel extends StatelessWidget {
  const _ScannerPanel({
    required this.scan,
    required this.reading,
    required this.canManage,
    required this.onCamera,
    required this.onGallery,
  });
  final PvcRecognitionResult? scan;
  final bool reading;
  final bool canManage;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'PVC recognition',
        subtitle:
            'Capture the card for normal enrolment. State-level authorized manual creation may proceed without a PVC.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 220,
              decoration: BoxDecoration(
                gradient: TgcgGradients.navigation,
                borderRadius: BorderRadius.circular(TgcgRadius.lg),
                border: Border.all(
                  color: TgcgColors.accent.withValues(alpha: .18),
                ),
              ),
              child: Center(
                child: reading
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            scan == null
                                ? Icons.credit_card_rounded
                                : Icons.verified_rounded,
                            color: scan == null
                                ? TgcgColors.accent
                                : TgcgColors.success,
                            size: 52,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            scan == null
                                ? 'Scan Permanent Voter Card'
                                : scan!.imageName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (scan != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              scan!.hasRecognizedText
                                  ? 'Identity text recognized'
                                  : 'Card captured',
                              style: const TextStyle(
                                color: TgcgColors.gold200,
                                fontSize: 11,
                              ),
                            ),
                            if (scan!.pollingUnitCode != null) ...[
                              const SizedBox(height: 5),
                              Text(
                                'PU CODE • ${scan!.pollingUnitCode}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canManage && !reading ? onCamera : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Scan PVC'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canManage && !reading ? onGallery : null,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Upload image'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _IdentityForm extends StatelessWidget {
  const _IdentityForm({
    required this.name,
    required this.phone,
    required this.email,
    required this.voterId,
    required this.password,
    required this.lgas,
    required this.pollingUnits,
    required this.selectedLgaId,
    required this.selectedPollingUnitId,
    required this.onLgaChanged,
    required this.onPollingUnitChanged,
    required this.scan,
    required this.created,
    required this.enabled,
    required this.canCreateWithoutPvc,
    required this.onCreate,
    required this.onReset,
  });

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController voterId;
  final TextEditingController password;
  final List<CanonicalLga> lgas;
  final List<CanonicalPollingUnit> pollingUnits;
  final String selectedLgaId;
  final String? selectedPollingUnitId;
  final ValueChanged<String> onLgaChanged;
  final ValueChanged<String?> onPollingUnitChanged;
  final PvcRecognitionResult? scan;
  final TgcgMember? created;
  final bool enabled;
  final bool canCreateWithoutPvc;
  final VoidCallback onCreate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Confirm identity',
        subtitle:
            'Review the PVC information when available. State-level membership authority can also create a member manually without a PVC.',
        child: Column(
          children: [
            TextField(
              controller: name,
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: voterId,
              enabled: enabled,
              decoration: InputDecoration(
                labelText: canCreateWithoutPvc
                    ? 'PVC / VIN (optional for state-level manual creation)'
                    : 'PVC / VIN',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: selectedLgaId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Registration LGA'),
              items: lgas
                  .map(
                    (lga) => DropdownMenuItem(
                      value: lga.id,
                      child: Text('${lga.name} • ${lga.senatorialDistrictName}'),
                    ),
                  )
                  .toList(),
              onChanged: enabled && created == null
                  ? (value) {
                      if (value != null) onLgaChanged(value);
                    }
                  : null,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('pu-$selectedLgaId-$selectedPollingUnitId'),
              initialValue: pollingUnits.any(
                (unit) => unit.code == selectedPollingUnitId,
              )
                  ? selectedPollingUnitId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Home polling unit',
                helperText: scan?.pollingUnitCode == null
                    ? 'Select the member polling unit'
                    : 'PVC code detected: ${scan!.pollingUnitCode}',
                prefixIcon: const Icon(Icons.location_on_outlined),
              ),
              items: pollingUnits
                  .map(
                    (unit) => DropdownMenuItem(
                      value: unit.code,
                      child: Text(
                        '${unit.displayCode} • ${unit.scope.pollingUnitName ?? unit.scope.label}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: enabled && created == null
                  ? onPollingUnitChanged
                  : null,
            ),
            if (scan?.pollingUnitCode != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TgcgStatusPill(
                  label: selectedPollingUnitId == null
                      ? 'PVC PU CODE NOT YET MATCHED'
                      : 'PVC PU MATCHED',
                  color: selectedPollingUnitId == null
                      ? TgcgColors.warning
                      : TgcgColors.success,
                  icon: selectedPollingUnitId == null
                      ? Icons.manage_search_rounded
                      : Icons.verified_outlined,
                  compact: true,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              enabled: enabled,
              decoration:
                  const InputDecoration(labelText: 'Phone number (optional)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: email,
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: password,
              enabled: enabled && created == null,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Member password',
                helperText:
                    'Use at least 8 characters. Login supports PVC/VIN, phone or email.',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            if (scan?.rawText.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Recognized PVC text',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      scan!.rawText,
                      style: const TextStyle(
                        fontSize: 11,
                        color: TgcgColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: enabled &&
                            created == null &&
                            selectedPollingUnitId != null &&
                            password.text.length >= 8
                        ? onCreate
                        : null,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Create member'),
                  ),
                ),
                if (created != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReset,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Next enrolment'),
                    ),
                  ),
                ],
              ],
            ),
            if (created != null) ...[
              const SizedBox(height: 12),
              TgcgStatusPill(
                label: created!.membershipNumber ?? created!.id,
                color: TgcgColors.success,
                icon: Icons.verified_rounded,
              ),
            ],
          ],
        ),
      );
}

class _RecentMembers extends StatelessWidget {
  const _RecentMembers({required this.store});
  final MembershipOperationsController store;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Member registry',
        subtitle: 'Recently enrolled USESF identities.',
        child: Column(
          children: store.members.take(6).map((member) {
            final scope = store.registrationScopeForMember(member.id);
            final homePu = store.homePollingUnitForMember(member.id);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(
                  member.fullName.isEmpty
                      ? '?'
                      : member.fullName[0].toUpperCase(),
                ),
              ),
              title: Text(
                member.fullName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                homePu == null
                    ? '${member.membershipNumber ?? member.id} • ${scope?.label ?? 'Kaduna State'} • ${member.phoneNumber}'
                    : '${member.membershipNumber ?? member.id} • HOME PU: ${homePu.displayCode}\n'
                        '${homePu.scope.label} • ${member.phoneNumber}',
              ),
              isThreeLine: homePu != null,
              trailing: TgcgStatusPill(
                label: member.status.name.toUpperCase(),
                color: member.status == RecordStatus.verified
                    ? TgcgColors.success
                    : TgcgColors.info,
                compact: true,
              ),
            );
          }).toList(),
        ),
      );
}

class _AssignmentNextStepPanel extends StatelessWidget {
  const _AssignmentNextStepPanel({
    required this.onOpenAssignments,
  });

  final VoidCallback? onOpenAssignments;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'One registration, many possible assignments',
        subtitle:
            'Every person is enrolled once as a USESF member. Jobs, temporary duties and polling-unit deployments are attached later from Assignment Control; they do not create a second member identity.',
        trailing: onOpenAssignments == null
            ? null
            : FilledButton.icon(
                onPressed: onOpenAssignments,
                icon: const Icon(Icons.assignment_ind_rounded),
                label: const Text('Open Assignment Control'),
              ),
        child: const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TgcgStatusPill(
              label: '1 MEMBER IDENTITY',
              color: TgcgColors.info,
              compact: true,
            ),
            TgcgStatusPill(
              label: '2 HOME POLLING UNIT',
              color: TgcgColors.primary,
              compact: true,
            ),
            TgcgStatusPill(
              label: '3 ASSIGN ANY AUTHORIZED JOB',
              color: TgcgColors.success,
              compact: true,
            ),
            TgcgStatusPill(
              label: '4 TRACK DUTY SEPARATELY',
              color: TgcgColors.accentStrong,
              compact: true,
            ),
          ],
        ),
      );
}

