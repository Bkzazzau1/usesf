import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'governance_store.dart';

class RoleAssignmentPage extends StatefulWidget {
  const RoleAssignmentPage({super.key});

  @override
  State<RoleAssignmentPage> createState() => _RoleAssignmentPageState();
}

class _RoleAssignmentPageState extends State<RoleAssignmentPage> {
  String? selectedMemberId;
  TgcgRole selectedRole = TgcgRole.stateCoordinator;
  String? selectedScopeKey;
  String search = '';

  static const assignableRoles = <TgcgRole>[
    TgcgRole.senatorialCoordinator,
    TgcgRole.lgaCoordinator,
    TgcgRole.wardCoordinator,
    TgcgRole.pollingUnitCoordinator,
    TgcgRole.pollingUnitAgent,
    TgcgRole.mediaOfficer,
    TgcgRole.womenMobilizationCoordinator,
    TgcgRole.youthMobilizationCoordinator,
    TgcgRole.communicationsOfficer,
    TgcgRole.logisticsOfficer,
    TgcgRole.monitoringEvaluationOfficer,
    TgcgRole.dataEvidenceOfficer,
    TgcgRole.transportCoordinator,
    TgcgRole.trainingOfficer,
    TgcgRole.ictOfficer,
    TgcgRole.observer,
    TgcgRole.legalOfficer,
    TgcgRole.technicalSupport,
    TgcgRole.readOnlyExecutive,
  ];

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final governance = GovernanceOperations.of(context);

    final currentRole = session.role!;
    final canAssignRoles = TgcgPermissionPolicy.allows(
      currentRole,
      TgcgCapability.manageRoleAssignments,
    );
    if (!canAssignRoles) {
      return const Center(
        child: TgcgEmptyState(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Role assignment not available',
          message:
              'Only coordinators with role-assignment authority can manage member roles.',
        ),
      );
    }

    final permittedRoles = _rolesAssignableBy(currentRole);
    if (permittedRoles.isNotEmpty && !permittedRoles.contains(selectedRole)) {
      selectedRole = permittedRoles.first;
      selectedScopeKey = null;
    }

    final members = membership.members.where((member) {
      final memberScope = membership.registrationScopeForMember(member.id);
      return memberScope != null &&
          TgcgPermissionPolicy.scopeAllows(session.scope, memberScope);
    }).toList(growable: false);
    if (selectedMemberId == null ||
        !members.any((item) => item.id == selectedMemberId)) {
      selectedMemberId = members.isEmpty ? null : members.first.id;
    }

    final scopes = _scopeOptions(
      membership,
      selectedRole,
      session.scope,
    );
    if (scopes.isNotEmpty &&
        !scopes.any((item) => item.key == selectedScopeKey)) {
      selectedScopeKey = scopes.first.key;
    }

    final assignments = governance.roleAssignmentsForScope(session.scope)
        .where((item) =>
            search.trim().isEmpty ||
            item.subjectName.toLowerCase().contains(search.toLowerCase()) ||
            roleLabel(item.role).toLowerCase().contains(search.toLowerCase()) ||
            item.scope.label.toLowerCase().contains(search.toLowerCase()))
        .toList(growable: false);

    final active = governance.roleAssignments.where((item) => item.active).length;
    final stateWide = governance.roleAssignments
        .where((item) => item.active && item.scope.level == GeographyLevel.state)
        .length;
    final field = governance.roleAssignments
        .where((item) =>
            item.active &&
            (item.role == TgcgRole.pollingUnitAgent ||
                item.role == TgcgRole.wardCoordinator ||
                item.role == TgcgRole.lgaCoordinator))
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'MEMBER ROLE CONTROL',
          title: 'Roles & Authorization',
          subtitle:
              'Every person is a member first. Assign one or more operational roles only within your authority and geographic scope.',
          trailing: TgcgStatusPill(
            label: roleLabel(currentRole).toUpperCase(),
            color: TgcgColors.primary,
            icon: roleIcon(currentRole),
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(active: active, stateWide: stateWide, field: field),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final form = _AssignmentForm(
              members: members,
              selectedMemberId: selectedMemberId,
              selectedRole: selectedRole,
              assignableRoles: permittedRoles,
              scopes: scopes,
              selectedScopeKey: selectedScopeKey,
              onMemberChanged: (value) => setState(() => selectedMemberId = value),
              onRoleChanged: (value) => setState(() {
                selectedRole = value;
                selectedScopeKey = null;
              }),
              onScopeChanged: (value) => setState(() => selectedScopeKey = value),
              onAssign: () => _assign(context, session, membership, governance, scopes),
            );
            final preview = _PermissionPreview(role: selectedRole);
            if (constraints.maxWidth < 980) {
              return Column(
                children: [form, const SizedBox(height: 16), preview],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: form),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: preview),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        TgcgSectionCard(
          title: 'Current role assignments',
          subtitle: 'Active and recently changed access records.',
          trailing: SizedBox(
            width: 260,
            child: TextField(
              onChanged: (value) => setState(() => search = value),
              decoration: const InputDecoration(
                hintText: 'Search assignments',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          child: assignments.isEmpty
              ? const TgcgEmptyState(
                  icon: Icons.manage_accounts_outlined,
                  title: 'No matching assignments',
                  message: 'Role assignments will appear here.',
                )
              : Column(
                  children: assignments
                      .map(
                        (item) => _AssignmentRow(
                          item: item,
                          onRevoke: item.active &&
                                  _mayRevokeRole(session, item)
                              ? () {
                                  final actorId = session.accessId.isEmpty
                                      ? session.operatorName
                                      : session.accessId;
                                  governance.revokeRole(
                                    item.id,
                                    actorId: actorId,
                                    allowStateOverride:
                                        session.role == TgcgRole.stateCoordinator ||
                                            session.role ==
                                                TgcgRole.stateAdministrator,
                                  );
                                }
                              : null,
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  void _assign(
    BuildContext context,
    TgcgSessionController session,
    MembershipOperationsController membership,
    GovernanceOperationsController governance,
    List<_ScopeOption> scopes,
  ) {
    final memberId = selectedMemberId;
    final scopeKey = selectedScopeKey;
    if (memberId == null || scopeKey == null) return;
    final member = membership.memberById(memberId);
    final scope = scopes.where((item) => item.key == scopeKey).firstOrNull;
    if (member == null || scope == null) return;

    governance.assignRole(
      subjectId: member.id,
      subjectName: member.fullName,
      role: selectedRole,
      scope: scope.scope,
      assignedBy: session.accessId.isEmpty ? session.operatorName : session.accessId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${roleLabel(selectedRole)} assigned to ${member.fullName} for ${scope.label}.',
        ),
      ),
    );
    setState(() {});
  }

  List<_ScopeOption> _scopeOptions(
    MembershipOperationsController membership,
    TgcgRole role,
  ) {
    final geography = membership.geography;
    switch (role) {
      case TgcgRole.senatorialCoordinator:
        return geography.senatorialDistricts
            .map((item) => _ScopeOption(item.id, item.name, item.scope))
            .toList(growable: false);
      case TgcgRole.lgaCoordinator:
        return geography.lgas
            .map(
              (item) => _ScopeOption(
                item.id,
                '${item.name} • ${item.senatorialDistrictName}',
                item.scope,
              ),
            )
            .toList(growable: false);
      case TgcgRole.wardCoordinator:
        final seen = <String>{};
        return geography.pollingUnits
            .map((item) => item.scope)
            .where((scope) => scope.wardId != null && seen.add(scope.wardId!))
            .map(
              (scope) => _ScopeOption(
                scope.wardId!,
                '${scope.wardName ?? 'Ward'} • ${scope.lgaName ?? ''} LGA',
                GeographicScope(
                  level: GeographyLevel.ward,
                  country: scope.country,
                  zoneId: scope.zoneId,
                  zoneName: scope.zoneName,
                  stateId: scope.stateId,
                  stateName: scope.stateName,
                  senatorialDistrictId: scope.senatorialDistrictId,
                  senatorialDistrictName: scope.senatorialDistrictName,
                  lgaId: scope.lgaId,
                  lgaName: scope.lgaName,
                  wardId: scope.wardId,
                  wardName: scope.wardName,
                ),
              ),
            )
            .toList(growable: false);
      case TgcgRole.pollingUnitAgent:
        return geography.pollingUnits
            .map(
              (item) => _ScopeOption(
                item.code,
                '${item.scope.pollingUnitName ?? item.code} • ${item.scope.wardName ?? ''} • ${item.scope.lgaName ?? ''}',
                item.scope,
              ),
            )
            .toList(growable: false);
      default:
        return const [
          _ScopeOption('KD', 'Kaduna State', GeographicScope.kaduna),
        ];
    }
  }
}

class _AssignmentForm extends StatelessWidget {
  const _AssignmentForm({
    required this.members,
    required this.selectedMemberId,
    required this.selectedRole,
    required this.scopes,
    required this.selectedScopeKey,
    required this.onMemberChanged,
    required this.onRoleChanged,
    required this.onScopeChanged,
    required this.onAssign,
  });

  final List<TgcgMember> members;
  final String? selectedMemberId;
  final TgcgRole selectedRole;
  final List<_ScopeOption> scopes;
  final String? selectedScopeKey;
  final ValueChanged<String?> onMemberChanged;
  final ValueChanged<TgcgRole> onRoleChanged;
  final ValueChanged<String?> onScopeChanged;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Assign operational role',
        subtitle: 'Choose a registered person, responsibility and geographic scope.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedMemberId,
              decoration: const InputDecoration(
                labelText: 'Registered person',
                prefixIcon: Icon(Icons.person_search_outlined),
              ),
              items: members
                  .map(
                    (member) => DropdownMenuItem(
                      value: member.id,
                      child: Text('${member.fullName} • ${member.membershipNumber}'),
                    ),
                  )
                  .toList(),
              onChanged: onMemberChanged,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<TgcgRole>(
              initialValue: selectedRole,
              decoration: const InputDecoration(
                labelText: 'Role',
                prefixIcon: Icon(Icons.manage_accounts_outlined),
              ),
              items: _RoleAssignmentPageState.assignableRoles
                  .map(
                    (role) => DropdownMenuItem(
                      value: role,
                      child: Text(roleLabel(role)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onRoleChanged(value);
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey('${selectedRole.name}-$selectedScopeKey'),
              initialValue: selectedScopeKey,
              decoration: const InputDecoration(
                labelText: 'Operational scope',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              items: scopes
                  .map(
                    (scope) => DropdownMenuItem(
                      value: scope.key,
                      child: Text(scope.label),
                    ),
                  )
                  .toList(),
              onChanged: onScopeChanged,
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [TgcgColors.gold100, TgcgColors.navy50],
                ),
                borderRadius: BorderRadius.circular(TgcgRadius.md),
                border: Border.all(color: TgcgColors.gold200),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.security_rounded, color: TgcgColors.accentStrong, size: 20),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'The assignment is recorded immediately with actor, role, scope and audit history. Production identity provisioning can be connected later without changing this workflow.',
                      style: TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: members.isEmpty || scopes.isEmpty ? null : onAssign,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Assign Role'),
              ),
            ),
          ],
        ),
      );
}

class _PermissionPreview extends StatelessWidget {
  const _PermissionPreview({required this.role});
  final TgcgRole role;

  @override
  Widget build(BuildContext context) {
    final permissions = TgcgPermissionPolicy.capabilitiesFor(role).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return TgcgSectionCard(
      title: roleLabel(role),
      subtitle: roleDescription(role),
      trailing: Icon(roleIcon(role), color: TgcgColors.primary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACCESS PREVIEW',
            style: TextStyle(
              color: TgcgColors.primaryMid,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: permissions
                .take(10)
                .map(
                  (capability) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: TgcgColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: TgcgColors.border),
                    ),
                    child: Text(
                      _humanize(capability.name),
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          if (permissions.length > 10) ...[
            const SizedBox(height: 9),
            Text(
              '+${permissions.length - 10} additional permissions',
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.active, required this.stateWide, required this.field});
  final int active;
  final int stateWide;
  final int field;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760 ? 3 : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Active assignments',
                value: '$active',
                detail: 'Currently authorized role records',
                icon: Icons.verified_user_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'State-wide roles',
                value: '$stateWide',
                detail: 'Assignments covering all of Kaduna State',
                icon: Icons.public_rounded,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Field roles',
                value: '$field',
                detail: 'LGA, ward and polling-unit responsibilities',
                icon: Icons.how_to_vote_outlined,
                tone: TgcgMetricTone.neutral,
              ),
            ],
          );
        },
      );
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({required this.item, required this.onRevoke});
  final RoleAssignmentRecord item;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [TgcgColors.surface, TgcgColors.navy50],
          ),
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: TgcgColors.accentSoft,
                borderRadius: BorderRadius.circular(TgcgRadius.sm),
                border: Border.all(color: TgcgColors.gold200),
              ),
              child: Icon(roleIcon(item.role), color: TgcgColors.accentStrong, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.subjectName,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${roleLabel(item.role)} • ${item.scope.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            TgcgStatusPill(
              label: item.active ? 'ACTIVE' : 'REVOKED',
              color: item.active ? TgcgColors.success : TgcgColors.muted,
              compact: true,
            ),
            if (onRevoke != null) ...[
              const SizedBox(width: 6),
              TextButton(
                onPressed: onRevoke,
                child: const Text('Revoke'),
              ),
            ],
          ],
        ),
      );
}

class _ScopeOption {
  const _ScopeOption(this.key, this.label, this.scope);
  final String key;
  final String label;
  final GeographicScope scope;
}

String _humanize(String value) => value
    .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .replaceAll('_', ' ')
    .trim()
    .split(' ')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
