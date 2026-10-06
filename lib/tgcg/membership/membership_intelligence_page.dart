import 'package:flutter/material.dart';

import '../assignments/assignment_control_actions.dart';
import '../assignments/assignment_store.dart';
import '../devices/managed_device_store.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../geography/kaduna_geography.dart';
import '../governance/governance_store.dart';
import '../meeting/operational_call_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'membership_store.dart';

enum MemberReadinessState {
  deployed,
  available,
  attention,
  identityReview,
  pendingActivation,
  blocked,
}

enum MemberAttentionKind {
  noRole,
  noDeviceWhileDeployed,
  gpsInactiveWhileDeployed,
  noContact,
  noHomePollingUnit,
  identityReview,
  pendingActivation,
  blocked,
  multipleCoordinatorPosts,
}

class MemberIntelligenceSnapshot {
  const MemberIntelligenceSnapshot({
    required this.member,
    required this.registrationScope,
    required this.homePollingUnit,
    required this.roles,
    required this.activeAssignments,
    required this.device,
    required this.gps,
    required this.resultSubmissions,
    required this.assignmentEvidence,
    required this.identityReady,
    required this.readinessScore,
    required this.readinessState,
    required this.attentionKinds,
  });

  final TgcgMember member;
  final GeographicScope? registrationScope;
  final MemberPollingUnitLink? homePollingUnit;
  final List<RoleAssignmentRecord> roles;
  final List<MemberAssignment> activeAssignments;
  final ManagedDevice? device;
  final OperationalCallGpsSnapshot? gps;
  final int resultSubmissions;
  final int assignmentEvidence;
  final bool identityReady;
  final int readinessScore;
  final MemberReadinessState readinessState;
  final Set<MemberAttentionKind> attentionKinds;

  bool get hasRole => roles.isNotEmpty;
  bool get isDeployed => activeAssignments.isNotEmpty;
  bool get hasContact =>
      member.phoneNumber.trim().isNotEmpty ||
      (member.email ?? '').trim().isNotEmpty;

  int get coordinatorRoleCount => roles
      .where((item) => _isCoordinatorRole(item.role))
      .length;
}

class LeadershipCoverageSummary {
  const LeadershipCoverageSummary({
    required this.senatorialExpected,
    required this.senatorialFilled,
    required this.lgaExpected,
    required this.lgaFilled,
    required this.loadedWardExpected,
    required this.loadedWardFilled,
    required this.loadedPollingUnitExpected,
    required this.loadedPollingUnitFilled,
  });

  final int senatorialExpected;
  final int senatorialFilled;
  final int lgaExpected;
  final int lgaFilled;
  final int loadedWardExpected;
  final int loadedWardFilled;
  final int loadedPollingUnitExpected;
  final int loadedPollingUnitFilled;
}

bool memberIdentityReady(TgcgMember member) =>
    member.identityReview == MemberIdentityReview.verified ||
    (member.origin == RecordOrigin.systemDerived &&
        member.status == RecordStatus.verified &&
        member.identityReview == MemberIdentityReview.pending);

MemberIntelligenceSnapshot buildMemberIntelligenceSnapshot({
  required TgcgMember member,
  required MembershipOperationsController membership,
  required AssignmentController assignments,
  required ManagedDeviceController devices,
  required GovernanceOperationsController governance,
  required ResultOperationsController results,
  required OperationalCallController calls,
}) {
  final roles = governance.activeRolesForMember(member.id);
  final activeAssignments = assignments.activeAssignmentsForMember(member.id);
  final device = devices.deviceForMember(member.id);
  final gps = calls.gpsSnapshotForMember(member.id);
  final registrationScope = membership.registrationScopeForMember(member.id);
  final homePollingUnit = membership.homePollingUnitForMember(member.id);
  final resultSubmissions =
      results.submissions.where((item) => item.submittedBy == member.id).length;
  final assignmentEvidence = assignments.assignments
      .where((item) => item.memberId == member.id)
      .fold<int>(0, (sum, item) => sum + item.evidence.length);
  final identityReady = memberIdentityReady(member);
  final hasContact = member.phoneNumber.trim().isNotEmpty ||
      (member.email ?? '').trim().isNotEmpty;

  final attention = <MemberAttentionKind>{};
  if (member.isBlocked) {
    attention.add(MemberAttentionKind.blocked);
  }
  if (member.isPendingActivation) {
    attention.add(MemberAttentionKind.pendingActivation);
  }
  if (!identityReady && !member.isBlocked) {
    attention.add(MemberAttentionKind.identityReview);
  }
  if (roles.isEmpty) {
    attention.add(MemberAttentionKind.noRole);
  }
  if (activeAssignments.isNotEmpty && device == null) {
    attention.add(MemberAttentionKind.noDeviceWhileDeployed);
  }
  if (activeAssignments.isNotEmpty && gps == null) {
    attention.add(MemberAttentionKind.gpsInactiveWhileDeployed);
  }
  if (!hasContact) {
    attention.add(MemberAttentionKind.noContact);
  }
  if (homePollingUnit == null) {
    attention.add(MemberAttentionKind.noHomePollingUnit);
  }
  final coordinatorPosts = roles
      .where((item) => _isCoordinatorRole(item.role))
      .length;
  if (coordinatorPosts > 1) {
    attention.add(MemberAttentionKind.multipleCoordinatorPosts);
  }

  var score = 0;
  if (member.accountStatus == MemberAccountStatus.active) {
    score += 20;
  } else if (member.accountStatus == MemberAccountStatus.pendingActivation) {
    score += 5;
  }
  if (identityReady) score += 20;
  if (hasContact) score += 10;
  if (roles.isNotEmpty) score += 15;
  if (device != null) score += 10;
  if (homePollingUnit != null) score += 10;
  if (activeAssignments.isEmpty || gps != null) score += 15;
  score = score.clamp(0, 100).toInt();

  final operationalAttention = attention.any(
    (item) =>
        item == MemberAttentionKind.noRole ||
        item == MemberAttentionKind.noDeviceWhileDeployed ||
        item == MemberAttentionKind.gpsInactiveWhileDeployed ||
        item == MemberAttentionKind.noContact ||
        item == MemberAttentionKind.multipleCoordinatorPosts,
  );

  final state = member.isBlocked
      ? MemberReadinessState.blocked
      : member.isPendingActivation
          ? MemberReadinessState.pendingActivation
          : !identityReady
              ? MemberReadinessState.identityReview
              : operationalAttention
                  ? MemberReadinessState.attention
                  : activeAssignments.isNotEmpty
                      ? MemberReadinessState.deployed
                      : MemberReadinessState.available;

  return MemberIntelligenceSnapshot(
    member: member,
    registrationScope: registrationScope,
    homePollingUnit: homePollingUnit,
    roles: List.unmodifiable(roles),
    activeAssignments: List.unmodifiable(activeAssignments),
    device: device,
    gps: gps,
    resultSubmissions: resultSubmissions,
    assignmentEvidence: assignmentEvidence,
    identityReady: identityReady,
    readinessScore: score,
    readinessState: state,
    attentionKinds: Set.unmodifiable(attention),
  );
}

LeadershipCoverageSummary buildLeadershipCoverage({
  required MembershipOperationsController membership,
  required GovernanceOperationsController governance,
}) {
  final geography = membership.geography;

  int exactRoleFilled(
    Iterable<GeographicScope> scopes,
    TgcgRole role,
  ) =>
      scopes.where((scope) {
        return governance.roleAssignments.any(
          (record) =>
              record.active &&
              record.role == role &&
              _sameScope(record.scope, scope),
        );
      }).length;

  final districtScopes =
      geography.districts.map((item) => item.scope).toList(growable: false);
  final lgaScopes =
      geography.lgas.map((item) => item.scope).toList(growable: false);

  final wardScopes = <String, GeographicScope>{};
  final puScopes = <String, GeographicScope>{};
  for (final unit in geography.pollingUnits) {
    final wardId = unit.scope.wardId;
    if (wardId != null) {
      wardScopes[wardId] = GeographicScope(
        level: GeographyLevel.ward,
        country: unit.scope.country,
        zoneId: unit.scope.zoneId,
        zoneName: unit.scope.zoneName,
        stateId: unit.scope.stateId,
        stateName: unit.scope.stateName,
        senatorialDistrictId: unit.scope.senatorialDistrictId,
        senatorialDistrictName: unit.scope.senatorialDistrictName,
        lgaId: unit.scope.lgaId,
        lgaName: unit.scope.lgaName,
        wardId: unit.scope.wardId,
        wardName: unit.scope.wardName,
      );
    }
    final puId = unit.scope.pollingUnitId;
    if (puId != null) puScopes[puId] = unit.scope;
  }

  return LeadershipCoverageSummary(
    senatorialExpected: districtScopes.length,
    senatorialFilled:
        exactRoleFilled(districtScopes, TgcgRole.senatorialCoordinator),
    lgaExpected: lgaScopes.length,
    lgaFilled: exactRoleFilled(lgaScopes, TgcgRole.lgaCoordinator),
    loadedWardExpected: wardScopes.length,
    loadedWardFilled:
        exactRoleFilled(wardScopes.values, TgcgRole.wardCoordinator),
    loadedPollingUnitExpected: puScopes.length,
    loadedPollingUnitFilled: exactRoleFilled(
      puScopes.values,
      TgcgRole.pollingUnitCoordinator,
    ),
  );
}

class MembershipIntelligencePage extends StatefulWidget {
  const MembershipIntelligencePage({
    super.key,
    required this.onOpenModule,
    required this.onAssignRole,
  });

  final ValueChanged<TgcgModule> onOpenModule;
  final ValueChanged<String> onAssignRole;

  @override
  State<MembershipIntelligencePage> createState() =>
      _MembershipIntelligencePageState();
}

class _MembershipIntelligencePageState
    extends State<MembershipIntelligencePage> {
  final _search = TextEditingController();
  MemberReadinessState? _state;
  MemberAttentionKind? _attention;
  String? _selectedMemberId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (session.role != TgcgRole.stateCoordinator) {
      return const Center(
        child: TgcgEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Membership Intelligence unavailable',
          message: 'State Coordinator authority is required.',
        ),
      );
    }

    final membership = MembershipOperations.of(context);
    final assignments = Assignments.of(context);
    final devices = ManagedDevices.of(context);
    final governance = GovernanceOperations.of(context);
    final results = ResultOperations.of(context);
    final calls = OperationalCalls.of(context);

    final snapshots = membership.members
        .map(
          (member) => buildMemberIntelligenceSnapshot(
            member: member,
            membership: membership,
            assignments: assignments,
            devices: devices,
            governance: governance,
            results: results,
            calls: calls,
          ),
        )
        .toList(growable: false)
      ..sort(_snapshotSort);

    final leadership = buildLeadershipCoverage(
      membership: membership,
      governance: governance,
    );
    final query = _search.text.trim().toLowerCase();
    final visible = snapshots.where((snapshot) {
      if (_state != null && snapshot.readinessState != _state) return false;
      if (_attention != null &&
          !snapshot.attentionKinds.contains(_attention)) {
        return false;
      }
      if (query.isEmpty) return true;
      final roleText =
          snapshot.roles.map((item) => _roleLabel(item.role)).join(' ');
      final assignmentText =
          snapshot.activeAssignments.map((item) => item.title).join(' ');
      final home = snapshot.homePollingUnit == null
          ? ''
          : membership
                  .geography
                  .pollingUnit(snapshot.homePollingUnit!.pollingUnitId)
                  ?.scope
                  .label ??
              snapshot.homePollingUnit!.pollingUnitId;
      return [
        snapshot.member.fullName,
        snapshot.member.phoneNumber,
        snapshot.member.email,
        snapshot.member.membershipNumber,
        snapshot.member.id,
        snapshot.registrationScope?.label,
        home,
        roleText,
        assignmentText,
      ].whereType<String>().join(' ').toLowerCase().contains(query);
    }).toList(growable: false);

    if (_selectedMemberId == null ||
        !visible.any((item) => item.member.id == _selectedMemberId)) {
      _selectedMemberId =
          visible.isEmpty ? null : visible.first.member.id;
    }
    final selected = _selectedMemberId == null
        ? null
        : snapshots
            .where((item) => item.member.id == _selectedMemberId)
            .firstOrNull;

    final activeCount = snapshots
        .where((item) => item.member.accountStatus == MemberAccountStatus.active)
        .length;
    final pendingActivation = snapshots
        .where((item) => item.member.isPendingActivation)
        .length;
    final blocked = snapshots.where((item) => item.member.isBlocked).length;
    final noRole = snapshots.where((item) => item.roles.isEmpty).length;
    final deployed =
        snapshots.where((item) => item.activeAssignments.isNotEmpty).length;
    final gpsActive = snapshots
        .where(
          (item) => item.activeAssignments.isNotEmpty && item.gps != null,
        )
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'STATE PEOPLE COMMAND',
          title: 'Membership Intelligence',
          subtitle: GeographicScope.kaduna.label,
          trailing: const TgcgStatusPill(
            label: 'STATE COORDINATOR',
            color: TgcgColors.primary,
            icon: Icons.manage_accounts_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _MembershipMetrics(
          total: snapshots.length,
          active: activeCount,
          pendingActivation: pendingActivation,
          blocked: blocked,
          noRole: noRole,
          deployed: deployed,
          gpsActive: gpsActive,
        ),
        const SizedBox(height: 16),
        _LeadershipCoveragePanel(
          coverage: leadership,
          onOpenRoles: () => widget.onOpenModule(TgcgModule.roleAssignment),
        ),
        const SizedBox(height: 16),
        _AttentionPanel(
          snapshots: snapshots,
          onSelect: (memberId) {
            setState(() {
              _selectedMemberId = memberId;
              _state = null;
              _attention = null;
              _search.clear();
            });
          },
        ),
        const SizedBox(height: 16),
        _MemberFilters(
          search: _search,
          state: _state,
          attention: _attention,
          onSearch: (_) => setState(() {}),
          onState: (value) => setState(() => _state = value),
          onAttention: (value) => setState(() => _attention = value),
          onClear: () {
            _search.clear();
            setState(() {
              _state = null;
              _attention = null;
            });
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final directory = _IntelligenceDirectory(
              snapshots: visible,
              selectedMemberId: _selectedMemberId,
              onSelect: (id) => setState(() => _selectedMemberId = id),
            );
            final inspector = _MemberCommandInspector(
              snapshot: selected,
              membership: membership,
              calls: calls,
              session: session,
              onAssignRole: selected == null
                  ? null
                  : () => widget.onAssignRole(selected.member.id),
              onAssignJob: selected == null
                  ? null
                  : () =>
                      widget.onOpenModule(TgcgModule.assignmentControl),
              onOpenCoverage: () =>
                  widget.onOpenModule(TgcgModule.geography),
              onOpenResults: selected == null ||
                      selected.resultSubmissions == 0
                  ? null
                  : () => widget.onOpenModule(TgcgModule.resultCapture),
            );

            if (constraints.maxWidth < 1080) {
              return Column(
                children: [
                  directory,
                  const SizedBox(height: 14),
                  inspector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: directory),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: inspector),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MembershipMetrics extends StatelessWidget {
  const _MembershipMetrics({
    required this.total,
    required this.active,
    required this.pendingActivation,
    required this.blocked,
    required this.noRole,
    required this.deployed,
    required this.gpsActive,
  });

  final int total;
  final int active;
  final int pendingActivation;
  final int blocked;
  final int noRole;
  final int deployed;
  final int gpsActive;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1180
              ? 7
              : constraints.maxWidth >= 760
                  ? 4
                  : constraints.maxWidth >= 500
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
                value: '$total',
                detail: 'State registry',
                icon: Icons.groups_2_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Active',
                value: '$active',
                detail: 'Account active',
                icon: Icons.verified_user_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Pending activation',
                value: '$pendingActivation',
                detail: 'First password pending',
                icon: Icons.schedule_rounded,
                tone: pendingActivation == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Blocked',
                value: '$blocked',
                detail: 'Access restricted',
                icon: Icons.block_outlined,
                tone: blocked == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Without role',
                value: '$noRole',
                detail: 'No active role',
                icon: Icons.badge_outlined,
                tone: noRole == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Deployed',
                value: '$deployed',
                detail: 'Active assignment',
                icon: Icons.assignment_ind_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'GPS active',
                value: '$gpsActive/$deployed',
                detail: 'Deployed & reachable',
                icon: Icons.gps_fixed_rounded,
                tone: deployed > 0 && gpsActive == deployed
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
            ],
          );
        },
      );
}

class _LeadershipCoveragePanel extends StatelessWidget {
  const _LeadershipCoveragePanel({
    required this.coverage,
    required this.onOpenRoles,
  });

  final LeadershipCoverageSummary coverage;
  final VoidCallback onOpenRoles;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Leadership coverage',
        trailing: TextButton.icon(
          onPressed: onOpenRoles,
          icon: const Icon(Icons.manage_accounts_outlined),
          label: const Text('Roles & Authorization'),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              _LeadershipStat(
                label: 'Senatorial',
                filled: coverage.senatorialFilled,
                expected: coverage.senatorialExpected,
              ),
              _LeadershipStat(
                label: 'LGA',
                filled: coverage.lgaFilled,
                expected: coverage.lgaExpected,
              ),
              _LeadershipStat(
                label: 'Loaded wards',
                filled: coverage.loadedWardFilled,
                expected: coverage.loadedWardExpected,
              ),
              _LeadershipStat(
                label: 'Loaded PUs',
                filled: coverage.loadedPollingUnitFilled,
                expected: coverage.loadedPollingUnitExpected,
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
                for (final item in cards)
                  SizedBox(width: width, child: item),
              ],
            );
          },
        ),
      );
}

class _LeadershipStat extends StatelessWidget {
  const _LeadershipStat({
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

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({
    required this.snapshots,
    required this.onSelect,
  });

  final List<MemberIntelligenceSnapshot> snapshots;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final attention = snapshots
        .where((item) => _attentionSeverity(item) > 0)
        .toList(growable: false)
      ..sort((a, b) {
        final severity =
            _attentionSeverity(b).compareTo(_attentionSeverity(a));
        if (severity != 0) return severity;
        return a.member.fullName.compareTo(b.member.fullName);
      });

    return TgcgSectionCard(
      title: 'People needing attention',
      trailing: TgcgStatusPill(
        label: '${attention.length} OPEN',
        color:
            attention.isEmpty ? TgcgColors.success : TgcgColors.warning,
        icon: Icons.warning_amber_rounded,
        compact: true,
      ),
      child: attention.isEmpty
          ? const TgcgStatusPill(
              label: 'NO CURRENT MEMBER EXCEPTION',
              color: TgcgColors.success,
              icon: Icons.check_circle_outline_rounded,
            )
          : Column(
              children: [
                for (final item in attention.take(12))
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onSelect(item.member.id),
                      borderRadius: BorderRadius.circular(TgcgRadius.sm),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _readinessColor(item.readinessState)
                              .withValues(alpha: .04),
                          borderRadius:
                              BorderRadius.circular(TgcgRadius.sm),
                          border: Border.all(
                            color: _readinessColor(item.readinessState)
                                .withValues(alpha: .16),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _readinessIcon(item.readinessState),
                              color:
                                  _readinessColor(item.readinessState),
                              size: 19,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.member.fullName,
                                    style: const TextStyle(
                                      color: TgcgColors.ink,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    item.attentionKinds
                                        .map(_attentionLabel)
                                        .take(3)
                                        .join(' • '),
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
                              label: '${item.readinessScore}',
                              color:
                                  _readinessColor(item.readinessState),
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
}

class _MemberFilters extends StatelessWidget {
  const _MemberFilters({
    required this.search,
    required this.state,
    required this.attention,
    required this.onSearch,
    required this.onState,
    required this.onAttention,
    required this.onClear,
  });

  final TextEditingController search;
  final MemberReadinessState? state;
  final MemberAttentionKind? attention;
  final ValueChanged<String> onSearch;
  final ValueChanged<MemberReadinessState?> onState;
  final ValueChanged<MemberAttentionKind?> onAttention;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Member filters',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 330,
              child: TextField(
                controller: search,
                onChanged: onSearch,
                decoration: const InputDecoration(
                  labelText: 'Search members',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<MemberReadinessState?>(
                initialValue: state,
                decoration:
                    const InputDecoration(labelText: 'Readiness state'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All states'),
                  ),
                  for (final value in MemberReadinessState.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_readinessLabel(value)),
                    ),
                ],
                onChanged: onState,
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<MemberAttentionKind?>(
                initialValue: attention,
                decoration:
                    const InputDecoration(labelText: 'Attention type'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All attention types'),
                  ),
                  for (final value in MemberAttentionKind.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_attentionLabel(value)),
                    ),
                ],
                onChanged: onAttention,
              ),
            ),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear'),
            ),
          ],
        ),
      );
}

class _IntelligenceDirectory extends StatelessWidget {
  const _IntelligenceDirectory({
    required this.snapshots,
    required this.selectedMemberId,
    required this.onSelect,
  });

  final List<MemberIntelligenceSnapshot> snapshots;
  final String? selectedMemberId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Member intelligence register',
        trailing: TgcgStatusPill(
          label: '${snapshots.length} SHOWN',
          color: TgcgColors.info,
          compact: true,
        ),
        child: snapshots.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.person_search_outlined,
                title: 'No matching members',
                message: 'Change the current filters.',
              )
            : Column(
                children: [
                  for (final item in snapshots)
                    _MemberIntelligenceRow(
                      snapshot: item,
                      selected: item.member.id == selectedMemberId,
                      onTap: () => onSelect(item.member.id),
                    ),
                ],
              ),
      );
}

class _MemberIntelligenceRow extends StatelessWidget {
  const _MemberIntelligenceRow({
    required this.snapshot,
    required this.selected,
    required this.onTap,
  });

  final MemberIntelligenceSnapshot snapshot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _readinessColor(snapshot.readinessState);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: selected
                  ? TgcgColors.primarySoft
                  : TgcgColors.surfaceRaised,
              borderRadius: BorderRadius.circular(TgcgRadius.sm),
              border: Border.all(
                color: selected
                    ? TgcgColors.primary.withValues(alpha: .28)
                    : TgcgColors.border,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .10),
                  child: Text(
                    snapshot.member.fullName.isEmpty
                        ? '?'
                        : snapshot.member.fullName[0].toUpperCase(),
                    style: TextStyle(
                      color: color,
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
                        snapshot.member.fullName,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${snapshot.member.membershipNumber ?? snapshot.member.id} • '
                        '${snapshot.registrationScope?.label ?? 'STATE / UNSCOPED'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          TgcgStatusPill(
                            label: _readinessLabel(
                              snapshot.readinessState,
                            ).toUpperCase(),
                            color: color,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label:
                                '${snapshot.roles.length} ROLE${snapshot.roles.length == 1 ? '' : 'S'}',
                            color: snapshot.roles.isEmpty
                                ? TgcgColors.warning
                                : TgcgColors.info,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label:
                                '${snapshot.activeAssignments.length} JOB${snapshot.activeAssignments.length == 1 ? '' : 'S'}',
                            color: snapshot.activeAssignments.isEmpty
                                ? TgcgColors.muted
                                : TgcgColors.ai,
                            compact: true,
                          ),
                          if (snapshot.isDeployed)
                            TgcgStatusPill(
                              label: snapshot.gps == null
                                  ? 'GPS INACTIVE'
                                  : 'GPS ACTIVE',
                              color: snapshot.gps == null
                                  ? TgcgColors.warning
                                  : TgcgColors.success,
                              compact: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(TgcgRadius.sm),
                  ),
                  child: Text(
                    '${snapshot.readinessScore}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: TgcgColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberCommandInspector extends StatelessWidget {
  const _MemberCommandInspector({
    required this.snapshot,
    required this.membership,
    required this.calls,
    required this.session,
    required this.onAssignRole,
    required this.onAssignJob,
    required this.onOpenCoverage,
    required this.onOpenResults,
  });

  final MemberIntelligenceSnapshot? snapshot;
  final MembershipOperationsController membership;
  final OperationalCallController calls;
  final TgcgSessionController session;
  final VoidCallback? onAssignRole;
  final VoidCallback? onAssignJob;
  final VoidCallback onOpenCoverage;
  final VoidCallback? onOpenResults;

  @override
  Widget build(BuildContext context) {
    final item = snapshot;
    if (item == null) {
      return const TgcgSectionCard(
        title: 'Member command',
        child: TgcgEmptyState(
          icon: Icons.manage_accounts_outlined,
          title: 'Select a member',
          message: 'Choose a member from the intelligence register.',
        ),
      );
    }

    final homeUnit = item.homePollingUnit == null
        ? null
        : membership.geography
            .pollingUnit(item.homePollingUnit!.pollingUnitId);
    final gps = item.gps;
    final device = item.device;
    final color = _readinessColor(item.readinessState);

    return TgcgSectionCard(
      title: 'Member command',
      trailing: TgcgStatusPill(
        label: 'READINESS ${item.readinessScore}',
        color: color,
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: color.withValues(alpha: .10),
                child: Text(
                  item.member.fullName.isEmpty
                      ? '?'
                      : item.member.fullName[0].toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.member.fullName,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      item.member.membershipNumber ?? item.member.id,
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              TgcgStatusPill(
                label:
                    _readinessLabel(item.readinessState).toUpperCase(),
                color: color,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InspectorSection(
            title: 'Identity & contact',
            rows: [
              (
                'Account',
                item.member.accountStatus.name.toUpperCase(),
              ),
              (
                'Identity',
                item.identityReady
                    ? 'READY'
                    : item.member.identityReview.name.toUpperCase(),
              ),
              (
                'Phone',
                item.member.phoneNumber.trim().isEmpty
                    ? 'Not set'
                    : item.member.phoneNumber,
              ),
              (
                'Email',
                (item.member.email ?? '').trim().isEmpty
                    ? 'Not set'
                    : item.member.email!,
              ),
              (
                'Home PU',
                homeUnit?.scope.label ?? 'Not linked',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InspectorSection(
            title: 'Roles & deployment',
            rows: [
              (
                'Roles',
                item.roles.isEmpty
                    ? 'None'
                    : item.roles
                        .map((role) => _roleLabel(role.role))
                        .join(', '),
              ),
              (
                'Active assignments',
                '${item.activeAssignments.length}',
              ),
              (
                'Assignment evidence',
                '${item.assignmentEvidence}',
              ),
              (
                'Result submissions',
                '${item.resultSubmissions}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InspectorSection(
            title: 'Device & location',
            rows: [
              ('Managed device', device?.label ?? 'Not bound'),
              (
                'GPS',
                gps == null
                    ? 'Inactive'
                    : 'Active • ${_gpsAge(gps.capturedAt)}',
              ),
              (
                'Battery',
                device?.batteryPercent == null
                    ? 'N/A'
                    : '${device!.batteryPercent}%',
              ),
              (
                'Sync',
                device?.syncState ?? 'N/A',
              ),
            ],
          ),
          if (item.attentionKinds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final attention in item.attentionKinds)
                  TgcgStatusPill(
                    label: _attentionLabel(attention).toUpperCase(),
                    color: _attentionColor(attention),
                    compact: true,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onAssignRole,
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Assign role'),
              ),
              OutlinedButton.icon(
                onPressed: onAssignJob,
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('Assign job'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenCoverage,
                icon: const Icon(Icons.public_outlined),
                label: const Text('Coverage'),
              ),
              if (onOpenResults != null)
                OutlinedButton.icon(
                  onPressed: onOpenResults,
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Results'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: gps == null || item.member.isBlocked
                      ? null
                      : () => _call(
                            context,
                            item.member,
                            OperationalCallKind.audio,
                          ),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Audio call'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: gps == null || item.member.isBlocked
                      ? null
                      : () => _call(
                            context,
                            item.member,
                            OperationalCallKind.video,
                          ),
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Video call'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _call(
    BuildContext context,
    TgcgMember member,
    OperationalCallKind kind,
  ) async {
    try {
      await startStateCoordinatorMemberCall(
        context,
        calls: calls,
        session: session,
        stateScope: GeographicScope.kaduna,
        member: member,
        kind: kind,
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }
}

class _InspectorSection extends StatelessWidget {
  const _InspectorSection({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceRaised,
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 105,
                      child: Text(
                        row.$1,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

int _snapshotSort(
  MemberIntelligenceSnapshot a,
  MemberIntelligenceSnapshot b,
) {
  final state = _readinessOrder(a.readinessState)
      .compareTo(_readinessOrder(b.readinessState));
  if (state != 0) return state;
  return a.member.fullName.compareTo(b.member.fullName);
}

int _readinessOrder(MemberReadinessState state) => switch (state) {
      MemberReadinessState.blocked => 0,
      MemberReadinessState.pendingActivation => 1,
      MemberReadinessState.identityReview => 2,
      MemberReadinessState.attention => 3,
      MemberReadinessState.deployed => 4,
      MemberReadinessState.available => 5,
    };

int _attentionSeverity(MemberIntelligenceSnapshot snapshot) {
  if (snapshot.member.isBlocked) return 5;
  if (snapshot.member.isPendingActivation) return 4;
  if (snapshot.attentionKinds.contains(MemberAttentionKind.identityReview)) {
    return 4;
  }
  if (snapshot.attentionKinds.contains(
        MemberAttentionKind.gpsInactiveWhileDeployed,
      ) ||
      snapshot.attentionKinds.contains(
        MemberAttentionKind.noDeviceWhileDeployed,
      )) {
    return 3;
  }
  if (snapshot.attentionKinds.contains(MemberAttentionKind.noRole) ||
      snapshot.attentionKinds.contains(
        MemberAttentionKind.multipleCoordinatorPosts,
      )) {
    return 2;
  }
  if (snapshot.attentionKinds.contains(MemberAttentionKind.noContact)) {
    return 2;
  }
  if (snapshot.attentionKinds.contains(MemberAttentionKind.noHomePollingUnit)) {
    return 1;
  }
  return 0;
}

bool _isCoordinatorRole(TgcgRole role) => switch (role) {
      TgcgRole.stateCoordinator ||
      TgcgRole.senatorialCoordinator ||
      TgcgRole.lgaCoordinator ||
      TgcgRole.wardCoordinator ||
      TgcgRole.pollingUnitCoordinator => true,
      _ => false,
    };

bool _sameScope(GeographicScope a, GeographicScope b) =>
    a.level == b.level &&
    a.stateId == b.stateId &&
    a.senatorialDistrictId == b.senatorialDistrictId &&
    a.lgaId == b.lgaId &&
    a.wardId == b.wardId &&
    a.pollingUnitId == b.pollingUnitId;

String _roleLabel(TgcgRole role) => switch (role) {
      TgcgRole.stateCoordinator => 'State Coordinator',
      TgcgRole.senatorialCoordinator => 'Senatorial Coordinator',
      TgcgRole.lgaCoordinator => 'LGA Coordinator',
      TgcgRole.wardCoordinator => 'Ward Coordinator',
      TgcgRole.pollingUnitCoordinator => 'Polling Unit Coordinator',
      TgcgRole.pollingUnitAgent => 'Polling Unit Agent',
      TgcgRole.mediaOfficer => 'Media Officer',
      TgcgRole.womenMobilizationCoordinator => 'Women Mobilization',
      TgcgRole.youthMobilizationCoordinator => 'Youth Mobilization',
      TgcgRole.communicationsOfficer => 'Communications',
      TgcgRole.logisticsOfficer => 'Logistics',
      TgcgRole.monitoringEvaluationOfficer => 'M&E',
      TgcgRole.dataEvidenceOfficer => 'Data & Evidence',
      TgcgRole.transportCoordinator => 'Transport',
      TgcgRole.trainingOfficer => 'Training',
      TgcgRole.ictOfficer => 'ICT',
      _ => role.name,
    };

String _readinessLabel(MemberReadinessState state) => switch (state) {
      MemberReadinessState.deployed => 'Deployed',
      MemberReadinessState.available => 'Available',
      MemberReadinessState.attention => 'Attention',
      MemberReadinessState.identityReview => 'Identity review',
      MemberReadinessState.pendingActivation => 'Pending activation',
      MemberReadinessState.blocked => 'Blocked',
    };

Color _readinessColor(MemberReadinessState state) => switch (state) {
      MemberReadinessState.deployed => TgcgColors.success,
      MemberReadinessState.available => TgcgColors.info,
      MemberReadinessState.attention => TgcgColors.warning,
      MemberReadinessState.identityReview => TgcgColors.ai,
      MemberReadinessState.pendingActivation => TgcgColors.warning,
      MemberReadinessState.blocked => TgcgColors.danger,
    };

IconData _readinessIcon(MemberReadinessState state) => switch (state) {
      MemberReadinessState.deployed => Icons.assignment_ind_outlined,
      MemberReadinessState.available => Icons.person_search_outlined,
      MemberReadinessState.attention => Icons.warning_amber_rounded,
      MemberReadinessState.identityReview => Icons.manage_search_rounded,
      MemberReadinessState.pendingActivation => Icons.schedule_rounded,
      MemberReadinessState.blocked => Icons.block_outlined,
    };

String _attentionLabel(MemberAttentionKind kind) => switch (kind) {
      MemberAttentionKind.noRole => 'No role',
      MemberAttentionKind.noDeviceWhileDeployed => 'No device while deployed',
      MemberAttentionKind.gpsInactiveWhileDeployed => 'GPS inactive',
      MemberAttentionKind.noContact => 'No phone/email',
      MemberAttentionKind.noHomePollingUnit => 'No home PU',
      MemberAttentionKind.identityReview => 'Identity review',
      MemberAttentionKind.pendingActivation => 'Pending activation',
      MemberAttentionKind.blocked => 'Blocked',
      MemberAttentionKind.multipleCoordinatorPosts =>
        'Multiple coordinator posts',
    };

Color _attentionColor(MemberAttentionKind kind) => switch (kind) {
      MemberAttentionKind.blocked => TgcgColors.danger,
      MemberAttentionKind.identityReview => TgcgColors.ai,
      MemberAttentionKind.pendingActivation ||
      MemberAttentionKind.noDeviceWhileDeployed ||
      MemberAttentionKind.gpsInactiveWhileDeployed ||
      MemberAttentionKind.noRole ||
      MemberAttentionKind.multipleCoordinatorPosts =>
        TgcgColors.warning,
      MemberAttentionKind.noContact ||
      MemberAttentionKind.noHomePollingUnit =>
        TgcgColors.muted,
    };

String _gpsAge(DateTime capturedAt) {
  final age = DateTime.now().toUtc().difference(capturedAt.toUtc()).abs();
  if (age.inSeconds < 60) return '${age.inSeconds}s ago';
  return '${age.inMinutes}m ago';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
