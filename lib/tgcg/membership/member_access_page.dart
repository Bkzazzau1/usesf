import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/tgcg_design.dart';
import 'membership_store.dart';

enum _MemberAccessMethod { phone, email, vin }

class MemberAccessPage extends StatefulWidget {
  const MemberAccessPage({super.key});

  @override
  State<MemberAccessPage> createState() => _MemberAccessPageState();
}

class _MemberAccessPageState extends State<MemberAccessPage> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  _MemberAccessMethod _method = _MemberAccessMethod.vin;
  TgcgMember? _member;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final membership = MembershipOperations.of(context);
    final homePu =
        _member == null ? null : membership.homePollingUnitForMember(_member!.id);

    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(title: const Text('Member Access')),
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
                        'Use your PVC/VIN, phone number or email with your password. You do not need to scan the PVC again.',
                    trailing: TgcgStatusPill(
                      label: 'MEMBER FIRST',
                      color: TgcgColors.success,
                      icon: Icons.verified_user_outlined,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TgcgSectionCard(
                    title: 'Sign-in identifier',
                    subtitle:
                        'PVC/VIN remains available even if you have not added a phone number or email.',
                    child: SegmentedButton<_MemberAccessMethod>(
                      segments: const [
                        ButtonSegment(
                          value: _MemberAccessMethod.vin,
                          icon: Icon(Icons.badge_outlined),
                          label: Text('PVC / VIN'),
                        ),
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
                      ],
                      selected: {_method},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) => setState(() {
                                _method = selection.first;
                                _member = null;
                                _identifier.clear();
                                _password.clear();
                                _confirmPassword.clear();
                                _message = null;
                              }),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_member == null)
                    TgcgSectionCard(
                      title: 'Find your member account',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _identifier,
                            enabled: !_busy,
                            keyboardType: _method == _MemberAccessMethod.phone
                                ? TextInputType.phone
                                : _method == _MemberAccessMethod.email
                                    ? TextInputType.emailAddress
                                    : TextInputType.text,
                            textCapitalization:
                                _method == _MemberAccessMethod.vin
                                    ? TextCapitalization.characters
                                    : TextCapitalization.none,
                            onSubmitted: (_) => _identify(membership),
                            decoration: InputDecoration(
                              labelText: switch (_method) {
                                _MemberAccessMethod.phone => 'Phone number',
                                _MemberAccessMethod.email => 'Email address',
                                _MemberAccessMethod.vin => 'PVC / VIN',
                              },
                              prefixIcon: Icon(
                                switch (_method) {
                                  _MemberAccessMethod.phone =>
                                    Icons.phone_outlined,
                                  _MemberAccessMethod.email =>
                                    Icons.email_outlined,
                                  _MemberAccessMethod.vin =>
                                    Icons.badge_outlined,
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed:
                                _busy ? null : () => _identify(membership),
                            icon: _busy
                                ? const SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.person_search_outlined),
                            label: const Text('Find account'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    TgcgSectionCard(
                      title: 'Account found',
                      trailing: TgcgStatusPill(
                        label: _member!.isBlocked
                            ? 'BLOCKED'
                            : _member!.isPendingActivation
                                ? 'PENDING ACTIVATION'
                                : 'ACCOUNT MATCHED',
                        color: _member!.isBlocked
                            ? TgcgColors.danger
                            : _member!.isPendingActivation
                                ? TgcgColors.warning
                                : TgcgColors.success,
                        icon: _member!.isBlocked
                            ? Icons.block_rounded
                            : _member!.isPendingActivation
                                ? Icons.schedule_rounded
                                : Icons.check_circle_outline_rounded,
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
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
                    if (_member!.isPendingActivation)
                      TgcgSectionCard(
                        title: 'Activate account',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _password,
                              enabled: !_busy && !_member!.isBlocked,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Create password',
                                helperText: 'Use at least 8 characters.',
                                prefixIcon: Icon(Icons.lock_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _confirmPassword,
                              enabled: !_busy && !_member!.isBlocked,
                              obscureText: true,
                              onSubmitted: (_) => _activate(membership),
                              decoration: const InputDecoration(
                                labelText: 'Confirm password',
                                prefixIcon:
                                    Icon(Icons.lock_reset_outlined),
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _busy || _member!.isBlocked
                                  ? null
                                  : () => _activate(membership),
                              icon: const Icon(Icons.verified_user_outlined),
                              label: const Text('Activate & continue'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                        _member = null;
                                        _password.clear();
                                        _confirmPassword.clear();
                                        _message = null;
                                      }),
                              child: const Text('Use another account'),
                            ),
                          ],
                        ),
                      )
                    else
                      TgcgSectionCard(
                        title: 'Enter password',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _password,
                              enabled: !_busy && !_member!.isBlocked,
                              obscureText: true,
                              onSubmitted: (_) => _authenticate(membership),
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _busy || _member!.isBlocked
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
                                        _password.clear();
                                        _confirmPassword.clear();
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
      setState(() => _message = 'Enter your account identifier.');
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
        _MemberAccessMethod.vin => await membership.memberByPvcVin(identifier),
      };
      if (!mounted) return;
      setState(() {
        _member = member;
        if (member == null) {
          _message = 'No registered USESF member matched those details.';
        } else if (member.isBlocked) {
          _message =
              'This member account is blocked and cannot sign in. Contact the authorized support channel.';
        } else if (member.isPendingActivation) {
          _message = null;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate(
    MembershipOperationsController membership,
  ) async {
    final member = _member;
    if (member == null || member.isBlocked || !member.isPendingActivation) {
      return;
    }

    final password = _password.text;
    if (password.length < 8) {
      setState(() {
        _message = 'Password must contain at least 8 characters.';
      });
      return;
    }
    if (password != _confirmPassword.text) {
      setState(() {
        _message = 'The passwords do not match.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await membership.setMemberPassword(
        memberId: member.id,
        password: password,
      );
      if (!mounted) return;

      final activated = membership.memberById(member.id);
      if (activated == null || !activated.isActive) {
        setState(() {
          _message = 'Account activation could not be completed.';
        });
        return;
      }

      setState(() => _member = activated);
      await _authenticate(membership);
    } on StateError catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(
          () => _message = error.message?.toString() ?? error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _authenticate(
    MembershipOperationsController membership,
  ) async {
    final member = _member;
    if (member == null || member.isBlocked) return;
    if (member.isPendingActivation) {
      setState(() {
        _message = 'Activate this account by creating a password first.';
      });
      return;
    }

    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _message = 'Enter your member password.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final hasCredential =
          await membership.hasMemberPasswordCredential(member.id);
      if (!mounted) return;
      if (!hasCredential) {
        setState(() {
          _message =
              'This member does not yet have a password. Complete member credential setup.';
        });
        return;
      }

      final valid = await membership.verifyMemberPassword(
        memberId: member.id,
        password: password,
      );
      if (!mounted) return;
      if (!valid) {
        setState(() => _message = 'The password is incorrect.');
        return;
      }

      final homePu = membership.homePollingUnitForMember(member.id);
      final registration =
          membership.registrationScopeForMember(member.id) ??
              GeographicScope.kaduna;

      // Authentication always enters through the permanent member identity.
      // Roles and assignments are resolved after sign-in.
      TgcgSession.of(context, listen: false).signIn(
        role: TgcgRole.member,
        operatorName: member.fullName,
        accessId: member.id,
        scope: homePu?.scope ?? registration,
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
