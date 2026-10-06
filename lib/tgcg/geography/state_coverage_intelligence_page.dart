import 'package:flutter/material.dart';

import '../assignments/assignment_control_actions.dart';
import '../assignments/assignment_store.dart';
import '../devices/managed_device_store.dart';
import '../field/field_operations_store.dart';
import '../governance/governance_store.dart';
import '../meeting/operational_call_store.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'geography_registry.dart';
import 'kaduna_geography.dart';

enum CoverageReadinessState { ready, watch, critical, cataloguePending }

enum CoverageExceptionKind {
  missingCoordinator,
  unstaffedPollingUnit,
  gpsGap,
  coordinateMissing,
  coordinateReview,
  openIncident,
  resultConflict,
  resultMissing,
}

class CoverageAreaSnapshot {
  const CoverageAreaSnapshot({
    required this.scope,
    required this.expectedPollingUnits,
    required this.staffedPollingUnits,
    required this.activeAssignments,
    required this.deployedMembers,
    required this.gpsActiveMembers,
    required this.coordinateReady,
    required this.coordinateReview,
    required this.openIncidents,
    required this.evidenceItems,
    required this.receivedResultPollingUnits,
    required this.verifiedResultPollingUnits,
    required this.conflictingResultPollingUnits,
    required this.coordinatorFilled,
    required this.coordinatorNames,
    required this.readinessScore,
    required this.readinessState,
  });

  final GeographicScope scope;
  final int expectedPollingUnits;
  final int staffedPollingUnits;
  final int activeAssignments;
  final int deployedMembers;
  final int gpsActiveMembers;
  final int coordinateReady;
  final int coordinateReview;
  final int openIncidents;
  final int evidenceItems;
  final int receivedResultPollingUnits;
  final int verifiedResultPollingUnits;
  final int conflictingResultPollingUnits;
  final bool coordinatorFilled;
  final List<String> coordinatorNames;
  final int? readinessScore;
  final CoverageReadinessState readinessState;

  int get unstaffedPollingUnits =>
      (expectedPollingUnits - staffedPollingUnits)
          .clamp(0, expectedPollingUnits)
          .toInt();

  int get gpsInactiveMembers =>
      (deployedMembers - gpsActiveMembers).clamp(0, deployedMembers).toInt();
}

class CoverageExceptionItem {
  const CoverageExceptionItem({
    required this.kind,
    required this.scope,
    required this.title,
    required this.detail,
    required this.severity,
  });

  final CoverageExceptionKind kind;
  final GeographicScope scope;
  final String title;
  final String detail;
  final int severity;
}

CoverageAreaSnapshot buildCoverageAreaSnapshot({
  required GeographicScope scope,
  required GeographyRegistry registry,
  required AssignmentController assignments,
  required GovernanceOperationsController governance,
  required FieldOperationsController field,
  required ResultOperationsController results,
  required OperationalCallController calls,
}) {
  final units = registry.pollingUnitsWithin(scope);
  final coverage = assignments.coverageForScope(scope);
  final scopedAssignments = assignments
      .assignmentsForScope(scope)
      .where((item) => !item.isTerminal)
      .toList(growable: false);
  final deployedIds = scopedAssignments.map((item) => item.memberId).toSet();
  final gpsActive = deployedIds
      .where((id) => calls.gpsActiveForMember(id))
      .length;

  final expectedRole = _coordinatorRoleFor(scope.level);
  final roles = expectedRole == null
      ? const <RoleAssignmentRecord>[]
      : governance
          .roleAssignmentsForScope(scope)
          .where(
            (item) =>
                item.active &&
                item.role == expectedRole &&
                _sameOperationalScope(item.scope, scope),
          )
          .toList(growable: false);

  final openIncidents = field
      .incidentsForScope(scope)
      .where(
        (item) =>
            item.status != IncidentStatus.resolved &&
            item.status != IncidentStatus.closed,
      )
      .toList(growable: false);

  final assignmentEvidence = assignments
      .assignmentsForScope(scope)
      .fold<int>(0, (sum, item) => sum + item.evidence.length);
  final incidentEvidence = field
      .incidentsForScope(scope)
      .fold<int>(0, (sum, item) => sum + item.evidence.length);
  final reportEvidence = field
      .reportsForScope(scope)
      .fold<int>(0, (sum, item) => sum + item.evidence.length);

  final submissions = results.submissionsForScope(scope);
  final resultEvidence =
      submissions.where((item) => item.resultForm != null).length;
  final resultGroups = <String, List<ElectionResultSubmission>>{};
  for (final result in submissions) {
    final pollingUnitId = result.pollingUnitScope.pollingUnitId;
    if (pollingUnitId == null) continue;
    resultGroups.putIfAbsent(pollingUnitId, () => []).add(result);
  }

  var receivedResults = 0;
  var verifiedResults = 0;
  var conflicts = 0;
  for (final unit in units) {
    final records = resultGroups[unit.code] ?? const <ElectionResultSubmission>[];
    final accountable = records
        .where(
          (item) =>
              item.status != RecordStatus.rejected &&
              item.status != RecordStatus.archived,
        )
        .toList(growable: false);
    if (accountable.isNotEmpty) receivedResults++;
    if (accountable.any((item) => item.status == RecordStatus.verified)) {
      verifiedResults++;
    }
    final unresolved = accountable
        .where((item) => item.status != RecordStatus.disputed)
        .length;
    if (unresolved > 1) conflicts++;
  }

  final expected = units.length;
  final staffed = coverage.where((item) => !item.isBelowMinimum).length;
  final coordinateReady = units
      .where(
        (unit) =>
            unit.operationalLatitude != null &&
            unit.operationalLongitude != null,
      )
      .length;
  final coordinateReview = units
      .where(
        (unit) =>
            unit.coordinateStatus == PollingUnitCoordinateStatus.needsReview,
      )
      .length;

  final coordinatorFilled =
      scope.level == GeographyLevel.state || roles.isNotEmpty;

  int? score;
  CoverageReadinessState state;
  if (expected == 0) {
    score = null;
    state = CoverageReadinessState.cataloguePending;
  } else {
    final staffing = staffed / expected;
    final gps = deployedIds.isEmpty ? 0.0 : gpsActive / deployedIds.length;
    final coordinates = coordinateReady / expected;
    final coordinator = coordinatorFilled ? 1.0 : 0.0;
    final incidentHealth =
        (1 - (openIncidents.length / expected)).clamp(0.0, 1.0);
    score = ((staffing * 30) +
            (gps * 25) +
            (coordinates * 15) +
            (coordinator * 15) +
            (incidentHealth * 15))
        .round()
        .clamp(0, 100)
        .toInt();
    state = score >= 80
        ? CoverageReadinessState.ready
        : score >= 60
            ? CoverageReadinessState.watch
            : CoverageReadinessState.critical;
  }

  return CoverageAreaSnapshot(
    scope: scope,
    expectedPollingUnits: expected,
    staffedPollingUnits: staffed,
    activeAssignments: scopedAssignments.length,
    deployedMembers: deployedIds.length,
    gpsActiveMembers: gpsActive,
    coordinateReady: coordinateReady,
    coordinateReview: coordinateReview,
    openIncidents: openIncidents.length,
    evidenceItems:
        assignmentEvidence + incidentEvidence + reportEvidence + resultEvidence,
    receivedResultPollingUnits: receivedResults,
    verifiedResultPollingUnits: verifiedResults,
    conflictingResultPollingUnits: conflicts,
    coordinatorFilled: coordinatorFilled,
    coordinatorNames: roles
        .map((item) => item.subjectName)
        .toSet()
        .toList(growable: false),
    readinessScore: score,
    readinessState: state,
  );
}

List<CoverageExceptionItem> buildCoverageExceptions({
  required GeographicScope scope,
  required GeographyRegistry registry,
  required AssignmentController assignments,
  required GovernanceOperationsController governance,
  required FieldOperationsController field,
  required ResultOperationsController results,
  required bool resultActivityStarted,
}) {
  final items = <CoverageExceptionItem>[];
  final coordinatorScopes = scope.level == GeographyLevel.state
      ? registry
          .lgasForState(scope.stateId ?? kadunaStateId)
          .map((item) => item.scope)
          .toList(growable: false)
      : <GeographicScope>[scope];
  for (final coordinatorScope in coordinatorScopes) {
    final expectedRole = _coordinatorRoleFor(coordinatorScope.level);
    if (expectedRole == null ||
        coordinatorScope.level == GeographyLevel.state) {
      continue;
    }
    final filled = governance
        .roleAssignmentsForScope(coordinatorScope)
        .any(
          (item) =>
              item.active &&
              item.role == expectedRole &&
              _sameOperationalScope(item.scope, coordinatorScope),
        );
    if (!filled) {
      items.add(
        CoverageExceptionItem(
          kind: CoverageExceptionKind.missingCoordinator,
          scope: coordinatorScope,
          title: 'Coordinator role missing',
          detail: 'No active ${_roleTitle(expectedRole)}',
          severity: 3,
        ),
      );
    }
  }

  for (final coverage in assignments.coverageForScope(scope)) {
    if (coverage.isBelowMinimum) {
      items.add(
        CoverageExceptionItem(
          kind: CoverageExceptionKind.unstaffedPollingUnit,
          scope: coverage.unit.scope,
          title: 'Polling-unit staffing gap',
          detail:
              '${coverage.activeAssignments}/${coverage.minimumStaffing} required assignment(s)',
          severity: 3,
        ),
      );
    }
    if (coverage.staleGps > 0 || coverage.gpsMismatch > 0) {
      items.add(
        CoverageExceptionItem(
          kind: CoverageExceptionKind.gpsGap,
          scope: coverage.unit.scope,
          title: 'Field GPS attention',
          detail:
              '${coverage.staleGps} stale • ${coverage.gpsMismatch} mismatched',
          severity: 2,
        ),
      );
    }
  }

  for (final unit in registry.pollingUnitsWithin(scope)) {
    if (unit.operationalLatitude == null || unit.operationalLongitude == null) {
      items.add(
        CoverageExceptionItem(
          kind: CoverageExceptionKind.coordinateMissing,
          scope: unit.scope,
          title: 'Polling-unit coordinate missing',
          detail: unit.code,
          severity: 2,
        ),
      );
    } else if (unit.coordinateStatus ==
        PollingUnitCoordinateStatus.needsReview) {
      items.add(
        CoverageExceptionItem(
          kind: CoverageExceptionKind.coordinateReview,
          scope: unit.scope,
          title: 'Polling-unit coordinate review',
          detail: unit.code,
          severity: 2,
        ),
      );
    }
  }

  for (final incident in field.incidentsForScope(scope)) {
    if (incident.status == IncidentStatus.resolved ||
        incident.status == IncidentStatus.closed) {
      continue;
    }
    items.add(
      CoverageExceptionItem(
        kind: CoverageExceptionKind.openIncident,
        scope: incident.scope,
        title: incident.title,
        detail: incident.severity.name.toUpperCase(),
        severity: incident.severity == IncidentSeverity.critical
            ? 4
            : incident.severity == IncidentSeverity.high
                ? 3
                : 2,
      ),
    );
  }

  if (resultActivityStarted) {
    final grouped = <String, List<ElectionResultSubmission>>{};
    for (final result in results.submissionsForScope(scope)) {
      final id = result.pollingUnitScope.pollingUnitId;
      if (id == null) continue;
      grouped.putIfAbsent(id, () => []).add(result);
    }
    for (final unit in registry.pollingUnitsWithin(scope)) {
      final records = grouped[unit.code] ?? const <ElectionResultSubmission>[];
      final accountable = records
          .where(
            (item) =>
                item.status != RecordStatus.rejected &&
                item.status != RecordStatus.archived,
          )
          .toList(growable: false);
      if (accountable.isEmpty) {
        items.add(
          CoverageExceptionItem(
            kind: CoverageExceptionKind.resultMissing,
            scope: unit.scope,
            title: 'Result not received',
            detail: unit.code,
            severity: 1,
          ),
        );
      }
      final unresolved = accountable
          .where((item) => item.status != RecordStatus.disputed)
          .length;
      if (unresolved > 1) {
        items.add(
          CoverageExceptionItem(
            kind: CoverageExceptionKind.resultConflict,
            scope: unit.scope,
            title: 'Conflicting PU results',
            detail: '$unresolved unresolved submissions',
            severity: 4,
          ),
        );
      }
    }
  }

  items.sort((a, b) {
    final severity = b.severity.compareTo(a.severity);
    return severity != 0
        ? severity
        : a.scope.label.compareTo(b.scope.label);
  });
  return List.unmodifiable(items);
}

class StateCoverageIntelligencePage extends StatefulWidget {
  const StateCoverageIntelligencePage({
    super.key,
    required this.onOpenModule,
  });

  final ValueChanged<TgcgModule> onOpenModule;

  @override
  State<StateCoverageIntelligencePage> createState() =>
      _StateCoverageIntelligencePageState();
}

class _StateCoverageIntelligencePageState
    extends State<StateCoverageIntelligencePage> {
  final List<GeographicScope> _path = [GeographicScope.kaduna];
  final _search = TextEditingController();
  CoverageReadinessState? _status;

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
          title: 'State coverage unavailable',
          message: 'State Coordinator authority is required.',
        ),
      );
    }

    final membership = MembershipOperations.of(context);
    final assignments = Assignments.of(context);
    ManagedDevices.of(context);
    final governance = GovernanceOperations.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);
    final calls = OperationalCalls.of(context);
    final registry = membership.geography;
    final scope = _path.last;

    final areas = coverageChildScopes(registry, scope);
    final snapshots = areas
        .map(
          (area) => buildCoverageAreaSnapshot(
            scope: area,
            registry: registry,
            assignments: assignments,
            governance: governance,
            field: field,
            results: results,
            calls: calls,
          ),
        )
        .toList(growable: false);

    final query = _search.text.trim().toLowerCase();
    final visible = snapshots.where((item) {
      if (_status != null && item.readinessState != _status) return false;
      if (query.isEmpty) return true;
      return item.scope.label.toLowerCase().contains(query);
    }).toList(growable: false);

    final current = buildCoverageAreaSnapshot(
      scope: scope,
      registry: registry,
      assignments: assignments,
      governance: governance,
      field: field,
      results: results,
      calls: calls,
    );
    final resultActivityStarted =
        results.submissionsForScope(GeographicScope.kaduna).isNotEmpty;
    final exceptions = buildCoverageExceptions(
      scope: scope,
      registry: registry,
      assignments: assignments,
      governance: governance,
      field: field,
      results: results,
      resultActivityStarted: resultActivityStarted,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'STATE COVERAGE COMMAND',
          title: 'State Coverage Intelligence',
          subtitle: scope.label,
          trailing: TgcgStatusPill(
            label: current.readinessScore == null
                ? 'CATALOGUE PENDING'
                : 'READINESS ${current.readinessScore}%',
            color: _readinessColor(current.readinessState),
            icon: Icons.public_rounded,
          ),
        ),
        const SizedBox(height: 14),
        _CoverageBreadcrumb(
          path: _path,
          onSelect: (index) => setState(() {
            _path.removeRange(index + 1, _path.length);
            _search.clear();
            _status = null;
          }),
        ),
        const SizedBox(height: 14),
        _CoverageMetrics(snapshot: current),
        const SizedBox(height: 16),
        _CommandShortcuts(onOpen: widget.onOpenModule),
        const SizedBox(height: 16),
        _ExceptionPanel(
          items: exceptions.take(12).toList(growable: false),
          total: exceptions.length,
          onOpenScope: _openScope,
        ),
        if (scope.level != GeographyLevel.pollingUnit) ...[
          const SizedBox(height: 16),
          _CoverageFilters(
            search: _search,
            status: _status,
            onSearch: (_) => setState(() {}),
            onStatus: (value) => setState(() => _status = value),
            onClear: () {
              _search.clear();
              setState(() => _status = null);
            },
          ),
          const SizedBox(height: 16),
          TgcgSectionCard(
            title: scope.level == GeographyLevel.state
                ? 'LGA readiness board'
                : '${_childLevelTitle(scope.level)} readiness board',
            trailing: TgcgStatusPill(
              label:
                  '${visible.length} AREA${visible.length == 1 ? '' : 'S'}',
              color: TgcgColors.primary,
              compact: true,
            ),
            child: visible.isEmpty
                ? const TgcgEmptyState(
                    icon: Icons.map_outlined,
                    title: 'No matching coverage area',
                    message: 'Change the current filters.',
                  )
                : Column(
                    children: [
                      for (final snapshot in visible)
                        _CoverageAreaCard(
                          snapshot: snapshot,
                          onOpen: () => _openScope(snapshot.scope),
                        ),
                    ],
                  ),
          ),
        ],
        if (scope.level == GeographyLevel.pollingUnit) ...[
          const SizedBox(height: 16),
          _PollingUnitCommandPanel(
            scope: scope,
            membership: membership,
            assignments: assignments,
            governance: governance,
            calls: calls,
            session: session,
            onOpenModule: widget.onOpenModule,
          ),
        ] else if (scope.level != GeographyLevel.state) ...[
          const SizedBox(height: 16),
          _CoordinatorPanel(
            scope: scope,
            membership: membership,
            governance: governance,
            calls: calls,
            session: session,
          ),
        ],
      ],
    );
  }

  void _openScope(GeographicScope scope) {
    setState(() {
      final existing =
          _path.indexWhere((item) => _sameOperationalScope(item, scope));
      if (existing >= 0) {
        _path.removeRange(existing + 1, _path.length);
      } else {
        _path.add(scope);
      }
      _search.clear();
      _status = null;
    });
  }
}

class _CoverageMetrics extends StatelessWidget {
  const _CoverageMetrics({required this.snapshot});

  final CoverageAreaSnapshot snapshot;

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
                label: 'Polling units',
                value: '${snapshot.expectedPollingUnits}',
                detail: snapshot.scope.level == GeographyLevel.state
                    ? 'of $kadunaPollingUnitCount statewide target'
                    : 'loaded in scope',
                icon: Icons.how_to_vote_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Staffed',
                value:
                    '${snapshot.staffedPollingUnits}/${snapshot.expectedPollingUnits}',
                detail: 'minimum assignment coverage',
                icon: Icons.groups_2_outlined,
                tone: snapshot.unstaffedPollingUnits == 0 &&
                        snapshot.expectedPollingUnits > 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'GPS active',
                value:
                    '${snapshot.gpsActiveMembers}/${snapshot.deployedMembers}',
                detail: 'fresh deployed-member location',
                icon: Icons.gps_fixed_rounded,
                tone: snapshot.gpsInactiveMembers == 0 &&
                        snapshot.deployedMembers > 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Coordinates',
                value:
                    '${snapshot.coordinateReady}/${snapshot.expectedPollingUnits}',
                detail: 'PU coordinate ready',
                icon: Icons.location_on_outlined,
                tone: snapshot.expectedPollingUnits > 0 &&
                        snapshot.coordinateReady ==
                            snapshot.expectedPollingUnits
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Incidents',
                value: '${snapshot.openIncidents}',
                detail: '${snapshot.evidenceItems} evidence records',
                icon: Icons.crisis_alert_outlined,
                tone: snapshot.openIncidents == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Results',
                value:
                    '${snapshot.verifiedResultPollingUnits}/${snapshot.receivedResultPollingUnits}',
                detail: 'verified / received PU results',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.ai,
              ),
            ],
          );
        },
      );
}

class _CommandShortcuts extends StatelessWidget {
  const _CommandShortcuts({required this.onOpen});

  final ValueChanged<TgcgModule> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Command actions',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.assignmentControl),
              icon: const Icon(Icons.assignment_ind_outlined),
              label: const Text('Assignment Control'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.fieldMonitoring),
              icon: const Icon(Icons.sensors_outlined),
              label: const Text('Field Monitoring'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.evidenceCapture),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Evidence Intelligence'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.resultCapture),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Result Intelligence'),
            ),
          ],
        ),
      );
}

class _ExceptionPanel extends StatelessWidget {
  const _ExceptionPanel({
    required this.items,
    required this.total,
    required this.onOpenScope,
  });

  final List<CoverageExceptionItem> items;
  final int total;
  final ValueChanged<GeographicScope> onOpenScope;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Needs attention',
        trailing: TgcgStatusPill(
          label: '$total OPEN',
          color: total == 0 ? TgcgColors.success : TgcgColors.warning,
          icon: Icons.warning_amber_rounded,
          compact: true,
        ),
        child: items.isEmpty
            ? const TgcgStatusPill(
                label: 'NO CURRENT COVERAGE EXCEPTION',
                color: TgcgColors.success,
                icon: Icons.check_circle_outline_rounded,
              )
            : Column(
                children: [
                  for (final item in items)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onOpenScope(item.scope),
                        borderRadius: BorderRadius.circular(TgcgRadius.sm),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _exceptionColor(item.severity)
                                .withValues(alpha: .04),
                            borderRadius:
                                BorderRadius.circular(TgcgRadius.sm),
                            border: Border.all(
                              color: _exceptionColor(item.severity)
                                  .withValues(alpha: .18),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _exceptionIcon(item.kind),
                                color: _exceptionColor(item.severity),
                                size: 19,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        color: TgcgColors.ink,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      '${item.scope.label} • ${item.detail}',
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

class _CoverageFilters extends StatelessWidget {
  const _CoverageFilters({
    required this.search,
    required this.status,
    required this.onSearch,
    required this.onStatus,
    required this.onClear,
  });

  final TextEditingController search;
  final CoverageReadinessState? status;
  final ValueChanged<String> onSearch;
  final ValueChanged<CoverageReadinessState?> onStatus;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Coverage filters',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: search,
                onChanged: onSearch,
                decoration: const InputDecoration(
                  labelText: 'Search area',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<CoverageReadinessState?>(
                initialValue: status,
                decoration:
                    const InputDecoration(labelText: 'Readiness state'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All states'),
                  ),
                  for (final item in CoverageReadinessState.values)
                    DropdownMenuItem(
                      value: item,
                      child: Text(_readinessLabel(item)),
                    ),
                ],
                onChanged: onStatus,
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

class _CoverageAreaCard extends StatelessWidget {
  const _CoverageAreaCard({
    required this.snapshot,
    required this.onOpen,
  });

  final CoverageAreaSnapshot snapshot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final color = _readinessColor(snapshot.readinessState);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: TgcgColors.surfaceRaised,
              borderRadius: BorderRadius.circular(TgcgRadius.md),
              border: Border.all(color: TgcgColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(TgcgRadius.sm),
                  ),
                  child: Text(
                    snapshot.readinessScore == null
                        ? '—'
                        : '${snapshot.readinessScore}',
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
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
                        snapshot.scope.label,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          TgcgStatusPill(
                            label: _readinessLabel(snapshot.readinessState)
                                .toUpperCase(),
                            color: color,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label:
                                'STAFF ${snapshot.staffedPollingUnits}/${snapshot.expectedPollingUnits}',
                            color: snapshot.expectedPollingUnits > 0 &&
                                    snapshot.staffedPollingUnits ==
                                        snapshot.expectedPollingUnits
                                ? TgcgColors.success
                                : TgcgColors.warning,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label:
                                'GPS ${snapshot.gpsActiveMembers}/${snapshot.deployedMembers}',
                            color: snapshot.deployedMembers > 0 &&
                                    snapshot.gpsActiveMembers ==
                                        snapshot.deployedMembers
                                ? TgcgColors.success
                                : TgcgColors.warning,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label: snapshot.coordinatorFilled
                                ? 'COORDINATOR'
                                : 'NO COORDINATOR',
                            color: snapshot.coordinatorFilled
                                ? TgcgColors.success
                                : TgcgColors.danger,
                            compact: true,
                          ),
                          if (snapshot.openIncidents > 0)
                            TgcgStatusPill(
                              label:
                                  '${snapshot.openIncidents} INCIDENT${snapshot.openIncidents == 1 ? '' : 'S'}',
                              color: TgcgColors.danger,
                              compact: true,
                            ),
                          if (snapshot.conflictingResultPollingUnits > 0)
                            TgcgStatusPill(
                              label:
                                  '${snapshot.conflictingResultPollingUnits} RESULT CONFLICT',
                              color: TgcgColors.danger,
                              compact: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${snapshot.activeAssignments} assignments • '
                        '${snapshot.evidenceItems} evidence • '
                        '${snapshot.receivedResultPollingUnits} result PUs • '
                        '${snapshot.coordinateReady}/${snapshot.expectedPollingUnits} coordinates',
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
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
    );
  }
}

class _CoordinatorPanel extends StatelessWidget {
  const _CoordinatorPanel({
    required this.scope,
    required this.membership,
    required this.governance,
    required this.calls,
    required this.session,
  });

  final GeographicScope scope;
  final MembershipOperationsController membership;
  final GovernanceOperationsController governance;
  final OperationalCallController calls;
  final TgcgSessionController session;

  @override
  Widget build(BuildContext context) {
    final expectedRole = _coordinatorRoleFor(scope.level);
    final coordinators = expectedRole == null
        ? const <RoleAssignmentRecord>[]
        : governance
            .roleAssignmentsForScope(scope)
            .where(
              (item) =>
                  item.active &&
                  item.role == expectedRole &&
                  _sameOperationalScope(item.scope, scope),
            )
            .toList(growable: false);

    return TgcgSectionCard(
      title: 'Area coordinator',
      child: coordinators.isEmpty
          ? const TgcgStatusPill(
              label: 'COORDINATOR ROLE VACANT',
              color: TgcgColors.danger,
              icon: Icons.person_off_outlined,
            )
          : Column(
              children: [
                for (final role in coordinators)
                  _MemberCommandRow(
                    member: membership.memberById(role.subjectId),
                    fallbackName: role.subjectName,
                    detail: _roleTitle(role.role),
                    calls: calls,
                    session: session,
                  ),
              ],
            ),
    );
  }
}

class _PollingUnitCommandPanel extends StatelessWidget {
  const _PollingUnitCommandPanel({
    required this.scope,
    required this.membership,
    required this.assignments,
    required this.governance,
    required this.calls,
    required this.session,
    required this.onOpenModule,
  });

  final GeographicScope scope;
  final MembershipOperationsController membership;
  final AssignmentController assignments;
  final GovernanceOperationsController governance;
  final OperationalCallController calls;
  final TgcgSessionController session;
  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final memberIds = <String>{
      ...assignments
          .assignmentsForScope(scope)
          .where((item) => !item.isTerminal)
          .map((item) => item.memberId),
      ...governance
          .roleAssignmentsForScope(scope)
          .where(
            (item) =>
                item.active &&
                _sameOperationalScope(item.scope, scope),
          )
          .map((item) => item.subjectId),
    };
    final rows = memberIds
        .map(membership.memberById)
        .whereType<TgcgMember>()
        .toList(growable: false);

    return TgcgSectionCard(
      title: 'Polling-unit command',
      trailing: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          TextButton(
            onPressed: () => onOpenModule(TgcgModule.assignmentControl),
            child: const Text('Assignments'),
          ),
          TextButton(
            onPressed: () => onOpenModule(TgcgModule.evidenceCapture),
            child: const Text('Evidence'),
          ),
          TextButton(
            onPressed: () => onOpenModule(TgcgModule.resultCapture),
            child: const Text('Result'),
          ),
        ],
      ),
      child: rows.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No deployed member',
              message: 'No active member is currently linked to this PU.',
            )
          : Column(
              children: [
                for (final member in rows)
                  _MemberCommandRow(
                    member: member,
                    fallbackName: member.fullName,
                    detail: 'Polling-unit operation',
                    calls: calls,
                    session: session,
                  ),
              ],
            ),
    );
  }
}

class _MemberCommandRow extends StatelessWidget {
  const _MemberCommandRow({
    required this.member,
    required this.fallbackName,
    required this.detail,
    required this.calls,
    required this.session,
  });

  final TgcgMember? member;
  final String fallbackName;
  final String detail;
  final OperationalCallController calls;
  final TgcgSessionController session;

  @override
  Widget build(BuildContext context) {
    final memberId = member?.id;
    final gps =
        memberId == null ? null : calls.gpsSnapshotForMember(memberId);
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
              fallbackName.isEmpty ? '?' : fallbackName[0].toUpperCase(),
              style: const TextStyle(
                color: TgcgColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fallbackName,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          TgcgStatusPill(
            label: gps == null ? 'GPS INACTIVE' : 'GPS ACTIVE',
            color: gps == null ? TgcgColors.warning : TgcgColors.success,
            icon:
                gps == null ? Icons.gps_off_rounded : Icons.gps_fixed_rounded,
            compact: true,
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Audio call',
            onPressed: member == null || gps == null
                ? null
                : () => _call(
                      context,
                      member!,
                      OperationalCallKind.audio,
                    ),
            icon: const Icon(Icons.call_outlined),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Video call',
            onPressed: member == null || gps == null
                ? null
                : () => _call(
                      context,
                      member!,
                      OperationalCallKind.video,
                    ),
            icon: const Icon(Icons.videocam_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _call(
    BuildContext context,
    TgcgMember target,
    OperationalCallKind kind,
  ) async {
    try {
      await startStateCoordinatorMemberCall(
        context,
        calls: calls,
        session: session,
        stateScope: GeographicScope.kaduna,
        member: target,
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

class _CoverageBreadcrumb extends StatelessWidget {
  const _CoverageBreadcrumb({
    required this.path,
    required this.onSelect,
  });

  final List<GeographicScope> path;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 5,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var index = 0; index < path.length; index++) ...[
            ActionChip(
              label: Text(_shortScopeLabel(path[index])),
              onPressed:
                  index == path.length - 1 ? null : () => onSelect(index),
            ),
            if (index != path.length - 1)
              const Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: TgcgColors.muted,
              ),
          ],
        ],
      );
}

List<GeographicScope> coverageChildScopes(
  GeographyRegistry registry,
  GeographicScope scope,
) {
  if (scope.level == GeographyLevel.state) {
    return registry
        .lgasForState(scope.stateId ?? kadunaStateId)
        .map((item) => item.scope)
        .toList(growable: false);
  }
  if (scope.level == GeographyLevel.ward) {
    return registry
        .pollingUnitsWithin(scope)
        .map((item) => item.scope)
        .toList(growable: false);
  }
  if (scope.level == GeographyLevel.pollingUnit) return const [];
  return registry.childScopes(scope);
}

TgcgRole? _coordinatorRoleFor(GeographyLevel level) => switch (level) {
      GeographyLevel.state => TgcgRole.stateCoordinator,
      GeographyLevel.senatorialDistrict => TgcgRole.senatorialCoordinator,
      GeographyLevel.lga => TgcgRole.lgaCoordinator,
      GeographyLevel.ward => TgcgRole.wardCoordinator,
      GeographyLevel.pollingUnit => TgcgRole.pollingUnitCoordinator,
      GeographyLevel.country || GeographyLevel.geopoliticalZone => null,
    };

bool _sameOperationalScope(GeographicScope a, GeographicScope b) =>
    a.level == b.level &&
    a.stateId == b.stateId &&
    a.senatorialDistrictId == b.senatorialDistrictId &&
    a.lgaId == b.lgaId &&
    a.wardId == b.wardId &&
    a.pollingUnitId == b.pollingUnitId;

String _shortScopeLabel(GeographicScope scope) => switch (scope.level) {
      GeographyLevel.state => scope.stateName ?? 'State',
      GeographyLevel.senatorialDistrict =>
        scope.senatorialDistrictName ?? 'Senatorial',
      GeographyLevel.lga => scope.lgaName ?? 'LGA',
      GeographyLevel.ward => scope.wardName ?? 'Ward',
      GeographyLevel.pollingUnit => scope.pollingUnitName ?? 'PU',
      GeographyLevel.country => scope.country,
      GeographyLevel.geopoliticalZone => scope.zoneName ?? 'Zone',
    };

String _childLevelTitle(GeographyLevel level) => switch (level) {
      GeographyLevel.state || GeographyLevel.senatorialDistrict => 'LGA',
      GeographyLevel.lga => 'Ward',
      GeographyLevel.ward || GeographyLevel.pollingUnit => 'Polling-unit',
      GeographyLevel.country || GeographyLevel.geopoliticalZone => 'State',
    };

String _roleTitle(TgcgRole role) => switch (role) {
      TgcgRole.stateCoordinator => 'State Coordinator',
      TgcgRole.senatorialCoordinator => 'Senatorial Coordinator',
      TgcgRole.lgaCoordinator => 'LGA Coordinator',
      TgcgRole.wardCoordinator => 'Ward Coordinator',
      TgcgRole.pollingUnitCoordinator => 'Polling Unit Coordinator',
      _ => role.name,
    };

String _readinessLabel(CoverageReadinessState state) => switch (state) {
      CoverageReadinessState.ready => 'Ready',
      CoverageReadinessState.watch => 'Watch',
      CoverageReadinessState.critical => 'Critical',
      CoverageReadinessState.cataloguePending => 'Catalogue pending',
    };

Color _readinessColor(CoverageReadinessState state) => switch (state) {
      CoverageReadinessState.ready => TgcgColors.success,
      CoverageReadinessState.watch => TgcgColors.warning,
      CoverageReadinessState.critical => TgcgColors.danger,
      CoverageReadinessState.cataloguePending => TgcgColors.muted,
    };

Color _exceptionColor(int severity) => severity >= 4
    ? TgcgColors.danger
    : severity >= 2
        ? TgcgColors.warning
        : TgcgColors.info;

IconData _exceptionIcon(CoverageExceptionKind kind) => switch (kind) {
      CoverageExceptionKind.missingCoordinator =>
        Icons.person_off_outlined,
      CoverageExceptionKind.unstaffedPollingUnit =>
        Icons.group_off_outlined,
      CoverageExceptionKind.gpsGap => Icons.gps_off_rounded,
      CoverageExceptionKind.coordinateMissing =>
        Icons.location_off_outlined,
      CoverageExceptionKind.coordinateReview =>
        Icons.rule_folder_outlined,
      CoverageExceptionKind.openIncident =>
        Icons.crisis_alert_outlined,
      CoverageExceptionKind.resultConflict =>
        Icons.compare_arrows_rounded,
      CoverageExceptionKind.resultMissing =>
        Icons.hourglass_empty_rounded,
    };
