import 'package:flutter/material.dart';

import '../access/access_policy.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../governance/governance_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'membership_store.dart';

class StateMemberEnrollmentPage extends StatefulWidget {
  const StateMemberEnrollmentPage({
    super.key,
    required this.onAssignRole,
  });

  final ValueChanged<String> onAssignRole;

  @override
  State<StateMemberEnrollmentPage> createState() =>
      _StateMemberEnrollmentPageState();
}

class _StateMemberEnrollmentPageState
    extends State<StateMemberEnrollmentPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _search = TextEditingController();
  TgcgMember? _created;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final governance = GovernanceOperations.of(context);
    final role = TgcgAccessPolicy.roleFor(
      context,
      TgcgCapability.manageMembership,
    );
    final scope = TgcgAccessPolicy.authorizingScope(
      context,
      TgcgCapability.manageMembership,
    );

    if (role != TgcgRole.stateCoordinator ||
        scope == null ||
        scope.level != GeographyLevel.state ||
        scope.stateId != GeographicScope.kaduna.stateId) {
      return const Center(
        child: TgcgEmptyState(
          icon: Icons.person_add_disabled_outlined,
          title: 'Quick enrolment unavailable',
          message: 'State Coordinator authority is required.',
        ),
      );
    }

    final members = membership.membersForScope(scope);
    final pending = members
        .where((item) => item.accountStatus == MemberAccountStatus.pendingActivation)
        .length;
    final active = members
        .where((item) => item.accountStatus == MemberAccountStatus.active)
        .length;
    final withoutRole = members
        .where((item) => governance.activeRolesForMember(item.id).isEmpty)
        .length;

    final query = _search.text.trim().toLowerCase();
    final filtered = members.where((member) {
      if (query.isEmpty) return true;
      final roles = governance
          .activeRolesForMember(member.id)
          .map((item) => roleLabel(item.role))
          .join(' ');
      final haystack = [
        member.fullName,
        member.phoneNumber,
        member.email,
        member.membershipNumber,
        member.id,
        roles,
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);

    final canSubmit = !_busy &&
        _name.text.trim().isNotEmpty &&
        (_phone.text.trim().isNotEmpty || _email.text.trim().isNotEmpty);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'STATE MEMBERSHIP',
          title: 'Member Enrolment',
          subtitle: scope.label,
          trailing: const TgcgStatusPill(
            label: 'STATE COORDINATOR',
            color: TgcgColors.primary,
            icon: Icons.manage_accounts_outlined,
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 520
                    ? 2
                    : 1;
            const gap = 10.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                TgcgMetricCard(
                  width: width,
                  label: 'Members',
                  value: '${members.length}',
                  detail: 'State register',
                  icon: Icons.groups_outlined,
                  tone: TgcgMetricTone.info,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Pending activation',
                  value: '$pending',
                  detail: 'Password not set',
                  icon: Icons.schedule_rounded,
                  tone: pending == 0
                      ? TgcgMetricTone.success
                      : TgcgMetricTone.warning,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Active',
                  value: '$active',
                  detail: 'Login ready',
                  icon: Icons.verified_user_outlined,
                  tone: TgcgMetricTone.success,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Without role',
                  value: '$withoutRole',
                  detail: 'No active role',
                  icon: Icons.person_search_outlined,
                  tone: withoutRole == 0
                      ? TgcgMetricTone.success
                      : TgcgMetricTone.neutral,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final addMember = TgcgSectionCard(
              title: 'Add member',
              child: Column(
                children: [
                  TextField(
                    controller: _name,
                    enabled: !_busy && _created == null,
                    onChanged: (_) => setState(() {}),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phone,
                    enabled: !_busy && _created == null,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _email,
                    enabled: !_busy && _created == null,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_created == null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: canSubmit
                            ? () => _createMember(
                                  membership,
                                  session,
                                  scope,
                                )
                            : null,
                        icon: _busy
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Create member'),
                      ),
                    )
                  else
                    _CreatedMemberCard(
                      member: _created!,
                      onAssignRole: () =>
                          widget.onAssignRole(_created!.id),
                      onNext: _reset,
                    ),
                ],
              ),
            );

            final registry = _MemberRegistry(
              members: filtered,
              governance: governance,
              search: _search,
              onSearch: (_) => setState(() {}),
              onAssignRole: widget.onAssignRole,
            );

            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  addMember,
                  const SizedBox(height: 16),
                  registry,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: addMember),
                const SizedBox(width: 16),
                Expanded(flex: 7, child: registry),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _createMember(
    MembershipOperationsController membership,
    TgcgSessionController session,
    GeographicScope scope,
  ) async {
    setState(() => _busy = true);
    try {
      final member = await membership.createStateCoordinatorMember(
        fullName: _name.text,
        phoneNumber: _phone.text,
        email: _email.text,
        createdBy:
            session.accessId.isEmpty ? session.operatorName : session.accessId,
        createdByRole: TgcgRole.stateCoordinator,
        authorizedScope: scope,
      );
      if (!mounted) return;
      setState(() => _created = member);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${member.fullName} created as ${member.membershipNumber ?? member.id}.',
          ),
        ),
      );
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message?.toString() ?? error.toString()),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    setState(() {
      _created = null;
      _name.clear();
      _phone.clear();
      _email.clear();
    });
  }
}

class _CreatedMemberCard extends StatelessWidget {
  const _CreatedMemberCard({
    required this.member,
    required this.onAssignRole,
    required this.onNext,
  });

  final TgcgMember member;
  final VoidCallback onAssignRole;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TgcgColors.success.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          border: Border.all(
            color: TgcgColors.success.withValues(alpha: .24),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: TgcgColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    member.fullName,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const TgcgStatusPill(
                  label: 'PENDING ACTIVATION',
                  color: TgcgColors.warning,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              member.membershipNumber ?? member.id,
              style: const TextStyle(
                color: TgcgColors.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAssignRole,
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Assign role'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onNext,
                    icon: const Icon(Icons.person_add_alt_rounded),
                    label: const Text('Next member'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _MemberRegistry extends StatelessWidget {
  const _MemberRegistry({
    required this.members,
    required this.governance,
    required this.search,
    required this.onSearch,
    required this.onAssignRole,
  });

  final List<TgcgMember> members;
  final GovernanceOperationsController governance;
  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onAssignRole;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Member register',
        trailing: SizedBox(
          width: 260,
          child: TextField(
            controller: search,
            onChanged: onSearch,
            decoration: const InputDecoration(
              hintText: 'Search members',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
        ),
        child: members.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.group_off_outlined,
                title: 'No matching members',
                message: 'Change the search.',
              )
            : Column(
                children: [
                  for (final member in members)
                    _MemberRow(
                      member: member,
                      roles: governance.activeRolesForMember(member.id),
                      onAssignRole: () => onAssignRole(member.id),
                    ),
                ],
              ),
      );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.roles,
    required this.onAssignRole,
  });

  final TgcgMember member;
  final List<RoleAssignmentRecord> roles;
  final VoidCallback onAssignRole;

  @override
  Widget build(BuildContext context) {
    final contact = member.phoneNumber.trim().isNotEmpty
        ? member.phoneNumber
        : member.email ?? 'No contact';
    final statusColor = switch (member.accountStatus) {
      MemberAccountStatus.pendingActivation => TgcgColors.warning,
      MemberAccountStatus.active => TgcgColors.success,
      MemberAccountStatus.blocked => TgcgColors.danger,
    };
    final statusLabel = switch (member.accountStatus) {
      MemberAccountStatus.pendingActivation => 'PENDING',
      MemberAccountStatus.active => 'ACTIVE',
      MemberAccountStatus.blocked => 'BLOCKED',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TgcgRadius.sm),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: TgcgColors.primarySoft,
            child: Text(
              member.fullName.isEmpty
                  ? '?'
                  : member.fullName[0].toUpperCase(),
              style: const TextStyle(
                color: TgcgColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.fullName,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${member.membershipNumber ?? member.id} • $contact',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    TgcgStatusPill(
                      label: statusLabel,
                      color: statusColor,
                      compact: true,
                    ),
                    TgcgStatusPill(
                      label: roles.isEmpty
                          ? 'NO ROLE'
                          : '${roles.length} ROLE${roles.length == 1 ? '' : 'S'}',
                      color: roles.isEmpty
                          ? TgcgColors.muted
                          : TgcgColors.info,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onAssignRole,
            icon: const Icon(Icons.admin_panel_settings_outlined, size: 17),
            label: const Text('Assign role'),
          ),
        ],
      ),
    );
  }
}
