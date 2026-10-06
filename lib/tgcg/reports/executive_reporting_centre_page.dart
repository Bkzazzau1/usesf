import 'package:flutter/material.dart';

import '../access/access_policy.dart';
import '../ai/state_ai_review_centre_page.dart';
import '../assignments/assignment_store.dart';
import '../devices/managed_device_store.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../edge_ai/assignment_edge_ai_store.dart';
import '../evidence/evidence_store.dart';
import '../field/field_operations_store.dart';
import '../geography/state_coverage_intelligence_page.dart';
import '../governance/governance_store.dart';
import '../meeting/operational_call_store.dart';
import '../membership/membership_intelligence_page.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'report_store.dart';

class ExecutiveBriefingSnapshot {
  const ExecutiveBriefingSnapshot({
    required this.generatedAt,
    required this.stateCoverage,
    required this.lgaCoverage,
    required this.leadership,
    required this.totalMembers,
    required this.activeMembers,
    required this.pendingActivation,
    required this.blockedMembers,
    required this.membersWithoutRole,
    required this.deployedMembers,
    required this.gpsActiveDeployedMembers,
    required this.openIncidents,
    required this.highCriticalIncidents,
    required this.evidenceRecords,
    required this.hashedEvidenceRecords,
    required this.aiReviewCases,
    required this.criticalAiCases,
    required this.coverageExceptions,
  });

  final DateTime generatedAt;
  final CoverageAreaSnapshot stateCoverage;
  final List<CoverageAreaSnapshot> lgaCoverage;
  final LeadershipCoverageSummary leadership;
  final int totalMembers;
  final int activeMembers;
  final int pendingActivation;
  final int blockedMembers;
  final int membersWithoutRole;
  final int deployedMembers;
  final int gpsActiveDeployedMembers;
  final int openIncidents;
  final int highCriticalIncidents;
  final int evidenceRecords;
  final int hashedEvidenceRecords;
  final List<StateAiReviewCase> aiReviewCases;
  final int criticalAiCases;
  final List<CoverageExceptionItem> coverageExceptions;

  int get lgaReady => lgaCoverage
      .where((item) => item.readinessState == CoverageReadinessState.ready)
      .length;

  int get lgaWatch => lgaCoverage
      .where((item) => item.readinessState == CoverageReadinessState.watch)
      .length;

  int get lgaCritical => lgaCoverage
      .where((item) => item.readinessState == CoverageReadinessState.critical)
      .length;

  int get lgaCataloguePending => lgaCoverage
      .where(
        (item) =>
            item.readinessState == CoverageReadinessState.cataloguePending,
      )
      .length;

  int get vacantLgaCoordinators =>
      (leadership.lgaExpected - leadership.lgaFilled)
          .clamp(0, leadership.lgaExpected)
          .toInt();

  int get resultMissing =>
      (stateCoverage.expectedPollingUnits -
              stateCoverage.receivedResultPollingUnits)
          .clamp(0, stateCoverage.expectedPollingUnits)
          .toInt();
}

class ExecutivePriorityItem {
  const ExecutivePriorityItem({
    required this.title,
    required this.detail,
    required this.severity,
    required this.module,
  });

  final String title;
  final String detail;
  final int severity;
  final TgcgModule module;
}

ExecutiveBriefingSnapshot buildExecutiveBriefingSnapshot({
  required MembershipOperationsController membership,
  required AssignmentController assignments,
  required ManagedDeviceController devices,
  required GovernanceOperationsController governance,
  required FieldOperationsController field,
  required ResultOperationsController results,
  required OperationalCallController calls,
  required AssignmentEdgeAiController edgeAi,
  required EvidenceOperationsController evidence,
  DateTime? now,
}) {
  final registry = membership.geography;
  final state = buildCoverageAreaSnapshot(
    scope: GeographicScope.kaduna,
    registry: registry,
    assignments: assignments,
    governance: governance,
    field: field,
    results: results,
    calls: calls,
  );
  final lgaCoverage = coverageChildScopes(
    registry,
    GeographicScope.kaduna,
  )
      .map(
        (scope) => buildCoverageAreaSnapshot(
          scope: scope,
          registry: registry,
          assignments: assignments,
          governance: governance,
          field: field,
          results: results,
          calls: calls,
        ),
      )
      .toList(growable: false)
    ..sort(_coverageSort);

  final leadership = buildLeadershipCoverage(
    membership: membership,
    governance: governance,
  );

  final memberSnapshots = membership.members
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
      .toList(growable: false);

  final aiCases = buildStateAiReviewCases(
    membership: membership,
    assignments: assignments,
    edgeAi: edgeAi,
    directEvidence: evidence,
    field: field,
    results: results,
    now: now,
  );

  final resultActivityStarted =
      results.submissionsForScope(GeographicScope.kaduna).isNotEmpty;
  final coverageExceptions = buildCoverageExceptions(
    scope: GeographicScope.kaduna,
    registry: registry,
    assignments: assignments,
    governance: governance,
    field: field,
    results: results,
    resultActivityStarted: resultActivityStarted,
  );

  final evidenceById = <String, EvidenceAttachment>{};
  void addEvidence(EvidenceAttachment item) => evidenceById[item.id] = item;

  for (final item in evidence.recordsForScope(GeographicScope.kaduna)) {
    addEvidence(item.evidence);
  }
  for (final assignment
      in assignments.assignmentsForScope(GeographicScope.kaduna)) {
    for (final item in assignment.evidence) {
      addEvidence(item);
    }
  }
  for (final incident in field.incidentsForScope(GeographicScope.kaduna)) {
    for (final item in incident.evidence) {
      addEvidence(item);
    }
  }
  for (final report in field.reportsForScope(GeographicScope.kaduna)) {
    for (final item in report.evidence) {
      addEvidence(item);
    }
  }
  for (final result in results.submissionsForScope(GeographicScope.kaduna)) {
    if (result.resultForm != null) addEvidence(result.resultForm!);
  }

  final incidents = field.incidentsForScope(GeographicScope.kaduna);
  final openIncidents = incidents
      .where(
        (item) =>
            item.status != IncidentStatus.resolved &&
            item.status != IncidentStatus.closed,
      )
      .toList(growable: false);
  final highCritical = openIncidents
      .where(
        (item) =>
            item.severity == IncidentSeverity.high ||
            item.severity == IncidentSeverity.critical,
      )
      .length;

  return ExecutiveBriefingSnapshot(
    generatedAt: (now ?? DateTime.now()).toUtc(),
    stateCoverage: state,
    lgaCoverage: List.unmodifiable(lgaCoverage),
    leadership: leadership,
    totalMembers: memberSnapshots.length,
    activeMembers: memberSnapshots
        .where(
          (item) =>
              item.member.accountStatus == MemberAccountStatus.active &&
              !item.member.isBlocked,
        )
        .length,
    pendingActivation: memberSnapshots
        .where(
          (item) =>
              item.member.isPendingActivation && !item.member.isBlocked,
        )
        .length,
    blockedMembers:
        memberSnapshots.where((item) => item.member.isBlocked).length,
    membersWithoutRole:
        memberSnapshots.where((item) => item.roles.isEmpty).length,
    deployedMembers:
        memberSnapshots.where((item) => item.isDeployed).length,
    gpsActiveDeployedMembers:
        memberSnapshots.where((item) => item.isDeployed && item.gps != null).length,
    openIncidents: openIncidents.length,
    highCriticalIncidents: highCritical,
    evidenceRecords: evidenceById.length,
    hashedEvidenceRecords: evidenceById.values
        .where(
          (item) =>
              item.contentHash != null &&
              item.contentHash!.trim().isNotEmpty,
        )
        .length,
    aiReviewCases: List.unmodifiable(aiCases),
    criticalAiCases: aiCases
        .where((item) => item.severity == StateAiReviewSeverity.critical)
        .length,
    coverageExceptions: List.unmodifiable(coverageExceptions),
  );
}

List<ExecutivePriorityItem> buildExecutivePriorities(
  ExecutiveBriefingSnapshot snapshot,
) {
  final items = <ExecutivePriorityItem>[];

  for (final review in snapshot.aiReviewCases) {
    if (review.severity != StateAiReviewSeverity.critical) continue;
    items.add(
      ExecutivePriorityItem(
        title: review.title,
        detail: review.detail,
        severity: 4,
        module: TgcgModule.aiVerification,
      ),
    );
  }

  for (final exception in snapshot.coverageExceptions) {
    if (exception.severity < 3) continue;
    items.add(
      ExecutivePriorityItem(
        title: exception.title,
        detail: '${exception.scope.label} • ${exception.detail}',
        severity: exception.severity,
        module: TgcgModule.geography,
      ),
    );
  }

  if (snapshot.vacantLgaCoordinators > 0) {
    items.add(
      ExecutivePriorityItem(
        title: 'LGA leadership vacancies',
        detail:
            '${snapshot.vacantLgaCoordinators}/${snapshot.leadership.lgaExpected} LGA Coordinator posts are vacant.',
        severity: 3,
        module: TgcgModule.membershipNetwork,
      ),
    );
  }

  if (snapshot.highCriticalIncidents > 0) {
    items.add(
      ExecutivePriorityItem(
        title: 'High / critical incidents open',
        detail:
            '${snapshot.highCriticalIncidents} high-priority incident(s) require operational attention.',
        severity: 4,
        module: TgcgModule.fieldMonitoring,
      ),
    );
  }

  if (snapshot.stateCoverage.conflictingResultPollingUnits > 0) {
    items.add(
      ExecutivePriorityItem(
        title: 'Result conflicts unresolved',
        detail:
            '${snapshot.stateCoverage.conflictingResultPollingUnits} polling unit(s) have conflicting result submissions.',
        severity: 4,
        module: TgcgModule.resultCapture,
      ),
    );
  }

  items.sort((a, b) {
    final severity = b.severity.compareTo(a.severity);
    if (severity != 0) return severity;
    return a.title.compareTo(b.title);
  });
  return List.unmodifiable(items);
}

class ExecutiveReportingCentrePage extends StatefulWidget {
  const ExecutiveReportingCentrePage({
    super.key,
    required this.onOpenModule,
  });

  final ValueChanged<TgcgModule> onOpenModule;

  @override
  State<ExecutiveReportingCentrePage> createState() =>
      _ExecutiveReportingCentrePageState();
}

class _ExecutiveReportingCentrePageState
    extends State<ExecutiveReportingCentrePage> {
  ReportKind _selectedKind = ReportKind.executiveBrief;
  ExportJobStatus? _jobStatus;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (session.role != TgcgRole.stateCoordinator) {
      return const Center(
        child: TgcgEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Executive Reporting unavailable',
          message: 'State Coordinator authority is required.',
        ),
      );
    }

    final membership = MembershipOperations.of(context);
    final assignments = Assignments.of(context);
    final devices = ManagedDevices.of(context);
    final governance = GovernanceOperations.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);
    final calls = OperationalCalls.of(context);
    final edgeAi = AssignmentEdgeAi.of(context);
    final evidence = EvidenceOperations.of(context);
    final reports = ReportOperations.of(context);

    final snapshot = buildExecutiveBriefingSnapshot(
      membership: membership,
      assignments: assignments,
      devices: devices,
      governance: governance,
      field: field,
      results: results,
      calls: calls,
      edgeAi: edgeAi,
      evidence: evidence,
    );
    final priorities = buildExecutivePriorities(snapshot);

    final capabilities = TgcgAccessPolicy.capabilitiesForTarget(
      context,
      GeographicScope.kaduna,
    );
    final packages = _executivePackages(
      snapshot: snapshot,
      store: reports,
      capabilities: capabilities,
    );
    final selected = packages.firstWhere(
      (item) => item.kind == _selectedKind,
      orElse: () => packages.first,
    );

    var jobs = reports.jobsForScope(
      GeographicScope.kaduna,
      role: TgcgRole.stateCoordinator,
    );
    if (_jobStatus != null) {
      jobs = jobs
          .where((item) => item.status == _jobStatus)
          .toList(growable: false);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'STATE EXECUTIVE BRIEFING',
          title: 'Executive Reporting Centre',
          subtitle: 'Kaduna State • ${_time(snapshot.generatedAt)}',
          trailing: const TgcgStatusPill(
            label: 'AUDITED EXPORTS',
            color: TgcgColors.primary,
            icon: Icons.verified_user_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _ExecutiveMetrics(snapshot: snapshot),
        const SizedBox(height: 16),
        _ExecutiveCommandActions(onOpen: widget.onOpenModule),
        const SizedBox(height: 16),
        _PriorityPanel(
          items: priorities.take(12).toList(growable: false),
          total: priorities.length,
          onOpen: widget.onOpenModule,
        ),
        const SizedBox(height: 16),
        _LgaPerformanceBoard(
          snapshots: snapshot.lgaCoverage,
          onOpenCoverage: () =>
              widget.onOpenModule(TgcgModule.geography),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final catalogue = _ExecutivePackageCatalogue(
              packages: packages,
              selectedKind: selected.kind,
              onSelect: (kind) => setState(() => _selectedKind = kind),
            );
            final preview = _ExecutivePackagePreview(
              package: selected,
              onExport: (format) => _requestExport(
                context,
                package: selected,
                format: format,
              ),
            );

            if (constraints.maxWidth < 1050) {
              return Column(
                children: [
                  catalogue,
                  const SizedBox(height: 14),
                  preview,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 370, child: catalogue),
                const SizedBox(width: 14),
                Expanded(child: preview),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _ExecutiveJobHistory(
          jobs: jobs,
          status: _jobStatus,
          onStatus: (value) => setState(() => _jobStatus = value),
          onClear: () => setState(() => _jobStatus = null),
        ),
      ],
    );
  }

  void _requestExport(
    BuildContext context, {
    required _ExecutiveReportPackage package,
    required ExportFormat format,
  }) {
    final session = TgcgSession.of(context, listen: false);
    final store = ReportOperations.of(context, listen: false);
    final job = store.requestExport(
      kind: package.kind,
      format: format,
      targetScope: GeographicScope.kaduna,
      actorId:
          session.accessId.isEmpty ? session.operatorName : session.accessId,
      role: TgcgRole.stateCoordinator,
      userScope: GeographicScope.kaduna,
      effectiveCapabilities: TgcgAccessPolicy.capabilitiesForTarget(
        context,
        GeographicScope.kaduna,
        listen: false,
      ),
      recordCount: package.recordCount,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          job == null
              ? 'This executive export is not authorized.'
              : '${job.id} queued for the export worker.',
        ),
      ),
    );
  }
}

class _ExecutiveReportPackage {
  const _ExecutiveReportPackage({
    required this.kind,
    required this.title,
    required this.detail,
    required this.icon,
    required this.formats,
    required this.enabled,
    required this.recordCount,
    required this.rows,
  });

  final ReportKind kind;
  final String title;
  final String detail;
  final IconData icon;
  final List<ExportFormat> formats;
  final bool enabled;
  final int recordCount;
  final List<(String, String)> rows;
}

List<_ExecutiveReportPackage> _executivePackages({
  required ExecutiveBriefingSnapshot snapshot,
  required ReportOperationsController store,
  required Set<TgcgCapability> capabilities,
}) {
  bool allowed(ReportKind kind) => store.canExportKind(
        kind: kind,
        role: TgcgRole.stateCoordinator,
        userScope: GeographicScope.kaduna,
        targetScope: GeographicScope.kaduna,
        effectiveCapabilities: capabilities,
      );

  return [
    _ExecutiveReportPackage(
      kind: ReportKind.executiveBrief,
      title: 'Executive Brief',
      detail:
          'Statewide readiness, people, incidents, AI review and result-accounting summary.',
      icon: Icons.summarize_outlined,
      formats: const [ExportFormat.pdf, ExportFormat.json],
      enabled: allowed(ReportKind.executiveBrief),
      recordCount: snapshot.lgaCoverage.length +
          snapshot.aiReviewCases.length +
          snapshot.coverageExceptions.length,
      rows: [
        ('State readiness', _score(snapshot.stateCoverage)),
        (
          'LGA ready / watch / critical',
          '${snapshot.lgaReady} / ${snapshot.lgaWatch} / ${snapshot.lgaCritical}',
        ),
        (
          'Members active / total',
          '${snapshot.activeMembers} / ${snapshot.totalMembers}',
        ),
        (
          'AI review / critical',
          '${snapshot.aiReviewCases.length} / ${snapshot.criticalAiCases}',
        ),
        (
          'Results verified / received',
          '${snapshot.stateCoverage.verifiedResultPollingUnits} / ${snapshot.stateCoverage.receivedResultPollingUnits}',
        ),
      ],
    ),
    _ExecutiveReportPackage(
      kind: ReportKind.incidentSummary,
      title: 'Incident Summary',
      detail: 'Open operational incidents and severity accounting.',
      icon: Icons.crisis_alert_outlined,
      formats: const [
        ExportFormat.pdf,
        ExportFormat.csv,
        ExportFormat.json,
      ],
      enabled: allowed(ReportKind.incidentSummary),
      recordCount: snapshot.openIncidents,
      rows: [
        ('Open incidents', '${snapshot.openIncidents}'),
        ('High / critical', '${snapshot.highCriticalIncidents}'),
      ],
    ),
    _ExecutiveReportPackage(
      kind: ReportKind.membershipDeployment,
      title: 'Membership & Deployment',
      detail: 'People readiness, leadership and deployment coverage.',
      icon: Icons.groups_2_outlined,
      formats: const [
        ExportFormat.pdf,
        ExportFormat.csv,
        ExportFormat.json,
      ],
      enabled: allowed(ReportKind.membershipDeployment),
      recordCount: snapshot.totalMembers,
      rows: [
        ('Members', '${snapshot.totalMembers}'),
        ('Active', '${snapshot.activeMembers}'),
        ('Pending activation', '${snapshot.pendingActivation}'),
        ('Blocked', '${snapshot.blockedMembers}'),
        ('Without role', '${snapshot.membersWithoutRole}'),
        (
          'LGA coordinators',
          '${snapshot.leadership.lgaFilled}/${snapshot.leadership.lgaExpected}',
        ),
      ],
    ),
    _ExecutiveReportPackage(
      kind: ReportKind.verifiedCollation,
      title: 'Verified Result Accounting',
      detail:
          'Unofficial verified-only result accounting with missing/conflict visibility.',
      icon: Icons.account_tree_outlined,
      formats: const [
        ExportFormat.pdf,
        ExportFormat.csv,
        ExportFormat.json,
      ],
      enabled: allowed(ReportKind.verifiedCollation),
      recordCount: snapshot.stateCoverage.verifiedResultPollingUnits,
      rows: [
        (
          'Loaded expected PUs',
          '${snapshot.stateCoverage.expectedPollingUnits}',
        ),
        (
          'Received',
          '${snapshot.stateCoverage.receivedResultPollingUnits}',
        ),
        (
          'Verified',
          '${snapshot.stateCoverage.verifiedResultPollingUnits}',
        ),
        ('Missing', '${snapshot.resultMissing}'),
        (
          'Conflicts',
          '${snapshot.stateCoverage.conflictingResultPollingUnits}',
        ),
      ],
    ),
    _ExecutiveReportPackage(
      kind: ReportKind.evidencePackage,
      title: 'Evidence Package',
      detail: 'Evidence records with integrity/provenance metadata.',
      icon: Icons.inventory_2_outlined,
      formats: const [ExportFormat.zip, ExportFormat.json],
      enabled: allowed(ReportKind.evidencePackage),
      recordCount: snapshot.evidenceRecords,
      rows: [
        ('Evidence', '${snapshot.evidenceRecords}'),
        ('Hashed', '${snapshot.hashedEvidenceRecords}'),
        (
          'Integrity gap',
          '${snapshot.evidenceRecords - snapshot.hashedEvidenceRecords}',
        ),
      ],
    ),
  ];
}

class _ExecutiveMetrics extends StatelessWidget {
  const _ExecutiveMetrics({required this.snapshot});

  final ExecutiveBriefingSnapshot snapshot;

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
                label: 'State readiness',
                value: _score(snapshot.stateCoverage),
                detail:
                    '${snapshot.lgaCritical} critical • ${snapshot.lgaWatch} watch',
                icon: Icons.speed_rounded,
                tone: _coverageTone(snapshot.stateCoverage),
              ),
              TgcgMetricCard(
                width: width,
                label: 'Members',
                value: '${snapshot.activeMembers}/${snapshot.totalMembers}',
                detail:
                    '${snapshot.pendingActivation} pending • ${snapshot.blockedMembers} blocked',
                icon: Icons.groups_2_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Leadership',
                value:
                    '${snapshot.leadership.lgaFilled}/${snapshot.leadership.lgaExpected}',
                detail: 'LGA coordinator posts filled',
                icon: Icons.admin_panel_settings_outlined,
                tone: snapshot.vacantLgaCoordinators == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'AI review',
                value: '${snapshot.aiReviewCases.length}',
                detail: '${snapshot.criticalAiCases} critical',
                icon: Icons.auto_awesome_rounded,
                tone: snapshot.criticalAiCases == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Incidents',
                value: '${snapshot.openIncidents}',
                detail: '${snapshot.highCriticalIncidents} high / critical',
                icon: Icons.crisis_alert_outlined,
                tone: snapshot.highCriticalIncidents == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Results',
                value:
                    '${snapshot.stateCoverage.verifiedResultPollingUnits}/${snapshot.stateCoverage.receivedResultPollingUnits}',
                detail:
                    '${snapshot.stateCoverage.conflictingResultPollingUnits} conflict PUs',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.ai,
              ),
            ],
          );
        },
      );
}

class _ExecutiveCommandActions extends StatelessWidget {
  const _ExecutiveCommandActions({required this.onOpen});

  final ValueChanged<TgcgModule> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Executive workspaces',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.geography),
              icon: const Icon(Icons.public_outlined),
              label: const Text('State Coverage'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.membershipNetwork),
              icon: const Icon(Icons.groups_2_outlined),
              label: const Text('Membership'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.aiVerification),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('AI Review'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.resultCapture),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Results'),
            ),
          ],
        ),
      );
}

class _PriorityPanel extends StatelessWidget {
  const _PriorityPanel({
    required this.items,
    required this.total,
    required this.onOpen,
  });

  final List<ExecutivePriorityItem> items;
  final int total;
  final ValueChanged<TgcgModule> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Executive priorities',
        trailing: TgcgStatusPill(
          label: '$total OPEN',
          color: total == 0 ? TgcgColors.success : TgcgColors.warning,
          compact: true,
        ),
        child: items.isEmpty
            ? const TgcgStatusPill(
                label: 'NO CURRENT EXECUTIVE PRIORITY',
                color: TgcgColors.success,
                icon: Icons.check_circle_outline_rounded,
              )
            : Column(
                children: [
                  for (final item in items)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onOpen(item.module),
                        borderRadius: BorderRadius.circular(TgcgRadius.sm),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _priorityColor(item.severity)
                                .withValues(alpha: .04),
                            borderRadius:
                                BorderRadius.circular(TgcgRadius.sm),
                            border: Border.all(
                              color: _priorityColor(item.severity)
                                  .withValues(alpha: .16),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.priority_high_rounded,
                                color: _priorityColor(item.severity),
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
                                      item.detail,
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

class _LgaPerformanceBoard extends StatelessWidget {
  const _LgaPerformanceBoard({
    required this.snapshots,
    required this.onOpenCoverage,
  });

  final List<CoverageAreaSnapshot> snapshots;
  final VoidCallback onOpenCoverage;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'LGA performance board',
        trailing: TextButton.icon(
          onPressed: onOpenCoverage,
          icon: const Icon(Icons.public_outlined),
          label: const Text('Open Coverage'),
        ),
        child: Column(
          children: [
            for (final item in snapshots)
              Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TgcgColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(TgcgRadius.sm),
                  border: Border.all(color: TgcgColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _coverageColor(item)
                                .withValues(alpha: .07),
                            borderRadius:
                                BorderRadius.circular(TgcgRadius.sm),
                          ),
                          child: Text(
                            item.readinessScore == null
                                ? '—'
                                : '${item.readinessScore}',
                            style: TextStyle(
                              color: _coverageColor(item),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.scope.lgaName ?? item.scope.label,
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TgcgStatusPill(
                          label: _coverageStateLabel(item.readinessState),
                          color: _coverageColor(item),
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        TgcgStatusPill(
                          label:
                              '${item.staffedPollingUnits}/${item.expectedPollingUnits} STAFF',
                          color: item.unstaffedPollingUnits == 0 &&
                                  item.expectedPollingUnits > 0
                              ? TgcgColors.success
                              : TgcgColors.warning,
                          compact: true,
                        ),
                        TgcgStatusPill(
                          label:
                              '${item.gpsActiveMembers}/${item.deployedMembers} GPS',
                          color: item.deployedMembers > 0 &&
                                  item.gpsActiveMembers ==
                                      item.deployedMembers
                              ? TgcgColors.success
                              : TgcgColors.warning,
                          compact: true,
                        ),
                        TgcgStatusPill(
                          label:
                              '${item.receivedResultPollingUnits} RESULT PUs',
                          color: TgcgColors.ai,
                          compact: true,
                        ),
                        if (item.openIncidents > 0)
                          TgcgStatusPill(
                            label: '${item.openIncidents} INCIDENTS',
                            color: TgcgColors.danger,
                            compact: true,
                          ),
                        if (item.conflictingResultPollingUnits > 0)
                          TgcgStatusPill(
                            label:
                                '${item.conflictingResultPollingUnits} CONFLICT',
                            color: TgcgColors.danger,
                            compact: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _ExecutivePackageCatalogue extends StatelessWidget {
  const _ExecutivePackageCatalogue({
    required this.packages,
    required this.selectedKind,
    required this.onSelect,
  });

  final List<_ExecutiveReportPackage> packages;
  final ReportKind selectedKind;
  final ValueChanged<ReportKind> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Executive report packages',
        child: Column(
          children: [
            for (final item in packages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: item.enabled ? () => onSelect(item.kind) : null,
                    borderRadius: BorderRadius.circular(TgcgRadius.sm),
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: item.kind == selectedKind
                            ? TgcgColors.primarySoft
                            : TgcgColors.surfaceRaised,
                        borderRadius:
                            BorderRadius.circular(TgcgRadius.sm),
                        border: Border.all(
                          color: item.kind == selectedKind
                              ? TgcgColors.primary.withValues(alpha: .24)
                              : TgcgColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.icon,
                            color: item.enabled
                                ? TgcgColors.primary
                                : TgcgColors.muted,
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
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  item.detail,
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
                            label: item.enabled ? 'READY' : 'LOCKED',
                            color: item.enabled
                                ? TgcgColors.success
                                : TgcgColors.muted,
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _ExecutivePackagePreview extends StatelessWidget {
  const _ExecutivePackagePreview({
    required this.package,
    required this.onExport,
  });

  final _ExecutiveReportPackage package;
  final ValueChanged<ExportFormat> onExport;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: package.title,
        trailing: TgcgStatusPill(
          label: '${package.recordCount} RECORDS',
          color: TgcgColors.info,
          compact: true,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in package.rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.$1,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                    Text(
                      row.$2,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final format in package.formats)
                  OutlinedButton.icon(
                    onPressed:
                        package.enabled ? () => onExport(format) : null,
                    icon: Icon(_formatIcon(format)),
                    label: Text(format.name.toUpperCase()),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const TgcgStatusPill(
              label: 'QUEUED EXPORT • BACKEND WORKER REQUIRED',
              color: TgcgColors.warning,
              icon: Icons.schedule_rounded,
              compact: true,
            ),
          ],
        ),
      );
}

class _ExecutiveJobHistory extends StatelessWidget {
  const _ExecutiveJobHistory({
    required this.jobs,
    required this.status,
    required this.onStatus,
    required this.onClear,
  });

  final List<ReportExportJob> jobs;
  final ExportJobStatus? status;
  final ValueChanged<ExportJobStatus?> onStatus;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Audited export queue',
        trailing: TgcgStatusPill(
          label: '${jobs.length} VISIBLE',
          color: TgcgColors.info,
          compact: true,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<ExportJobStatus?>(
                    initialValue: status,
                    decoration:
                        const InputDecoration(labelText: 'Job status'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All statuses'),
                      ),
                      for (final item in ExportJobStatus.values)
                        DropdownMenuItem(
                          value: item,
                          child: Text(_statusLabel(item)),
                        ),
                    ],
                    onChanged: onStatus,
                  ),
                ),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (jobs.isEmpty)
              const TgcgEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No export jobs in this view',
                message: 'Queue an executive report package above.',
              )
            else
              for (final job in jobs)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: TgcgColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(TgcgRadius.sm),
                    border: Border.all(color: TgcgColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _jobIcon(job.status),
                        color: _jobColor(job.status),
                        size: 19,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${job.id} • ${_reportKindLabel(job.kind)}',
                              style: const TextStyle(
                                color: TgcgColors.ink,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${job.format.name.toUpperCase()} • ${_time(job.requestedAt)}'
                              '${job.fileName == null ? '' : ' • ${job.fileName}'}',
                              style: const TextStyle(
                                color: TgcgColors.muted,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TgcgStatusPill(
                        label: _statusLabel(job.status).toUpperCase(),
                        color: _jobColor(job.status),
                        compact: true,
                      ),
                    ],
                  ),
                ),
          ],
        ),
      );
}

int _coverageSort(CoverageAreaSnapshot a, CoverageAreaSnapshot b) {
  final aPending =
      a.readinessState == CoverageReadinessState.cataloguePending;
  final bPending =
      b.readinessState == CoverageReadinessState.cataloguePending;
  if (aPending != bPending) return aPending ? 1 : -1;

  final score =
      (a.readinessScore ?? 101).compareTo(b.readinessScore ?? 101);
  if (score != 0) return score;
  return a.scope.label.compareTo(b.scope.label);
}

String _score(CoverageAreaSnapshot snapshot) =>
    snapshot.readinessScore == null ? 'PENDING' : '${snapshot.readinessScore}%';

TgcgMetricTone _coverageTone(CoverageAreaSnapshot snapshot) =>
    switch (snapshot.readinessState) {
      CoverageReadinessState.ready => TgcgMetricTone.success,
      CoverageReadinessState.watch => TgcgMetricTone.warning,
      CoverageReadinessState.critical => TgcgMetricTone.danger,
      CoverageReadinessState.cataloguePending => TgcgMetricTone.neutral,
    };

Color _coverageColor(CoverageAreaSnapshot snapshot) =>
    switch (snapshot.readinessState) {
      CoverageReadinessState.ready => TgcgColors.success,
      CoverageReadinessState.watch => TgcgColors.warning,
      CoverageReadinessState.critical => TgcgColors.danger,
      CoverageReadinessState.cataloguePending => TgcgColors.muted,
    };

String _coverageStateLabel(CoverageReadinessState state) => switch (state) {
      CoverageReadinessState.ready => 'READY',
      CoverageReadinessState.watch => 'WATCH',
      CoverageReadinessState.critical => 'CRITICAL',
      CoverageReadinessState.cataloguePending => 'CATALOGUE PENDING',
    };

Color _priorityColor(int severity) =>
    severity >= 4 ? TgcgColors.danger : TgcgColors.warning;

IconData _formatIcon(ExportFormat format) => switch (format) {
      ExportFormat.pdf => Icons.picture_as_pdf_outlined,
      ExportFormat.csv => Icons.table_chart_outlined,
      ExportFormat.json => Icons.data_object_rounded,
      ExportFormat.zip => Icons.folder_zip_outlined,
    };

String _reportKindLabel(ReportKind kind) => switch (kind) {
      ReportKind.executiveBrief => 'Executive Brief',
      ReportKind.incidentSummary => 'Incident Summary',
      ReportKind.fieldActivity => 'Field Activity',
      ReportKind.membershipDeployment => 'Membership & Deployment',
      ReportKind.verifiedCollation => 'Verified Result Accounting',
      ReportKind.evidencePackage => 'Evidence Package',
      ReportKind.auditTrail => 'Audit Trail',
      ReportKind.syncOutbox => 'Sync Outbox',
    };

String _statusLabel(ExportJobStatus status) => switch (status) {
      ExportJobStatus.queued => 'Queued',
      ExportJobStatus.generating => 'Generating',
      ExportJobStatus.completed => 'Completed',
      ExportJobStatus.failed => 'Failed',
    };

Color _jobColor(ExportJobStatus status) => switch (status) {
      ExportJobStatus.queued => TgcgColors.warning,
      ExportJobStatus.generating => TgcgColors.info,
      ExportJobStatus.completed => TgcgColors.success,
      ExportJobStatus.failed => TgcgColors.danger,
    };

IconData _jobIcon(ExportJobStatus status) => switch (status) {
      ExportJobStatus.queued => Icons.schedule_rounded,
      ExportJobStatus.generating => Icons.autorenew_rounded,
      ExportJobStatus.completed => Icons.task_alt_rounded,
      ExportJobStatus.failed => Icons.error_outline_rounded,
    };

String _time(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
