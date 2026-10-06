import 'package:flutter/material.dart';

import '../assignments/assignment_store.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../membership/membership_intelligence_page.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../sync/sync_models.dart';
import '../ui/tgcg_design.dart';
import 'governance_store.dart';

enum StateGovernanceRiskKind {
  vacantLeadership,
  duplicateLeadershipHolder,
  coordinatorScopeMismatch,
  blockedAuthority,
  pendingActivationAuthority,
  identityReviewAuthority,
  multipleCoordinatorPosts,
  orphanRoleRecord,
  syncFailure,
  syncConflict,
  disabledSafeguard,
}

enum StateGovernanceRiskSeverity { info, warning, critical }

class StateGovernanceRisk {
  const StateGovernanceRisk({
    required this.kind,
    required this.severity,
    required this.title,
    required this.detail,
    required this.module,
    this.scope,
    this.memberId,
  });

  final StateGovernanceRiskKind kind;
  final StateGovernanceRiskSeverity severity;
  final String title;
  final String detail;
  final TgcgModule module;
  final GeographicScope? scope;
  final String? memberId;
}

class RoleAuthoritySummary {
  const RoleAuthoritySummary({
    required this.role,
    required this.activeAssignments,
    required this.distinctHolders,
  });

  final TgcgRole role;
  final int activeAssignments;
  final int distinctHolders;
}

class StateGovernanceSnapshot {
  const StateGovernanceSnapshot({
    required this.leadership,
    required this.leadershipVacancies,
    required this.activeRoles,
    required this.distinctRoleHolders,
    required this.roleSummaries,
    required this.temporaryAccessAssignments,
    required this.settings,
    required this.syncQueued,
    required this.syncing,
    required this.syncFailed,
    required this.syncConflicts,
    required this.risks,
  });

  final LeadershipCoverageSummary leadership;
  final List<LeadershipVacancy> leadershipVacancies;
  final List<RoleAssignmentRecord> activeRoles;
  final int distinctRoleHolders;
  final List<RoleAuthoritySummary> roleSummaries;
  final List<MemberAssignment> temporaryAccessAssignments;
  final List<SystemSettingRecord> settings;
  final int syncQueued;
  final int syncing;
  final int syncFailed;
  final int syncConflicts;
  final List<StateGovernanceRisk> risks;

  int get safeguardsEnabled => settings.where((item) => item.value).length;

  int get criticalRisks => risks
      .where((item) => item.severity == StateGovernanceRiskSeverity.critical)
      .length;

  int get warningRisks => risks
      .where((item) => item.severity == StateGovernanceRiskSeverity.warning)
      .length;
}

StateGovernanceSnapshot buildStateGovernanceSnapshot({
  required MembershipOperationsController membership,
  required GovernanceOperationsController governance,
  required AssignmentController assignments,
}) {
  final leadership = buildLeadershipCoverage(
    membership: membership,
    governance: governance,
  );
  final vacancies = buildLeadershipVacancies(
    membership: membership,
    governance: governance,
  );
  final activeRoles = governance.roleAssignments
      .where((item) => item.active)
      .toList(growable: false);

  final roleGroups = <TgcgRole, List<RoleAssignmentRecord>>{};
  for (final record in activeRoles) {
    roleGroups.putIfAbsent(record.role, () => []).add(record);
  }
  final roleSummaries = roleGroups.entries
      .map(
        (entry) => RoleAuthoritySummary(
          role: entry.key,
          activeAssignments: entry.value.length,
          distinctHolders:
              entry.value.map((item) => item.subjectId).toSet().length,
        ),
      )
      .toList(growable: false)
    ..sort((a, b) {
      final count = b.activeAssignments.compareTo(a.activeAssignments);
      return count != 0
          ? count
          : _roleLabel(a.role).compareTo(_roleLabel(b.role));
    });

  final temporaryAccess = assignments.assignments
      .where(
        (item) =>
            item.confersAccess &&
            item.grantedCapabilities.isNotEmpty,
      )
      .toList(growable: false)
    ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

  final risks = <StateGovernanceRisk>[];

  final vacanciesByRole = <TgcgRole, int>{};
  for (final vacancy in vacancies) {
    vacanciesByRole.update(
      vacancy.role,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }
  for (final entry in vacanciesByRole.entries) {
    risks.add(
      StateGovernanceRisk(
        kind: StateGovernanceRiskKind.vacantLeadership,
        severity: StateGovernanceRiskSeverity.warning,
        title: '${_roleLabel(entry.key)} vacancies',
        detail: '${entry.value} leadership post(s) are vacant.',
        module: TgcgModule.roleAssignment,
      ),
    );
  }

  final leadershipPosts = <String, List<RoleAssignmentRecord>>{};
  for (final record in activeRoles.where(
    (item) => _isCoordinatorRole(item.role),
  )) {
    final key = '${record.role.name}:${_scopeKey(record.scope)}';
    leadershipPosts.putIfAbsent(key, () => []).add(record);

    final expected = _expectedScopeLevel(record.role);
    if (expected != null && record.scope.level != expected) {
      risks.add(
        StateGovernanceRisk(
          kind: StateGovernanceRiskKind.coordinatorScopeMismatch,
          severity: StateGovernanceRiskSeverity.critical,
          title: 'Coordinator scope mismatch',
          detail:
              '${record.subjectName} holds ${_roleLabel(record.role)} at ${record.scope.label}.',
          module: TgcgModule.roleAssignment,
          scope: record.scope,
          memberId: record.subjectId,
        ),
      );
    }
  }
  for (final records in leadershipPosts.values) {
    final holders = records.map((item) => item.subjectId).toSet();
    if (holders.length <= 1) continue;
    final first = records.first;
    risks.add(
      StateGovernanceRisk(
        kind: StateGovernanceRiskKind.duplicateLeadershipHolder,
        severity: StateGovernanceRiskSeverity.critical,
        title: 'Multiple holders for one leadership post',
        detail:
            '${_roleLabel(first.role)} • ${first.scope.label} has ${holders.length} active holders.',
        module: TgcgModule.roleAssignment,
        scope: first.scope,
      ),
    );
  }

  final rolesByMember = <String, List<RoleAssignmentRecord>>{};
  for (final record in activeRoles) {
    rolesByMember.putIfAbsent(record.subjectId, () => []).add(record);
  }

  for (final entry in rolesByMember.entries) {
    final member = membership.memberById(entry.key);
    if (member == null) {
      risks.add(
        StateGovernanceRisk(
          kind: StateGovernanceRiskKind.orphanRoleRecord,
          severity: StateGovernanceRiskSeverity.critical,
          title: 'Role record has no member identity',
          detail:
              '${entry.value.length} active role grant(s) reference missing member ${entry.key}.',
          module: TgcgModule.roleAssignment,
          memberId: entry.key,
        ),
      );
      continue;
    }

    if (member.isBlocked) {
      risks.add(
        StateGovernanceRisk(
          kind: StateGovernanceRiskKind.blockedAuthority,
          severity: StateGovernanceRiskSeverity.critical,
          title: 'Blocked member still holds authority',
          detail:
              '${member.fullName} has ${entry.value.length} active role grant(s).',
          module: TgcgModule.roleAssignment,
          memberId: member.id,
        ),
      );
    } else if (member.isPendingActivation) {
      risks.add(
        StateGovernanceRisk(
          kind: StateGovernanceRiskKind.pendingActivationAuthority,
          severity: StateGovernanceRiskSeverity.warning,
          title: 'Pending Activation member holds authority',
          detail:
              '${member.fullName} has ${entry.value.length} active role grant(s).',
          module: TgcgModule.membershipNetwork,
          memberId: member.id,
        ),
      );
    } else if (!memberIdentityReady(member)) {
      risks.add(
        StateGovernanceRisk(
          kind: StateGovernanceRiskKind.identityReviewAuthority,
          severity: StateGovernanceRiskSeverity.warning,
          title: 'Identity review member holds authority',
          detail:
              '${member.fullName} has active authority before identity review is complete.',
          module: TgcgModule.aiVerification,
          memberId: member.id,
        ),
      );
    }

    final coordinatorRoles = entry.value
        .where((item) => _isCoordinatorRole(item.role))
        .toList(growable: false);
    if (coordinatorRoles.length > 1) {
      risks.add(
        StateGovernanceRisk(
          kind: StateGovernanceRiskKind.multipleCoordinatorPosts,
          severity: StateGovernanceRiskSeverity.warning,
          title: 'Multiple coordinator posts',
          detail:
              '${member.fullName} holds ${coordinatorRoles.length} active coordinator roles.',
          module: TgcgModule.roleAssignment,
          memberId: member.id,
        ),
      );
    }
  }

  int syncCount(SyncState state) =>
      governance.outbox.where((item) => item.state == state).length;
  final failed = syncCount(SyncState.failed);
  final conflicts = syncCount(SyncState.conflict);

  if (failed > 0) {
    risks.add(
      StateGovernanceRisk(
        kind: StateGovernanceRiskKind.syncFailure,
        severity: StateGovernanceRiskSeverity.warning,
        title: 'Durable sync failures',
        detail:
            '$failed local mutation(s) are retained but have failed transport.',
        module: TgcgModule.systemMonitoring,
      ),
    );
  }
  if (conflicts > 0) {
    risks.add(
      StateGovernanceRisk(
        kind: StateGovernanceRiskKind.syncConflict,
        severity: StateGovernanceRiskSeverity.critical,
        title: 'Sync reconciliation conflicts',
        detail:
            '$conflicts mutation(s) require backend reconciliation.',
        module: TgcgModule.systemMonitoring,
      ),
    );
  }

  for (final setting in governance.settings.where((item) => !item.value)) {
    risks.add(
      StateGovernanceRisk(
        kind: StateGovernanceRiskKind.disabledSafeguard,
        severity: StateGovernanceRiskSeverity.critical,
        title: 'Protected safeguard disabled',
        detail: setting.label,
        module: TgcgModule.systemMonitoring,
      ),
    );
  }

  risks.sort((a, b) {
    final severity =
        _severityOrder(a.severity).compareTo(_severityOrder(b.severity));
    if (severity != 0) return severity;
    return a.title.compareTo(b.title);
  });

  return StateGovernanceSnapshot(
    leadership: leadership,
    leadershipVacancies: List.unmodifiable(vacancies),
    activeRoles: List.unmodifiable(activeRoles),
    distinctRoleHolders:
        activeRoles.map((item) => item.subjectId).toSet().length,
    roleSummaries: List.unmodifiable(roleSummaries),
    temporaryAccessAssignments: List.unmodifiable(temporaryAccess),
    settings: List.unmodifiable(governance.settings),
    syncQueued: syncCount(SyncState.queued),
    syncing: syncCount(SyncState.syncing),
    syncFailed: failed,
    syncConflicts: conflicts,
    risks: List.unmodifiable(risks),
  );
}

class StateGovernanceControlPage extends StatefulWidget {
  const StateGovernanceControlPage({
    super.key,
    required this.onOpenModule,
    required this.onManageMemberRole,
  });

  final ValueChanged<TgcgModule> onOpenModule;
  final ValueChanged<String> onManageMemberRole;

  @override
  State<StateGovernanceControlPage> createState() =>
      _StateGovernanceControlPageState();
}

class _StateGovernanceControlPageState
    extends State<StateGovernanceControlPage> {
  final _roleSearch = TextEditingController();
  TgcgRole? _roleFilter;

  @override
  void dispose() {
    _roleSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (session.role != TgcgRole.stateCoordinator) {
      return const Center(
        child: TgcgEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'State Governance Control unavailable',
          message: 'State Coordinator authority is required.',
        ),
      );
    }

    final membership = MembershipOperations.of(context);
    final governance = GovernanceOperations.of(context);
    final assignments = Assignments.of(context);

    final snapshot = buildStateGovernanceSnapshot(
      membership: membership,
      governance: governance,
      assignments: assignments,
    );

    final query = _roleSearch.text.trim().toLowerCase();
    final visibleRoles = snapshot.activeRoles.where((record) {
      if (_roleFilter != null && record.role != _roleFilter) return false;
      if (query.isEmpty) return true;
      return [
        record.subjectName,
        record.subjectId,
        _roleLabel(record.role),
        record.scope.label,
        record.assignedBy,
      ].join(' ').toLowerCase().contains(query);
    }).toList(growable: false);

    final availableRoles = snapshot.activeRoles
        .map((item) => item.role)
        .toSet()
        .toList(growable: false)
      ..sort(
        (a, b) => _roleLabel(a).compareTo(_roleLabel(b)),
      );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'STATE AUTHORITY & ACCOUNTABILITY',
          title: 'State Governance Control',
          subtitle: GeographicScope.kaduna.label,
          trailing: TgcgStatusPill(
            label: snapshot.criticalRisks > 0
                ? '${snapshot.criticalRisks} CRITICAL'
                : 'GOVERNANCE STABLE',
            color: snapshot.criticalRisks > 0
                ? TgcgColors.danger
                : TgcgColors.success,
            icon: Icons.policy_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _GovernanceMetrics(snapshot: snapshot),
        const SizedBox(height: 16),
        _GovernanceCommandActions(onOpen: widget.onOpenModule),
        const SizedBox(height: 16),
        _GovernanceRiskPanel(
          risks: snapshot.risks.take(14).toList(growable: false),
          total: snapshot.risks.length,
          onOpen: (risk) {
            if (risk.memberId != null &&
                risk.module == TgcgModule.roleAssignment) {
              widget.onManageMemberRole(risk.memberId!);
              return;
            }
            widget.onOpenModule(risk.module);
          },
        ),
        const SizedBox(height: 16),
        _LeadershipGovernancePanel(
          snapshot: snapshot,
          onOpenRoles: () =>
              widget.onOpenModule(TgcgModule.roleAssignment),
          onOpenCoverage: () =>
              widget.onOpenModule(TgcgModule.geography),
        ),
        const SizedBox(height: 16),
        _RoleDistributionPanel(summaries: snapshot.roleSummaries),
        const SizedBox(height: 16),
        _TemporaryAuthorityPanel(
          assignments: snapshot.temporaryAccessAssignments,
          membership: membership,
          onOpenAssignments: () =>
              widget.onOpenModule(TgcgModule.assignmentControl),
        ),
        const SizedBox(height: 16),
        _ProtectedControlPanel(snapshot: snapshot),
        const SizedBox(height: 16),
        _RoleAuthorityRegister(
          records: visibleRoles,
          roles: availableRoles,
          search: _roleSearch,
          filter: _roleFilter,
          onSearch: (_) => setState(() {}),
          onRole: (value) => setState(() => _roleFilter = value),
          onClear: () {
            _roleSearch.clear();
            setState(() => _roleFilter = null);
          },
          onManage: widget.onManageMemberRole,
        ),
      ],
    );
  }
}

class _GovernanceMetrics extends StatelessWidget {
  const _GovernanceMetrics({required this.snapshot});

  final StateGovernanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1100
              ? 6
              : constraints.maxWidth >= 720
                  ? 3
                  : constraints.maxWidth >= 460
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
                label: 'Active role grants',
                value: '${snapshot.activeRoles.length}',
                detail: '${snapshot.distinctRoleHolders} distinct holders',
                icon: Icons.verified_user_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'LGA leadership',
                value:
                    '${snapshot.leadership.lgaFilled}/${snapshot.leadership.lgaExpected}',
                detail: 'Coordinator posts filled',
                icon: Icons.account_tree_outlined,
                tone: snapshot.leadership.lgaFilled ==
                        snapshot.leadership.lgaExpected
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Governance risks',
                value: '${snapshot.risks.length}',
                detail:
                    '${snapshot.criticalRisks} critical • ${snapshot.warningRisks} warning',
                icon: Icons.gpp_maybe_outlined,
                tone: snapshot.criticalRisks > 0
                    ? TgcgMetricTone.danger
                    : snapshot.warningRisks > 0
                        ? TgcgMetricTone.warning
                        : TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Temporary authority',
                value: '${snapshot.temporaryAccessAssignments.length}',
                detail: 'Active assignment-granted access',
                icon: Icons.key_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Sync assurance',
                value: '${snapshot.syncFailed + snapshot.syncConflicts}',
                detail:
                    '${snapshot.syncFailed} failed • ${snapshot.syncConflicts} conflict',
                icon: Icons.sync_problem_outlined,
                tone: snapshot.syncFailed + snapshot.syncConflicts == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Safeguards',
                value:
                    '${snapshot.safeguardsEnabled}/${snapshot.settings.length}',
                detail: 'Protected controls enabled',
                icon: Icons.security_outlined,
                tone: snapshot.safeguardsEnabled == snapshot.settings.length
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.danger,
              ),
            ],
          );
        },
      );
}

class _GovernanceCommandActions extends StatelessWidget {
  const _GovernanceCommandActions({required this.onOpen});

  final ValueChanged<TgcgModule> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Governance workspaces',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.roleAssignment),
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('Roles & Authorization'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.membershipNetwork),
              icon: const Icon(Icons.groups_2_outlined),
              label: const Text('Membership Intelligence'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.geography),
              icon: const Icon(Icons.public_outlined),
              label: const Text('State Coverage'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.assignmentControl),
              icon: const Icon(Icons.assignment_ind_outlined),
              label: const Text('Assignment Control'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.aiVerification),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('AI Review'),
            ),
          ],
        ),
      );
}

class _GovernanceRiskPanel extends StatelessWidget {
  const _GovernanceRiskPanel({
    required this.risks,
    required this.total,
    required this.onOpen,
  });

  final List<StateGovernanceRisk> risks;
  final int total;
  final ValueChanged<StateGovernanceRisk> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Governance exceptions',
        trailing: TgcgStatusPill(
          label: '$total OPEN',
          color: total == 0 ? TgcgColors.success : TgcgColors.warning,
          compact: true,
        ),
        child: risks.isEmpty
            ? const TgcgStatusPill(
                label: 'NO CURRENT GOVERNANCE EXCEPTION',
                color: TgcgColors.success,
                icon: Icons.check_circle_outline_rounded,
              )
            : Column(
                children: [
                  for (final risk in risks)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onOpen(risk),
                        borderRadius: BorderRadius.circular(TgcgRadius.sm),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _riskColor(risk.severity)
                                .withValues(alpha: .04),
                            borderRadius:
                                BorderRadius.circular(TgcgRadius.sm),
                            border: Border.all(
                              color: _riskColor(risk.severity)
                                  .withValues(alpha: .16),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _riskIcon(risk.kind),
                                color: _riskColor(risk.severity),
                                size: 19,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      risk.title,
                                      style: const TextStyle(
                                        color: TgcgColors.ink,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      risk.detail,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: TgcgColors.muted,
                                        fontSize: 9.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TgcgStatusPill(
                                label: _severityLabel(risk.severity),
                                color: _riskColor(risk.severity),
                                compact: true,
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: TgcgColors.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      );
}

class _LeadershipGovernancePanel extends StatelessWidget {
  const _LeadershipGovernancePanel({
    required this.snapshot,
    required this.onOpenRoles,
    required this.onOpenCoverage,
  });

  final StateGovernanceSnapshot snapshot;
  final VoidCallback onOpenRoles;
  final VoidCallback onOpenCoverage;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Leadership authority coverage',
        trailing: Wrap(
          spacing: 4,
          children: [
            TextButton(
              onPressed: onOpenCoverage,
              child: const Text('Coverage'),
            ),
            TextButton(
              onPressed: onOpenRoles,
              child: const Text('Manage roles'),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              (
                'Senatorial',
                snapshot.leadership.senatorialFilled,
                snapshot.leadership.senatorialExpected,
              ),
              (
                'LGA',
                snapshot.leadership.lgaFilled,
                snapshot.leadership.lgaExpected,
              ),
              (
                'Loaded wards',
                snapshot.leadership.loadedWardFilled,
                snapshot.leadership.loadedWardExpected,
              ),
              (
                'Loaded PUs',
                snapshot.leadership.loadedPollingUnitFilled,
                snapshot.leadership.loadedPollingUnitExpected,
              ),
            ];
            final width = constraints.maxWidth >= 800
                ? (constraints.maxWidth - 30) / 4
                : constraints.maxWidth >= 420
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: width,
                    child: _LeadershipCard(
                      label: card.$1,
                      filled: card.$2,
                      expected: card.$3,
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

class _LeadershipCard extends StatelessWidget {
  const _LeadershipCard({
    required this.label,
    required this.filled,
    required this.expected,
  });

  final String label;
  final int filled;
  final int expected;

  @override
  Widget build(BuildContext context) {
    final complete = expected > 0 && filled == expected;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: complete
            ? TgcgColors.success.withValues(alpha: .05)
            : TgcgColors.warning.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(TgcgRadius.sm),
        border: Border.all(
          color: complete
              ? TgcgColors.success.withValues(alpha: .18)
              : TgcgColors.warning.withValues(alpha: .18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$filled/$expected',
            style: TextStyle(
              color: complete ? TgcgColors.success : TgcgColors.warning,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            expected == 0
                ? 'Catalogue pending'
                : complete
                    ? 'Coverage complete'
                    : '${expected - filled} vacant',
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleDistributionPanel extends StatelessWidget {
  const _RoleDistributionPanel({required this.summaries});

  final List<RoleAuthoritySummary> summaries;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Role authority distribution',
        child: summaries.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.manage_accounts_outlined,
                title: 'No active role grants',
                message: 'Active role grants will appear here.',
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in summaries)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: TgcgColors.surfaceRaised,
                        borderRadius:
                            BorderRadius.circular(TgcgRadius.sm),
                        border: Border.all(color: TgcgColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _roleLabel(item.role),
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 10.5,
                            ),
                          ),
                          Text(
                            '${item.activeAssignments} grants • ${item.distinctHolders} holders',
                            style: const TextStyle(
                              color: TgcgColors.muted,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      );
}

class _TemporaryAuthorityPanel extends StatelessWidget {
  const _TemporaryAuthorityPanel({
    required this.assignments,
    required this.membership,
    required this.onOpenAssignments,
  });

  final List<MemberAssignment> assignments;
  final MembershipOperationsController membership;
  final VoidCallback onOpenAssignments;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Temporary assignment authority',
        trailing: TextButton.icon(
          onPressed: onOpenAssignments,
          icon: const Icon(Icons.assignment_ind_outlined),
          label: const Text('Assignment Control'),
        ),
        child: assignments.isEmpty
            ? const TgcgStatusPill(
                label: 'NO ACTIVE TEMPORARY ACCESS GRANTS',
                color: TgcgColors.success,
                icon: Icons.check_circle_outline_rounded,
              )
            : Column(
                children: [
                  for (final assignment in assignments.take(12))
                    Container(
                      margin: const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: TgcgColors.surfaceRaised,
                        borderRadius:
                            BorderRadius.circular(TgcgRadius.sm),
                        border: Border.all(color: TgcgColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.key_outlined,
                            color: TgcgColors.ai,
                            size: 19,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  membership
                                          .memberById(assignment.memberId)
                                          ?.fullName ??
                                      assignment.memberId,
                                  style: const TextStyle(
                                    color: TgcgColors.ink,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 10.5,
                                  ),
                                ),
                                Text(
                                  '${assignment.title} • ${assignment.targetScope.label}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: TgcgColors.muted,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TgcgStatusPill(
                            label:
                                '${assignment.grantedCapabilities.length} CAPABILITIES',
                            color: TgcgColors.ai,
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      );
}

class _ProtectedControlPanel extends StatelessWidget {
  const _ProtectedControlPanel({required this.snapshot});

  final StateGovernanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Protected control state',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                const TgcgStatusPill(
                  label: 'AUDIT TRAIL • PROTECTED',
                  color: TgcgColors.muted,
                  icon: Icons.lock_outline_rounded,
                  compact: true,
                ),
                const TgcgStatusPill(
                  label: 'SYSTEM SETTINGS • ADMIN ONLY',
                  color: TgcgColors.muted,
                  icon: Icons.admin_panel_settings_outlined,
                  compact: true,
                ),
                TgcgStatusPill(
                  label:
                      'SYNC ${snapshot.syncQueued} QUEUED • ${snapshot.syncing} ACTIVE',
                  color: snapshot.syncFailed + snapshot.syncConflicts > 0
                      ? TgcgColors.warning
                      : TgcgColors.success,
                  icon: Icons.sync_rounded,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final setting in snapshot.settings)
              Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: setting.value
                      ? TgcgColors.success.withValues(alpha: .04)
                      : TgcgColors.danger.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(TgcgRadius.sm),
                  border: Border.all(
                    color: setting.value
                        ? TgcgColors.success.withValues(alpha: .14)
                        : TgcgColors.danger.withValues(alpha: .18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      setting.value
                          ? Icons.verified_user_outlined
                          : Icons.gpp_maybe_outlined,
                      color: setting.value
                          ? TgcgColors.success
                          : TgcgColors.danger,
                      size: 19,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        setting.label,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TgcgStatusPill(
                      label: setting.value ? 'ENABLED' : 'DISABLED',
                      color: setting.value
                          ? TgcgColors.success
                          : TgcgColors.danger,
                      compact: true,
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _RoleAuthorityRegister extends StatelessWidget {
  const _RoleAuthorityRegister({
    required this.records,
    required this.roles,
    required this.search,
    required this.filter,
    required this.onSearch,
    required this.onRole,
    required this.onClear,
    required this.onManage,
  });

  final List<RoleAssignmentRecord> records;
  final List<TgcgRole> roles;
  final TextEditingController search;
  final TgcgRole? filter;
  final ValueChanged<String> onSearch;
  final ValueChanged<TgcgRole?> onRole;
  final VoidCallback onClear;
  final ValueChanged<String> onManage;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Active role authority register',
        trailing: TgcgStatusPill(
          label: '${records.length} SHOWN',
          color: TgcgColors.info,
          compact: true,
        ),
        child: Column(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: search,
                    onChanged: onSearch,
                    decoration: const InputDecoration(
                      labelText: 'Search authority',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<TgcgRole?>(
                    initialValue: filter,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All roles'),
                      ),
                      for (final role in roles)
                        DropdownMenuItem(
                          value: role,
                          child: Text(_roleLabel(role)),
                        ),
                    ],
                    onChanged: onRole,
                  ),
                ),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (records.isEmpty)
              const TgcgEmptyState(
                icon: Icons.manage_accounts_outlined,
                title: 'No matching authority records',
                message: 'Change the current filters.',
              )
            else
              for (final record in records)
                Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: TgcgColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(TgcgRadius.sm),
                    border: Border.all(color: TgcgColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        color: TgcgColors.primary,
                        size: 19,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.subjectName,
                              style: const TextStyle(
                                color: TgcgColors.ink,
                                fontWeight: FontWeight.w900,
                                fontSize: 10.5,
                              ),
                            ),
                            Text(
                              '${_roleLabel(record.role)} • ${record.scope.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: TgcgColors.muted,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'by ${record.assignedBy}',
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(width: 7),
                      TextButton(
                        onPressed: () => onManage(record.subjectId),
                        child: const Text('Manage'),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      );
}

int _severityOrder(StateGovernanceRiskSeverity severity) => switch (severity) {
      StateGovernanceRiskSeverity.critical => 0,
      StateGovernanceRiskSeverity.warning => 1,
      StateGovernanceRiskSeverity.info => 2,
    };

String _severityLabel(StateGovernanceRiskSeverity severity) =>
    switch (severity) {
      StateGovernanceRiskSeverity.critical => 'CRITICAL',
      StateGovernanceRiskSeverity.warning => 'WARNING',
      StateGovernanceRiskSeverity.info => 'INFO',
    };

Color _riskColor(StateGovernanceRiskSeverity severity) => switch (severity) {
      StateGovernanceRiskSeverity.critical => TgcgColors.danger,
      StateGovernanceRiskSeverity.warning => TgcgColors.warning,
      StateGovernanceRiskSeverity.info => TgcgColors.info,
    };

IconData _riskIcon(StateGovernanceRiskKind kind) => switch (kind) {
      StateGovernanceRiskKind.vacantLeadership =>
        Icons.person_off_outlined,
      StateGovernanceRiskKind.duplicateLeadershipHolder =>
        Icons.people_alt_outlined,
      StateGovernanceRiskKind.coordinatorScopeMismatch =>
        Icons.wrong_location_outlined,
      StateGovernanceRiskKind.blockedAuthority => Icons.block_outlined,
      StateGovernanceRiskKind.pendingActivationAuthority =>
        Icons.schedule_outlined,
      StateGovernanceRiskKind.identityReviewAuthority =>
        Icons.manage_search_outlined,
      StateGovernanceRiskKind.multipleCoordinatorPosts =>
        Icons.account_tree_outlined,
      StateGovernanceRiskKind.orphanRoleRecord =>
        Icons.link_off_outlined,
      StateGovernanceRiskKind.syncFailure =>
        Icons.cloud_off_outlined,
      StateGovernanceRiskKind.syncConflict =>
        Icons.merge_type_rounded,
      StateGovernanceRiskKind.disabledSafeguard =>
        Icons.gpp_maybe_outlined,
    };

bool _isCoordinatorRole(TgcgRole role) => switch (role) {
      TgcgRole.stateCoordinator ||
      TgcgRole.senatorialCoordinator ||
      TgcgRole.lgaCoordinator ||
      TgcgRole.wardCoordinator ||
      TgcgRole.pollingUnitCoordinator => true,
      _ => false,
    };

GeographyLevel? _expectedScopeLevel(TgcgRole role) => switch (role) {
      TgcgRole.stateCoordinator => GeographyLevel.state,
      TgcgRole.senatorialCoordinator => GeographyLevel.senatorialDistrict,
      TgcgRole.lgaCoordinator => GeographyLevel.lga,
      TgcgRole.wardCoordinator => GeographyLevel.ward,
      TgcgRole.pollingUnitCoordinator => GeographyLevel.pollingUnit,
      _ => null,
    };

String _scopeKey(GeographicScope scope) =>
    '${scope.level.name}:${scope.country}:${scope.zoneId ?? ''}:'
    '${scope.stateId ?? ''}:${scope.senatorialDistrictId ?? ''}:'
    '${scope.lgaId ?? ''}:${scope.wardId ?? ''}:'
    '${scope.pollingUnitId ?? ''}';

String _roleLabel(TgcgRole role) {
  final value = role.name.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return value.isEmpty
      ? value
      : '${value[0].toUpperCase()}${value.substring(1)}';
}
