import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/tgcg_design.dart';
import 'membership_store.dart';
import 'pvc_recognition_service.dart';

enum _MemberAccessMethod { phone, email, pvc }

class MemberAccessPage extends StatefulWidget {
  const MemberAccessPage({super.key});

  @override
  State<MemberAccessPage> createState() => _MemberAccessPageState();
}

class _MemberAccessPageState extends State<MemberAccessPage> {
  final _identifier = TextEditingController();
  final _pin = TextEditingController();
  final _recognizer = PvcRecognitionService();

  _MemberAccessMethod _method = _MemberAccessMethod.phone;
  TgcgMember? _member;
  PvcRecognitionResult? _pvcScan;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _identifier.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final membership = MembershipOperations.of(context);
    final homePu =
        _member == null ? null : membership.homePollingUnitForMember(_member!.id);

    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(
        title: const Text('Member Access'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TgcgPageHeader(
                    eyebrow: 'MEMBER AUTHENTICATION',
                    title: 'Sign in to USESF',
                    subtitle:
                        'Find your USESF account with your PVC, phone number or email, then confirm your 6-digit member PIN.',
                    trailing: TgcgStatusPill(
                      label: 'SECURE MEMBER ACCESS',
                      color: TgcgColors.success,
                      icon: Icons.verified_user_outlined,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TgcgSectionCard(
                    title: 'Choose sign-in method',
                    subtitle:
                        'PVC is used only to find the enrolled USESF account. A PIN is still required.',
                    child: SegmentedButton<_MemberAccessMethod>(
                      segments: const [
                        ButtonSegment(
                          value: _MemberAccessMethod.phone,
                          icon: Icon(Icons.phone_android_outlined),
                          label: Text('Phone'),
                        ),
                        ButtonSegment(
                          value: _MemberAccessMethod.email,
                          icon: Icon(Icons.alternate_email_rounded),
                          label: Text('Email'),
                        ),
                        ButtonSegment(
                          value: _MemberAccessMethod.pvc,
                          icon: Icon(Icons.credit_card_outlined),
                          label: Text('PVC'),
                        ),
                      ],
                      selected: {_method},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) => setState(() {
                                _method = selection.first;
                                _member = null;
                                _pvcScan = null;
                                _identifier.clear();
                                _pin.clear();
                                _message = null;
                              }),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_member == null)
                    TgcgSectionCard(
                      title: _method == _MemberAccessMethod.pvc
                          ? 'Scan enrolled PVC'
                          : 'Find your member account',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_method != _MemberAccessMethod.pvc)
                            TextField(
                              controller: _identifier,
                              enabled: !_busy,
                              keyboardType:
                                  _method == _MemberAccessMethod.phone
                                      ? TextInputType.phone
                                      : TextInputType.emailAddress,
                              onSubmitted: (_) => _identify(membership),
                              decoration: InputDecoration(
                                labelText: _method == _MemberAccessMethod.phone
                                    ? 'Phone number'
                                    : 'Email address',
                                prefixIcon: Icon(
                                  _method == _MemberAccessMethod.phone
                                      ? Icons.phone_outlined
                                      : Icons.email_outlined,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: TgcgGradients.navigation,
                                borderRadius:
                                    BorderRadius.circular(TgcgRadius.lg),
                                border:
                                    Border.all(color: TgcgColors.gold200),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    _pvcScan == null
                                        ? Icons.credit_card_rounded
                                        : Icons.verified_outlined,
                                    color: _pvcScan == null
                                        ? TgcgColors.gold400
                                        : TgcgColors.success,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _pvcScan == null
                                        ? 'Scan the PVC used during enrolment'
                                        : 'PVC captured',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (_pvcScan?.pollingUnitCode != null) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      'PU • ${_pvcScan!.pollingUnitCode}',
                                      style: const TextStyle(
                                        color: TgcgColors.gold200,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : _method == _MemberAccessMethod.pvc
                                    ? () => _scanPvc(membership)
                                    : () => _identify(membership),
                            icon: _busy
                                ? const SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _method == _MemberAccessMethod.pvc
                                        ? Icons.document_scanner_outlined
                                        : Icons.person_search_outlined,
                                  ),
                            label: Text(
                              _method == _MemberAccessMethod.pvc
                                  ? 'Scan PVC'
                                  : 'Find account',
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    TgcgSectionCard(
                      title: 'Account found',
                      subtitle:
                          'Confirm this is your USESF member profile before entering your PIN.',
                      trailing: const TgcgStatusPill(
                        label: 'ACCOUNT MATCHED',
                        color: TgcgColors.success,
                        icon: Icons.check_circle_outline_rounded,
                        compact: true,
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: TgcgColors.primarySoft,
                              child: Text(
                                _member!.fullName.isEmpty
                                    ? '?'
                                    : _member!.fullName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: TgcgColors.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            title: Text(
                              _member!.fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              _member!.membershipNumber ?? _member!.id,
                            ),
                          ),
                          if (homePu != null) ...[
                            const Divider(),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.location_on_outlined,
                                color: TgcgColors.accentStrong,
                              ),
                              title: Text(
                                'Home polling unit • ${homePu.displayCode}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(homePu.scope.label),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TgcgSectionCard(
                      title: 'Confirm member PIN',
                      subtitle:
                          'The PIN is checked against a salted derived credential; the raw PIN is not stored.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _pin,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            maxLength: 6,
                            onSubmitted: (_) => _authenticate(membership),
                            decoration: const InputDecoration(
                              labelText: '6-digit PIN',
                              prefixIcon: Icon(Icons.pin_outlined),
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _authenticate(membership),
                            icon: const Icon(Icons.login_rounded),
                            label: const Text('Continue'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _member = null;
                                      _pin.clear();
                                      _message = null;
                                    }),
                            child: const Text('Use another account'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: TgcgColors.warning.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(TgcgRadius.sm),
                        border: Border.all(
                          color: TgcgColors.warning.withValues(alpha: .20),
                        ),
                      ),
                      child: Text(
                        _message!,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _identify(MembershipOperationsController membership) async {
    final identifier = _identifier.text.trim();
    if (identifier.isEmpty) {
      setState(() => _message = 'Enter your registered account identifier.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final member = switch (_method) {
        _MemberAccessMethod.phone => membership.memberByPhone(identifier),
        _MemberAccessMethod.email => membership.memberByEmail(identifier),
        _MemberAccessMethod.pvc => null,
      };
      if (!mounted) return;
      setState(() {
        _member = member;
        if (member == null) {
          _message = 'No enrolled USESF member matched those details.';
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanPvc(MembershipOperationsController membership) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final scan = await _recognizer.captureAndRecognize();
      if (!mounted || scan == null) return;
      final voterId = scan.voterId;
      final member = voterId == null
          ? null
          : await membership.memberByPvcCredential(voterId);
      if (!mounted) return;
      setState(() {
        _pvcScan = scan;
        _member = member;
        if (voterId == null) {
          _message =
              'The PVC was captured, but the enrolled voter identifier could not be read. Try again or use phone/email.';
        } else if (member == null) {
          _message =
              'This PVC did not match an enrolled USESF member credential.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'PVC sign-in could not be completed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _authenticate(
    MembershipOperationsController membership,
  ) async {
    final member = _member;
    if (member == null) return;
    final hasPin = await membership.hasMemberPinCredential(member.id);
    if (!mounted) return;
    if (!hasPin) {
      setState(() {
        _message =
            'This member does not yet have a sign-in PIN. Complete member credential setup at enrolment.';
      });
      return;
    }
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => _message = 'Enter the 6-digit member PIN.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final valid = await membership.verifyMemberPin(
        memberId: member.id,
        pin: pin,
      );
      if (!mounted) return;
      if (!valid) {
        setState(() => _message = 'The member PIN is incorrect.');
        return;
      }

      final session = TgcgSession.of(context, listen: false);
      final approved = membership.approvedAccreditationForMember(member.id);
      final homePu = membership.homePollingUnitForMember(member.id);
      final registration =
          membership.registrationScopeForMember(member.id) ?? GeographicScope.kaduna;

      if (approved != null) {
        session.signIn(
          role: approved.role,
          operatorName: member.fullName,
          accessId: approved.agentId,
          scope: approved.scope,
        );
      } else {
        session.signIn(
          role: TgcgRole.member,
          operatorName: member.fullName,
          accessId: member.id,
          scope: homePu?.scope ?? registration,
        );
      }

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
