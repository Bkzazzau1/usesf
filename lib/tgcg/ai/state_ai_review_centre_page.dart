import 'package:flutter/material.dart';

import '../assignments/assignment_store.dart';
import '../edge_ai/assignment_edge_ai_store.dart';
import '../evidence/evidence_store.dart';
import '../field/field_operations_store.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

enum StateAiReviewSource {
  identity,
  assignment,
  evidence,
  result,
}

enum StateAiReviewSeverity {
  info,
  warning,
  critical,
}

class StateAiReviewCase {
  const StateAiReviewCase({
    required this.id,
    required this.source,
    required this.severity,
    required this.title,
    required this.detail,
    required this.scope,
    required this.createdAt,
    required this.referenceId,
    required this.targetModule,
    required this.notes,
    this.memberId,
    this.memberName,
    this.resolvableEventIds = const [],
  });

  final String id;
  final StateAiReviewSource source;
  final StateAiReviewSeverity severity;
  final String title;
  final String detail;
  final GeographicScope scope;
  final DateTime createdAt;
  final String referenceId;
  final TgcgModule targetModule;
  final List<String> notes;
  final String? memberId;
  final String? memberName;
  final List<String> resolvableEventIds;

  bool get canResolveAssignmentEvents => resolvableEventIds.isNotEmpty;
}

bool stateAiIdentityReady(TgcgMember member) =>
    member.identityReview == MemberIdentityReview.verified ||
    (member.origin == RecordOrigin.systemDerived &&
        member.status == RecordStatus.verified &&
        member.identityReview == MemberIdentityReview.pending);

List<StateAiReviewCase> buildStateAiReviewCases({
  required MembershipOperationsController membership,
  required AssignmentController assignments,
  required AssignmentEdgeAiController edgeAi,
  required EvidenceOperationsController directEvidence,
  required FieldOperationsController field,
  required ResultOperationsController results,
  DateTime? now,
}) {
  final cases = <StateAiReviewCase>[];
  final current = (now ?? DateTime.now()).toUtc();

  for (final member in membership.members) {
    if (stateAiIdentityReady(member) && !member.isBlocked) continue;

    final suspicious =
        member.identityReview == MemberIdentityReview.suspicious ||
        member.isBlocked;
    final scope =
        membership.registrationScopeForMember(member.id) ??
        GeographicScope.kaduna;
    final notes = <String>[
      if (member.identityReview == MemberIdentityReview.suspicious)
        'Identity was marked suspicious by human review.',
      if (member.identityReview == MemberIdentityReview.pending)
        'Identity review has not been completed.',
      if (member.isPendingActivation)
        'The member has not completed first-password activation.',
      if (member.isBlocked)
        'Operational access is blocked.',
      'Identity approval remains a backend/System Admin human-review action.',
    ];

    cases.add(
      StateAiReviewCase(
        id: 'IDENTITY-${member.id}',
        source: StateAiReviewSource.identity,
        severity: suspicious
            ? StateAiReviewSeverity.critical
            : StateAiReviewSeverity.warning,
        title: suspicious
            ? 'Identity requires urgent review'
            : 'Identity review pending',
        detail: member.fullName,
        scope: scope,
        createdAt: member.createdAt,
        referenceId: member.id,
        memberId: member.id,
        memberName: member.fullName,
        targetModule: TgcgModule.membershipNetwork,
        notes: List.unmodifiable(notes),
      ),
    );
  }

  for (final assignment in assignments.assignments) {
    if (assignment.isTerminal ||
        assignment.status == AssignmentStatus.reassigned) {
      continue;
    }

    final snapshot = edgeAi.snapshotFor(assignment, now: current);
    final operationalLifecycle = switch (assignment.status) {
      AssignmentStatus.accepted ||
      AssignmentStatus.enRoute ||
      AssignmentStatus.checkedIn ||
      AssignmentStatus.active ||
      AssignmentStatus.overdue ||
      AssignmentStatus.gpsMismatch => true,
      _ => false,
    };
    final significantFindings = operationalLifecycle
        ? snapshot.findings
            .where(
              (item) =>
                  item.severity == AssignmentEdgeAiSeverity.warning ||
                  item.severity == AssignmentEdgeAiSeverity.critical,
            )
            .toList(growable: false)
        : const <AssignmentEdgeAiFinding>[];
    final significantEvents = snapshot.openEvents
        .where(
          (item) =>
              item.severity == AssignmentEdgeAiSeverity.warning ||
              item.severity == AssignmentEdgeAiSeverity.critical,
        )
        .toList(growable: false);

    if (!operationalLifecycle && significantEvents.isEmpty) {
      continue;
    }
    if (snapshot.enabled &&
        significantFindings.isEmpty &&
        significantEvents.isEmpty &&
        snapshot.health == AssignmentEdgeAiHealth.healthy) {
      continue;
    }

    final critical = significantFindings.any(
          (item) => item.severity == AssignmentEdgeAiSeverity.critical,
        ) ||
        significantEvents.any(
          (item) => item.severity == AssignmentEdgeAiSeverity.critical,
        ) ||
        snapshot.health == AssignmentEdgeAiHealth.risk;

    final notes = <String>[
      if (!snapshot.enabled) 'Assignment Edge AI monitoring is disabled.',
      for (final finding in significantFindings) finding.label,
      for (final event in significantEvents)
        [
          _assignmentEventLabel(event.type),
          if (event.summary != null) event.summary!,
          if (event.confidence != null)
            '${(event.confidence! * 100).round()}% confidence',
        ].join(' • '),
    ];
    if (notes.isEmpty && snapshot.health == AssignmentEdgeAiHealth.offline) {
      notes.add('Assignment AI monitoring is offline.');
    }

    final latestEvent = significantEvents.isEmpty
        ? assignment.assignedAt
        : significantEvents
            .map((item) => item.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final member = membership.memberById(assignment.memberId);

    cases.add(
      StateAiReviewCase(
        id: 'ASSIGNMENT-${assignment.id}',
        source: StateAiReviewSource.assignment,
        severity: critical
            ? StateAiReviewSeverity.critical
            : StateAiReviewSeverity.warning,
        title: 'Assignment AI attention',
        detail:
            'AI ${snapshot.score}/100 • ${_assignmentHealthLabel(snapshot.health)} • ${assignment.title}',
        scope: assignment.targetScope,
        createdAt: latestEvent,
        referenceId: assignment.id,
        memberId: assignment.memberId,
        memberName: member?.fullName ?? assignment.memberId,
        targetModule: TgcgModule.assignmentControl,
        notes: List.unmodifiable(notes),
        resolvableEventIds: significantEvents
            .map((item) => item.id)
            .toList(growable: false),
      ),
    );
  }

  final evidenceRecords = _allEvidenceRecords(
    directEvidence: directEvidence,
    assignments: assignments,
    field: field,
    results: results,
  );
  for (final record in evidenceRecords) {
    final hash = record.evidence.contentHash?.trim() ?? '';
    if (hash.isNotEmpty) continue;

    final uploader = membership.memberById(record.evidence.uploaderId);
    cases.add(
      StateAiReviewCase(
        id: 'EVIDENCE-${record.evidence.id}',
        source: StateAiReviewSource.evidence,
        severity: StateAiReviewSeverity.critical,
        title: 'Evidence integrity review',
        detail: record.evidence.fileName,
        scope: record.scope,
        createdAt: record.evidence.createdAt,
        referenceId: record.evidence.id,
        memberId: record.evidence.uploaderId,
        memberName: uploader?.fullName ?? record.evidence.uploaderId,
        targetModule: TgcgModule.evidenceCapture,
        notes: const [
          'No cryptographic content hash is stored for this evidence record.',
          'Verify the source evidence before relying on it operationally.',
        ],
      ),
    );
  }

  final unresolvedResults = results.submissions
      .where(
        (item) =>
            item.status != RecordStatus.verified &&
            item.status != RecordStatus.rejected &&
            item.status != RecordStatus.archived,
      )
      .toList(growable: false);

  // Conflict candidates match Result Intelligence accounting: a verified
  // result still counts, so a later submission contradicting an already
  // verified result is flagged rather than silently ignored.
  final resultGroups = <String, List<ElectionResultSubmission>>{};
  for (final result in results.submissions) {
    if (result.status == RecordStatus.disputed ||
        result.status == RecordStatus.rejected ||
        result.status == RecordStatus.archived) {
      continue;
    }
    final key =
        result.pollingUnitScope.pollingUnitId ??
        result.pollingUnitScope.label;
    resultGroups.putIfAbsent(key, () => []).add(result);
  }

  final conflictKeys = <String>{};
  for (final entry in resultGroups.entries) {
    final active = entry.value;
    if (active.length <= 1) continue;
    conflictKeys.add(entry.key);
    active.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    final latest = active.first;
    cases.add(
      StateAiReviewCase(
        id: 'RESULT-CONFLICT-${entry.key}',
        source: StateAiReviewSource.result,
        severity: StateAiReviewSeverity.critical,
        title: 'Conflicting polling-unit results',
        detail:
            '${active.length} unresolved submissions • ${latest.pollingUnitScope.label}',
        scope: latest.pollingUnitScope,
        createdAt: latest.submittedAt,
        referenceId: entry.key,
        memberId: latest.submittedBy,
        memberName:
            membership.memberById(latest.submittedBy)?.fullName ??
            latest.submittedBy,
        targetModule: TgcgModule.resultCapture,
        notes: List.unmodifiable(
          active
              .map((item) => '${item.id} • ${item.status.name.toUpperCase()}')
              .toList(growable: false),
        ),
      ),
    );
  }

  for (final result in unresolvedResults) {
    final key =
        result.pollingUnitScope.pollingUnitId ??
        result.pollingUnitScope.label;
    if (conflictKeys.contains(key)) continue;

    final validation = result.validation;
    final requiresReview =
        result.status == RecordStatus.underReview ||
        result.status == RecordStatus.disputed ||
        validation?.requiresHumanReview == true;
    if (!requiresReview) continue;

    final critical = result.status == RecordStatus.disputed ||
        validation?.arithmeticValid == false ||
        validation?.duplicateSuspected == true ||
        validation?.pollingUnitMatched == false ||
        validation?.agentScopeMatched == false ||
        validation?.ocrMatchedManualEntry == false;

    final notes = <String>[
      if (result.status == RecordStatus.disputed)
        'This result is currently disputed.',
      if (validation?.arithmeticValid == false)
        'Arithmetic validation failed.',
      if (validation?.duplicateSuspected == true)
        'A duplicate submission is suspected.',
      if (validation?.pollingUnitMatched == false)
        'Polling-unit identity does not match canonical data.',
      if (validation?.agentScopeMatched == false)
        'Submitter scope does not match the polling unit.',
      if (validation?.formEvidencePresent == false)
        'Captured result-form evidence is missing.',
      if (validation?.ocrProcessed == false)
        'The result form has not been processed by OCR.',
      if (validation?.ocrMatchedManualEntry == false)
        'AI/OCR figures differ from submitted figures.',
      if (validation?.ocrConfidence != null &&
          validation!.ocrConfidence! < .85)
        'AI extraction score is below the automatic review threshold.',
      ...?validation?.notes,
    ];

    cases.add(
      StateAiReviewCase(
        id: 'RESULT-${result.id}',
        source: StateAiReviewSource.result,
        severity: critical
            ? StateAiReviewSeverity.critical
            : StateAiReviewSeverity.warning,
        title: result.status == RecordStatus.disputed
            ? 'Disputed result review'
            : 'Result AI review',
        detail: '${result.id} • ${result.pollingUnitScope.label}',
        scope: result.pollingUnitScope,
        createdAt: result.submittedAt,
        referenceId: result.id,
        memberId: result.submittedBy,
        memberName:
            membership.memberById(result.submittedBy)?.fullName ??
            result.submittedBy,
        targetModule: TgcgModule.resultCapture,
        notes: List.unmodifiable(
          notes.isEmpty
              ? const ['Human review is required by the result validation state.']
              : notes,
        ),
      ),
    );
  }

  cases.sort((a, b) {
    final severity =
        _severityOrder(a.severity).compareTo(_severityOrder(b.severity));
    if (severity != 0) return severity;
    return b.createdAt.compareTo(a.createdAt);
  });
  return List.unmodifiable(cases);
}

class StateAiReviewCentrePage extends StatefulWidget {
  const StateAiReviewCentrePage({
    super.key,
    required this.onOpenModule,
  });

  final ValueChanged<TgcgModule> onOpenModule;

  @override
  State<StateAiReviewCentrePage> createState() =>
      _StateAiReviewCentrePageState();
}

class _StateAiReviewCentrePageState extends State<StateAiReviewCentrePage> {
  final _search = TextEditingController();
  StateAiReviewSource? _source;
  StateAiReviewSeverity? _severity;
  String? _lgaId;
  String? _selectedCaseId;
  bool _resolving = false;

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
          title: 'State AI Review unavailable',
          message: 'State Coordinator authority is required.',
        ),
      );
    }

    final membership = MembershipOperations.of(context);
    final assignments = Assignments.of(context);
    final edgeAi = AssignmentEdgeAi.of(context);
    final directEvidence = EvidenceOperations.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);

    final cases = buildStateAiReviewCases(
      membership: membership,
      assignments: assignments,
      edgeAi: edgeAi,
      directEvidence: directEvidence,
      field: field,
      results: results,
    );

    final lgas = <String, String>{};
    for (final item in cases) {
      final id = item.scope.lgaId;
      final name = item.scope.lgaName;
      if (id != null && name != null) lgas[id] = name;
    }

    final query = _search.text.trim().toLowerCase();
    final visible = cases.where((item) {
      if (_source != null && item.source != _source) return false;
      if (_severity != null && item.severity != _severity) return false;
      if (_lgaId != null && item.scope.lgaId != _lgaId) return false;
      if (query.isEmpty) return true;
      return [
        item.title,
        item.detail,
        item.scope.label,
        item.referenceId,
        item.memberName,
        ...item.notes,
      ].whereType<String>().join(' ').toLowerCase().contains(query);
    }).toList(growable: false);

    if (_selectedCaseId == null ||
        !visible.any((item) => item.id == _selectedCaseId)) {
      _selectedCaseId = visible.isEmpty ? null : visible.first.id;
    }
    final selected = _selectedCaseId == null
        ? null
        : _firstWhereOrNull(
            cases,
            (item) => item.id == _selectedCaseId,
          );

    final critical = cases
        .where((item) => item.severity == StateAiReviewSeverity.critical)
        .length;
    final identity = cases
        .where((item) => item.source == StateAiReviewSource.identity)
        .length;
    final assignment = cases
        .where((item) => item.source == StateAiReviewSource.assignment)
        .length;
    final evidence = cases
        .where((item) => item.source == StateAiReviewSource.evidence)
        .length;
    final result = cases
        .where((item) => item.source == StateAiReviewSource.result)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        const TgcgPageHeader(
          eyebrow: 'STATE AI GOVERNANCE',
          title: 'State AI Review Centre',
          subtitle: 'Kaduna State • explainable AI-assisted human review',
          trailing: TgcgStatusPill(
            label: 'HUMAN AUTHORITY',
            color: TgcgColors.ai,
            icon: Icons.verified_user_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _ReviewMetrics(
          open: cases.length,
          critical: critical,
          identity: identity,
          assignment: assignment,
          evidence: evidence,
          result: result,
        ),
        const SizedBox(height: 16),
        _ReviewCommandActions(onOpen: widget.onOpenModule),
        const SizedBox(height: 16),
        _ReviewFilters(
          search: _search,
          source: _source,
          severity: _severity,
          lgaId: _lgaId,
          lgas: lgas,
          onSearch: (_) => setState(() {}),
          onSource: (value) => setState(() => _source = value),
          onSeverity: (value) => setState(() => _severity = value),
          onLga: (value) => setState(() => _lgaId = value),
          onClear: () {
            _search.clear();
            setState(() {
              _source = null;
              _severity = null;
              _lgaId = null;
            });
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final queue = _ReviewQueue(
              cases: visible,
              selectedCaseId: _selectedCaseId,
              onSelect: (id) => setState(() => _selectedCaseId = id),
            );
            final inspector = _ReviewInspector(
              reviewCase: selected,
              resolving: _resolving,
              onOpenSource: selected == null
                  ? null
                  : () => widget.onOpenModule(selected.targetModule),
              onResolve: selected?.canResolveAssignmentEvents == true
                  ? () => _resolveAssignmentEvents(
                        selected!,
                        edgeAi: edgeAi,
                        session: session,
                      )
                  : null,
            );

            if (constraints.maxWidth < 1060) {
              return Column(
                children: [
                  queue,
                  const SizedBox(height: 14),
                  inspector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: queue),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: inspector),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _resolveAssignmentEvents(
    StateAiReviewCase reviewCase, {
    required AssignmentEdgeAiController edgeAi,
    required TgcgSessionController session,
  }) async {
    if (_resolving || reviewCase.resolvableEventIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve assignment AI events'),
        content: Text(
          'Mark ${reviewCase.resolvableEventIds.length} durable AI event(s) as human-reviewed and resolved? Live GPS/device findings will remain until the underlying condition changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Resolve reviewed events'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resolving = true);
    try {
      final actor = session.accessId.isEmpty
          ? session.operatorName
          : session.accessId;
      for (final eventId in reviewCase.resolvableEventIds) {
        await edgeAi.resolveEvent(
          eventId: eventId,
          resolvedBy: actor,
          authorizedScope: GeographicScope.kaduna,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assignment AI event review recorded.'),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }
}

class _ReviewMetrics extends StatelessWidget {
  const _ReviewMetrics({
    required this.open,
    required this.critical,
    required this.identity,
    required this.assignment,
    required this.evidence,
    required this.result,
  });

  final int open;
  final int critical;
  final int identity;
  final int assignment;
  final int evidence;
  final int result;

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
                label: 'Open review',
                value: '$open',
                detail: 'Current queue',
                icon: Icons.fact_check_outlined,
                tone: open == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Critical',
                value: '$critical',
                detail: 'Highest priority',
                icon: Icons.crisis_alert_outlined,
                tone: critical == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Identity',
                value: '$identity',
                detail: 'Backend review visibility',
                icon: Icons.face_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Assignment AI',
                value: '$assignment',
                detail: 'Edge AI / telemetry',
                icon: Icons.memory_rounded,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Evidence',
                value: '$evidence',
                detail: 'Integrity exceptions',
                icon: Icons.perm_media_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Results',
                value: '$result',
                detail: 'OCR / validation review',
                icon: Icons.analytics_outlined,
                tone: TgcgMetricTone.ai,
              ),
            ],
          );
        },
      );
}

class _ReviewCommandActions extends StatelessWidget {
  const _ReviewCommandActions({required this.onOpen});

  final ValueChanged<TgcgModule> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Review workspaces',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.membershipNetwork),
              icon: const Icon(Icons.groups_2_outlined),
              label: const Text('Membership Intelligence'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.assignmentControl),
              icon: const Icon(Icons.assignment_ind_outlined),
              label: const Text('Assignment Control'),
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

class _ReviewFilters extends StatelessWidget {
  const _ReviewFilters({
    required this.search,
    required this.source,
    required this.severity,
    required this.lgaId,
    required this.lgas,
    required this.onSearch,
    required this.onSource,
    required this.onSeverity,
    required this.onLga,
    required this.onClear,
  });

  final TextEditingController search;
  final StateAiReviewSource? source;
  final StateAiReviewSeverity? severity;
  final String? lgaId;
  final Map<String, String> lgas;
  final ValueChanged<String> onSearch;
  final ValueChanged<StateAiReviewSource?> onSource;
  final ValueChanged<StateAiReviewSeverity?> onSeverity;
  final ValueChanged<String?> onLga;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final lgaEntries = lgas.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return TgcgSectionCard(
      title: 'Review filters',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 310,
            child: TextField(
              controller: search,
              onChanged: onSearch,
              decoration: const InputDecoration(
                labelText: 'Search review queue',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          SizedBox(
            width: 210,
            child: DropdownButtonFormField<StateAiReviewSource?>(
              initialValue: source,
              decoration: const InputDecoration(labelText: 'Source'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All sources'),
                ),
                for (final item in StateAiReviewSource.values)
                  DropdownMenuItem(
                    value: item,
                    child: Text(_sourceLabel(item)),
                  ),
              ],
              onChanged: onSource,
            ),
          ),
          SizedBox(
            width: 210,
            child: DropdownButtonFormField<StateAiReviewSeverity?>(
              initialValue: severity,
              decoration: const InputDecoration(labelText: 'Severity'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All severities'),
                ),
                for (final item in StateAiReviewSeverity.values)
                  DropdownMenuItem(
                    value: item,
                    child: Text(_severityLabel(item)),
                  ),
              ],
              onChanged: onSeverity,
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: lgaId,
              decoration: const InputDecoration(labelText: 'LGA'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All LGAs'),
                ),
                for (final entry in lgaEntries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: onLga,
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
}

class _ReviewQueue extends StatelessWidget {
  const _ReviewQueue({
    required this.cases,
    required this.selectedCaseId,
    required this.onSelect,
  });

  final List<StateAiReviewCase> cases;
  final String? selectedCaseId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Prioritized review queue',
        trailing: TgcgStatusPill(
          label: '${cases.length} OPEN',
          color: cases.isEmpty ? TgcgColors.success : TgcgColors.warning,
          compact: true,
        ),
        child: cases.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.verified_outlined,
                title: 'No open AI review cases',
                message: 'Current review sources have no unresolved exception.',
              )
            : Column(
                children: [
                  for (final item in cases)
                    _ReviewCaseRow(
                      reviewCase: item,
                      selected: item.id == selectedCaseId,
                      onTap: () => onSelect(item.id),
                    ),
                ],
              ),
      );
}

class _ReviewCaseRow extends StatelessWidget {
  const _ReviewCaseRow({
    required this.reviewCase,
    required this.selected,
    required this.onTap,
  });

  final StateAiReviewCase reviewCase;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(reviewCase.severity);
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
                  ? color.withValues(alpha: .055)
                  : TgcgColors.surfaceRaised,
              borderRadius: BorderRadius.circular(TgcgRadius.sm),
              border: Border.all(
                color: selected
                    ? color.withValues(alpha: .26)
                    : TgcgColors.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _sourceIcon(reviewCase.source),
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reviewCase.title,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reviewCase.detail,
                        maxLines: 2,
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
                            label: _sourceLabel(reviewCase.source)
                                .toUpperCase(),
                            color: TgcgColors.ai,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label: _severityLabel(reviewCase.severity)
                                .toUpperCase(),
                            color: color,
                            compact: true,
                          ),
                          if (reviewCase.memberName != null)
                            TgcgStatusPill(
                              label: reviewCase.memberName!,
                              color: TgcgColors.info,
                              compact: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
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

class _ReviewInspector extends StatelessWidget {
  const _ReviewInspector({
    required this.reviewCase,
    required this.resolving,
    required this.onOpenSource,
    required this.onResolve,
  });

  final StateAiReviewCase? reviewCase;
  final bool resolving;
  final VoidCallback? onOpenSource;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    final item = reviewCase;
    if (item == null) {
      return const TgcgSectionCard(
        title: 'Review detail',
        child: TgcgEmptyState(
          icon: Icons.fact_check_outlined,
          title: 'Select a review case',
          message: 'Choose an item from the prioritized queue.',
        ),
      );
    }

    final color = _severityColor(item.severity);
    return TgcgSectionCard(
      title: 'Review detail',
      trailing: TgcgStatusPill(
        label: _severityLabel(item.severity).toUpperCase(),
        color: color,
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(TgcgRadius.sm),
                ),
                child: Icon(_sourceIcon(item.source), color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.detail,
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _ReviewFact('Source', _sourceLabel(item.source)),
          _ReviewFact('Reference', item.referenceId),
          _ReviewFact('Scope', item.scope.label),
          if (item.memberName != null)
            _ReviewFact('Member', item.memberName!),
          _ReviewFact('Raised', _timeLabel(item.createdAt)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: TgcgColors.surfaceRaised,
              borderRadius: BorderRadius.circular(TgcgRadius.sm),
              border: Border.all(color: TgcgColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WHY THIS NEEDS REVIEW',
                  style: TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 8),
                for (final note in item.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 6,
                          color: color,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontSize: 10.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (item.source == StateAiReviewSource.identity) ...[
            const SizedBox(height: 12),
            const TgcgStatusPill(
              label: 'BACKEND IDENTITY APPROVAL ONLY',
              color: TgcgColors.warning,
              icon: Icons.admin_panel_settings_outlined,
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onOpenSource,
            icon: Icon(_targetIcon(item.targetModule)),
            label: Text(_targetLabel(item.targetModule)),
          ),
          if (onResolve != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: resolving ? null : onResolve,
              icon: resolving
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: Text(
                resolving
                    ? 'Recording review...'
                    : 'Resolve reviewed AI events',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewFact extends StatelessWidget {
  const _ReviewFact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 78,
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
}

class _EvidenceReviewRecord {
  const _EvidenceReviewRecord({
    required this.evidence,
    required this.scope,
  });

  final EvidenceAttachment evidence;
  final GeographicScope scope;
}

List<_EvidenceReviewRecord> _allEvidenceRecords({
  required EvidenceOperationsController directEvidence,
  required AssignmentController assignments,
  required FieldOperationsController field,
  required ResultOperationsController results,
}) {
  final byId = <String, _EvidenceReviewRecord>{};

  void add(EvidenceAttachment evidence, GeographicScope scope) {
    byId[evidence.id] = _EvidenceReviewRecord(
      evidence: evidence,
      scope: scope,
    );
  }

  for (final record in directEvidence.recordsForScope(GeographicScope.kaduna)) {
    add(record.evidence, record.scope);
  }
  for (final assignment in assignments.assignmentsForScope(
    GeographicScope.kaduna,
  )) {
    for (final evidence in assignment.evidence) {
      add(evidence, assignment.targetScope);
    }
  }
  for (final incident in field.incidentsForScope(GeographicScope.kaduna)) {
    for (final evidence in incident.evidence) {
      add(evidence, incident.scope);
    }
  }
  for (final report in field.reportsForScope(GeographicScope.kaduna)) {
    for (final evidence in report.evidence) {
      add(evidence, report.scope);
    }
  }
  for (final result in results.submissionsForScope(GeographicScope.kaduna)) {
    final evidence = result.resultForm;
    if (evidence != null) add(evidence, result.pollingUnitScope);
  }

  return byId.values.toList(growable: false);
}

T? _firstWhereOrNull<T>(
  Iterable<T> values,
  bool Function(T value) test,
) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

int _severityOrder(StateAiReviewSeverity severity) => switch (severity) {
      StateAiReviewSeverity.critical => 0,
      StateAiReviewSeverity.warning => 1,
      StateAiReviewSeverity.info => 2,
    };

String _sourceLabel(StateAiReviewSource source) => switch (source) {
      StateAiReviewSource.identity => 'Identity',
      StateAiReviewSource.assignment => 'Assignment AI',
      StateAiReviewSource.evidence => 'Evidence',
      StateAiReviewSource.result => 'Result AI',
    };

IconData _sourceIcon(StateAiReviewSource source) => switch (source) {
      StateAiReviewSource.identity => Icons.face_outlined,
      StateAiReviewSource.assignment => Icons.memory_rounded,
      StateAiReviewSource.evidence => Icons.perm_media_outlined,
      StateAiReviewSource.result => Icons.analytics_outlined,
    };

String _severityLabel(StateAiReviewSeverity severity) => switch (severity) {
      StateAiReviewSeverity.info => 'Info',
      StateAiReviewSeverity.warning => 'Warning',
      StateAiReviewSeverity.critical => 'Critical',
    };

Color _severityColor(StateAiReviewSeverity severity) => switch (severity) {
      StateAiReviewSeverity.info => TgcgColors.info,
      StateAiReviewSeverity.warning => TgcgColors.warning,
      StateAiReviewSeverity.critical => TgcgColors.danger,
    };

String _assignmentHealthLabel(AssignmentEdgeAiHealth health) =>
    switch (health) {
      AssignmentEdgeAiHealth.healthy => 'Healthy',
      AssignmentEdgeAiHealth.watch => 'Watch',
      AssignmentEdgeAiHealth.risk => 'Risk',
      AssignmentEdgeAiHealth.offline => 'Offline',
    };

String _assignmentEventLabel(AssignmentEdgeAiEventType type) => switch (type) {
      AssignmentEdgeAiEventType.gpsMissing => 'GPS missing',
      AssignmentEdgeAiEventType.gpsStale => 'GPS stale',
      AssignmentEdgeAiEventType.gpsOutsideTarget => 'GPS outside target',
      AssignmentEdgeAiEventType.gpsNoGeofence => 'No geofence',
      AssignmentEdgeAiEventType.deviceMissing => 'Managed device missing',
      AssignmentEdgeAiEventType.deviceStale => 'Device stale',
      AssignmentEdgeAiEventType.batteryLow => 'Low battery',
      AssignmentEdgeAiEventType.syncProblem => 'Sync problem',
      AssignmentEdgeAiEventType.identityCheck => 'Identity check',
      AssignmentEdgeAiEventType.imageQuality => 'Image quality',
      AssignmentEdgeAiEventType.videoVerification => 'Video verification',
      AssignmentEdgeAiEventType.audioEvent => 'Audio event',
      AssignmentEdgeAiEventType.crowdActivity => 'Crowd activity',
      AssignmentEdgeAiEventType.locationCorroboration =>
        'Location corroboration',
      AssignmentEdgeAiEventType.evidenceIntegrity => 'Evidence integrity',
      AssignmentEdgeAiEventType.system => 'System',
    };

String _targetLabel(TgcgModule module) => switch (module) {
      TgcgModule.membershipNetwork => 'Open Membership Intelligence',
      TgcgModule.assignmentControl => 'Open Assignment Control',
      TgcgModule.evidenceCapture => 'Open Evidence Intelligence',
      TgcgModule.resultCapture => 'Open Result Intelligence',
      _ => 'Open source workspace',
    };

IconData _targetIcon(TgcgModule module) => switch (module) {
      TgcgModule.membershipNetwork => Icons.groups_2_outlined,
      TgcgModule.assignmentControl => Icons.assignment_ind_outlined,
      TgcgModule.evidenceCapture => Icons.fact_check_outlined,
      TgcgModule.resultCapture => Icons.analytics_outlined,
      _ => Icons.open_in_new_rounded,
    };

String _timeLabel(DateTime value) {
  final utc = value.toUtc();
  return '${utc.day.toString().padLeft(2, '0')}/'
      '${utc.month.toString().padLeft(2, '0')}/'
      '${utc.year} '
      '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')} UTC';
}
