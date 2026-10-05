import 'package:flutter/material.dart';

import '../access/access_policy.dart';
import '../assignments/assignment_store.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../edge_ai/assignment_edge_ai_store.dart';
import '../edge_ai/submitted_assignment_ai_report.dart';
import '../field/field_operations_store.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'evidence_store.dart';

enum EvidenceIntelligenceSource {
  directCapture,
  assignment,
  incident,
  fieldReport,
  result,
}

class EvidenceIntelligenceRecord {
  const EvidenceIntelligenceRecord({
    required this.evidence,
    required this.scope,
    required this.source,
    required this.referenceId,
    required this.referenceTitle,
    required this.aiEvents,
    this.assignment,
    this.group,
    this.incident,
    this.fieldReport,
    this.result,
    this.directReference,
  });

  final EvidenceAttachment evidence;
  final GeographicScope scope;
  final EvidenceIntelligenceSource source;
  final String referenceId;
  final String referenceTitle;
  final List<AssignmentEdgeAiEvent> aiEvents;
  final MemberAssignment? assignment;
  final GroupAssignment? group;
  final FieldIncident? incident;
  final FieldReport? fieldReport;
  final ElectionResultSubmission? result;
  final String? directReference;

  bool get hasGps =>
      evidence.latitude != null && evidence.longitude != null;

  bool get hasIntegrityHash =>
      evidence.contentHash != null && evidence.contentHash!.trim().isNotEmpty;

  bool get requiresReview =>
      aiEvents.any(
        (event) =>
            event.severity == AssignmentEdgeAiSeverity.warning ||
            event.severity == AssignmentEdgeAiSeverity.critical,
      ) ||
      result?.validation?.requiresHumanReview == true;

  String get lgaLabel => scope.lgaName ?? scope.stateName ?? scope.label;
}

List<EvidenceIntelligenceRecord> buildEvidenceIntelligenceRecords({
  required GeographicScope scope,
  required EvidenceOperationsController directEvidence,
  required AssignmentController assignments,
  required FieldOperationsController field,
  required ResultOperationsController results,
  required AssignmentEdgeAiController edgeAi,
}) {
  final records = <EvidenceIntelligenceRecord>[];

  for (final direct in directEvidence.recordsForScope(scope)) {
    records.add(
      EvidenceIntelligenceRecord(
        evidence: direct.evidence,
        scope: direct.scope,
        source: EvidenceIntelligenceSource.directCapture,
        referenceId: direct.evidence.id,
        referenceTitle: direct.reference ?? 'Direct evidence capture',
        directReference: direct.reference,
        aiEvents: const [],
      ),
    );
  }

  for (final assignment in assignments.assignmentsForScope(scope)) {
    final group = assignment.groupAssignmentId == null
        ? null
        : assignments.groupAssignmentById(assignment.groupAssignmentId!);
    final assignmentEvents = edgeAi.eventsForAssignment(assignment.id);
    for (final evidence in assignment.evidence) {
      final linkedEvents = assignmentEvents
          .where(
            (event) =>
                event.evidenceReference == evidence.id ||
                event.evidenceReference == evidence.sourceReference,
          )
          .toList(growable: false);
      records.add(
        EvidenceIntelligenceRecord(
          evidence: evidence,
          scope: assignment.targetScope,
          source: EvidenceIntelligenceSource.assignment,
          referenceId: assignment.id,
          referenceTitle: assignment.title,
          assignment: assignment,
          group: group,
          aiEvents: linkedEvents,
        ),
      );
    }
  }

  for (final incident in field.incidentsForScope(scope)) {
    for (final evidence in incident.evidence) {
      records.add(
        EvidenceIntelligenceRecord(
          evidence: evidence,
          scope: incident.scope,
          source: EvidenceIntelligenceSource.incident,
          referenceId: incident.id,
          referenceTitle: incident.title,
          incident: incident,
          aiEvents: const [],
        ),
      );
    }
  }

  for (final report in field.reportsForScope(scope)) {
    for (final evidence in report.evidence) {
      records.add(
        EvidenceIntelligenceRecord(
          evidence: evidence,
          scope: report.scope,
          source: EvidenceIntelligenceSource.fieldReport,
          referenceId: report.id,
          referenceTitle: report.category,
          fieldReport: report,
          aiEvents: const [],
        ),
      );
    }
  }

  for (final result in results.submissionsForScope(scope)) {
    final evidence = result.resultForm;
    if (evidence == null) continue;
    records.add(
      EvidenceIntelligenceRecord(
        evidence: evidence,
        scope: result.pollingUnitScope,
        source: EvidenceIntelligenceSource.result,
        referenceId: result.id,
        referenceTitle: 'Result form',
        result: result,
        aiEvents: const [],
      ),
    );
  }

  records.sort(
    (a, b) => b.evidence.createdAt.compareTo(a.evidence.createdAt),
  );
  return List.unmodifiable(records);
}

class EvidenceIntelligencePage extends StatefulWidget {
  const EvidenceIntelligencePage({super.key});

  @override
  State<EvidenceIntelligencePage> createState() =>
      _EvidenceIntelligencePageState();
}

class _EvidenceIntelligencePageState extends State<EvidenceIntelligencePage> {
  final _search = TextEditingController();
  EvidenceIntelligenceSource? _source;
  EvidenceType? _type;
  String? _lgaId;
  bool _reviewOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final assignments = Assignments.of(context);
    final edgeAi = AssignmentEdgeAi.of(context);
    final directEvidence = EvidenceOperations.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);
    final scope = TgcgAccessPolicy.authorizingScope(
          context,
          TgcgCapability.viewEvidence,
        ) ??
        session.scope;

    final records = buildEvidenceIntelligenceRecords(
      scope: scope,
      directEvidence: directEvidence,
      assignments: assignments,
      field: field,
      results: results,
      edgeAi: edgeAi,
    );

    final lgas = <String, String>{};
    for (final record in records) {
      final id = record.scope.lgaId;
      final name = record.scope.lgaName;
      if (id != null && name != null) lgas[id] = name;
    }

    final query = _search.text.trim().toLowerCase();
    final filtered = records.where((record) {
      if (_source != null && record.source != _source) return false;
      if (_type != null && record.evidence.type != _type) return false;
      if (_lgaId != null && record.scope.lgaId != _lgaId) return false;
      if (_reviewOnly && !record.requiresReview) return false;
      if (query.isEmpty) return true;
      final uploader =
          membership.memberById(record.evidence.uploaderId)?.fullName ??
              record.evidence.uploaderId;
      final haystack = [
        record.evidence.fileName,
        record.evidence.caption,
        uploader,
        record.referenceId,
        record.referenceTitle,
        record.scope.label,
        record.evidence.type.name,
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);

    final photos =
        records.where((item) => item.evidence.type == EvidenceType.photo).length;
    final videoAudio = records
        .where(
          (item) =>
              item.evidence.type == EvidenceType.video ||
              item.evidence.type == EvidenceType.audio,
        )
        .length;
    final gps = records.where((item) => item.hasGps).length;
    final hashed = records.where((item) => item.hasIntegrityHash).length;
    final review = records.where((item) => item.requiresReview).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'STATE EVIDENCE',
          title: 'Evidence Intelligence',
          subtitle: scope.label,
          trailing: TgcgStatusPill(
            label: scope.level == GeographyLevel.state
                ? 'STATEWIDE'
                : scope.level.name.toUpperCase(),
            color: TgcgColors.ai,
            icon: Icons.fact_check_outlined,
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
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
                  label: 'Evidence',
                  value: '${records.length}',
                  detail: 'All sources',
                  icon: Icons.inventory_2_outlined,
                  tone: TgcgMetricTone.neutral,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Photos',
                  value: '${photos}',
                  detail: 'Images',
                  icon: Icons.photo_outlined,
                  tone: TgcgMetricTone.info,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Video / Audio',
                  value: '${videoAudio}',
                  detail: 'Recorded media',
                  icon: Icons.video_camera_back_outlined,
                  tone: TgcgMetricTone.ai,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'AI review',
                  value: '${review}',
                  detail: 'Needs attention',
                  icon: Icons.psychology_alt_outlined,
                  tone: review == 0
                      ? TgcgMetricTone.success
                      : TgcgMetricTone.warning,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'GPS tagged',
                  value: '${gps}',
                  detail: 'Location evidence',
                  icon: Icons.gps_fixed_rounded,
                  tone: TgcgMetricTone.success,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Integrity',
                  value: '${hashed}',
                  detail: 'Hashed records',
                  icon: Icons.verified_user_outlined,
                  tone: TgcgMetricTone.success,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _EvidenceFilters(
          search: _search,
          source: _source,
          type: _type,
          lgaId: _lgaId,
          reviewOnly: _reviewOnly,
          lgas: lgas,
          onSearch: (_) => setState(() {}),
          onSource: (value) => setState(() => _source = value),
          onType: (value) => setState(() => _type = value),
          onLga: (value) => setState(() => _lgaId = value),
          onReviewOnly: (value) => setState(() => _reviewOnly = value),
          onClear: () {
            _search.clear();
            setState(() {
              _source = null;
              _type = null;
              _lgaId = null;
              _reviewOnly = false;
            });
          },
        ),
        const SizedBox(height: 14),
        TgcgSectionCard(
          title: 'Evidence register',
          trailing: TgcgStatusPill(
            label: '${filtered.length} RECORDS',
            color: filtered.isEmpty ? TgcgColors.muted : TgcgColors.primary,
            compact: true,
          ),
          child: filtered.isEmpty
              ? const TgcgEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matching evidence',
                  message: 'Change the current filters.',
                )
              : Column(
                  children: [
                    for (final record in filtered)
                      _EvidenceRegisterRow(
                        record: record,
                        uploaderName:
                            membership.memberById(record.evidence.uploaderId)
                                    ?.fullName ??
                                record.evidence.uploaderId,
                        onTap: () => _showEvidenceRecord(
                          context,
                          record: record,
                          membership: membership,
                          assignments: assignments,
                          edgeAi: edgeAi,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EvidenceFilters extends StatelessWidget {
  const _EvidenceFilters({
    required this.search,
    required this.source,
    required this.type,
    required this.lgaId,
    required this.reviewOnly,
    required this.lgas,
    required this.onSearch,
    required this.onSource,
    required this.onType,
    required this.onLga,
    required this.onReviewOnly,
    required this.onClear,
  });

  final TextEditingController search;
  final EvidenceIntelligenceSource? source;
  final EvidenceType? type;
  final String? lgaId;
  final bool reviewOnly;
  final Map<String, String> lgas;
  final ValueChanged<String> onSearch;
  final ValueChanged<EvidenceIntelligenceSource?> onSource;
  final ValueChanged<EvidenceType?> onType;
  final ValueChanged<String?> onLga;
  final ValueChanged<bool> onReviewOnly;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Filters',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 950
                ? (constraints.maxWidth - 30) / 4
                : constraints.maxWidth >= 600
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: width,
                  child: TextField(
                    controller: search,
                    onChanged: onSearch,
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<EvidenceIntelligenceSource?>(
                    initialValue: source,
                    decoration: const InputDecoration(
                      labelText: 'Source',
                      prefixIcon: Icon(Icons.hub_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All sources'),
                      ),
                      for (final item in EvidenceIntelligenceSource.values)
                        DropdownMenuItem(
                          value: item,
                          child: Text(_sourceLabel(item)),
                        ),
                    ],
                    onChanged: onSource,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<EvidenceType?>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      prefixIcon: Icon(Icons.perm_media_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All types'),
                      ),
                      for (final item in EvidenceType.values)
                        DropdownMenuItem(
                          value: item,
                          child: Text(_evidenceTypeLabel(item)),
                        ),
                    ],
                    onChanged: onType,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<String?>(
                    initialValue: lgaId,
                    decoration: const InputDecoration(
                      labelText: 'LGA',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All LGAs'),
                      ),
                      ...(() {
                        final entries = lgas.entries.toList()
                          ..sort((a, b) => a.value.compareTo(b.value));
                        return entries
                            .map(
                              (entry) => DropdownMenuItem<String?>(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            )
                            .toList(growable: false);
                      })(),
                    ],
                    onChanged: onLga,
                  ),
                ),
                FilterChip(
                  selected: reviewOnly,
                  onSelected: onReviewOnly,
                  avatar: const Icon(Icons.psychology_alt_outlined, size: 17),
                  label: const Text('AI review only'),
                ),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Clear'),
                ),
              ],
            );
          },
        ),
      );
}

class _EvidenceRegisterRow extends StatelessWidget {
  const _EvidenceRegisterRow({
    required this.record,
    required this.uploaderName,
    required this.onTap,
  });

  final EvidenceIntelligenceRecord record;
  final String uploaderName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _sourceColor(record.source).withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(TgcgRadius.sm),
                    ),
                    child: Icon(
                      _evidenceIcon(record.evidence.type),
                      color: _sourceColor(record.source),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.evidence.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${uploaderName} • ${record.referenceTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TgcgColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          record.scope.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TgcgColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            TgcgStatusPill(
                              label: _sourceLabel(record.source).toUpperCase(),
                              color: _sourceColor(record.source),
                              compact: true,
                            ),
                            TgcgStatusPill(
                              label: _evidenceTypeLabel(
                                record.evidence.type,
                              ).toUpperCase(),
                              color: TgcgColors.info,
                              compact: true,
                            ),
                            if (record.hasGps)
                              const TgcgStatusPill(
                                label: 'GPS',
                                color: TgcgColors.success,
                                icon: Icons.gps_fixed_rounded,
                                compact: true,
                              ),
                            if (record.hasIntegrityHash)
                              const TgcgStatusPill(
                                label: 'HASHED',
                                color: TgcgColors.success,
                                icon: Icons.verified_outlined,
                                compact: true,
                              ),
                            if (record.requiresReview)
                              const TgcgStatusPill(
                                label: 'AI REVIEW',
                                color: TgcgColors.warning,
                                icon: Icons.psychology_alt_outlined,
                                compact: true,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _shortDate(record.evidence.createdAt),
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: TgcgColors.muted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

Future<void> _showEvidenceRecord(
  BuildContext context, {
  required EvidenceIntelligenceRecord record,
  required MembershipOperationsController membership,
  required AssignmentController assignments,
  required AssignmentEdgeAiController edgeAi,
}) async {
  final uploader =
      membership.memberById(record.evidence.uploaderId)?.fullName ??
          record.evidence.uploaderId;
  final canOpenSubmission = record.assignment != null &&
      record.assignment!.status == AssignmentStatus.completed;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(record.evidence.fileName),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  TgcgStatusPill(
                    label: _sourceLabel(record.source).toUpperCase(),
                    color: _sourceColor(record.source),
                    compact: true,
                  ),
                  TgcgStatusPill(
                    label:
                        _evidenceTypeLabel(record.evidence.type).toUpperCase(),
                    color: TgcgColors.info,
                    compact: true,
                  ),
                  if (record.requiresReview)
                    const TgcgStatusPill(
                      label: 'REVIEW',
                      color: TgcgColors.warning,
                      compact: true,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _DetailRow('Uploader', uploader),
              _DetailRow('Reference', record.referenceId),
              _DetailRow('Context', record.referenceTitle),
              _DetailRow('Scope', record.scope.label),
              _DetailRow('Captured', _fullDate(record.evidence.createdAt)),
              if (record.evidence.caption != null)
                _DetailRow('Caption', record.evidence.caption!),
              if (record.evidence.latitude != null &&
                  record.evidence.longitude != null)
                _DetailRow(
                  'GPS',
                  '${record.evidence.latitude!.toStringAsFixed(6)}, ${record.evidence.longitude!.toStringAsFixed(6)}',
                ),
              if (record.evidence.contentHash != null)
                _DetailRow('Integrity hash', record.evidence.contentHash!),
              if (record.evidence.mimeType != null)
                _DetailRow('Media type', record.evidence.mimeType!),
              if (record.evidence.sourceReference != null)
                _DetailRow('Media reference', record.evidence.sourceReference!),
              if (record.directReference != null)
                _DetailRow('Capture reference', record.directReference!),
              if (record.assignment != null) ...[
                _DetailRow(
                  'Assignment',
                  '${record.assignment!.title} • ${record.assignment!.status.name.toUpperCase()}',
                ),
                if (record.group != null)
                  _DetailRow('Group', record.group!.title),
              ],
              if (record.incident != null) ...[
                _DetailRow('Incident', record.incident!.title),
                _DetailRow(
                  'Incident status',
                  record.incident!.status.name.toUpperCase(),
                ),
              ],
              if (record.fieldReport != null) ...[
                _DetailRow('Field report', record.fieldReport!.category),
                _DetailRow(
                  'Report status',
                  record.fieldReport!.status.name.toUpperCase(),
                ),
              ],
              if (record.result != null) ...[
                _DetailRow('Result', record.result!.id),
                _DetailRow(
                  'Result status',
                  record.result!.status.name.toUpperCase(),
                ),
                if (record.result!.validation?.ocrConfidence != null)
                  _DetailRow(
                    'OCR confidence',
                    '${(record.result!.validation!.ocrConfidence! * 100).round()}%',
                  ),
              ],
              if (record.aiEvents.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 4),
                for (final event in record.aiEvents)
                  _AiEventLine(event: event),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
        if (canOpenSubmission)
          FilledButton.icon(
            onPressed: () {
              final assignment = record.assignment!;
              final group = record.group;
              Navigator.pop(dialogContext);
              final submittedGroup =
                  group?.status == GroupAssignmentStatus.submitted
                      ? group
                      : null;
              showSubmittedAssignmentAiReport(
                context,
                membership: membership,
                assignments: assignments,
                edgeAi: edgeAi,
                assignment: submittedGroup == null ? assignment : null,
                group: submittedGroup,
              );
            },
            icon: const Icon(Icons.psychology_alt_outlined),
            label: const Text('AI report'),
          ),
      ],
    ),
  );
}

class _AiEventLine extends StatelessWidget {
  const _AiEventLine({required this.event});

  final AssignmentEdgeAiEvent event;

  @override
  Widget build(BuildContext context) {
    final color = switch (event.severity) {
      AssignmentEdgeAiSeverity.info => TgcgColors.info,
      AssignmentEdgeAiSeverity.warning => TgcgColors.warning,
      AssignmentEdgeAiSeverity.critical => TgcgColors.danger,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.memory_rounded, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                event.type.name,
                event.source,
                if (event.confidence != null)
                  '${(event.confidence! * 100).round()}%',
                if (event.summary != null) event.summary!,
              ].join(' • '),
              style: const TextStyle(
                color: TgcgColors.ink,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 125,
              child: Text(
                label,
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}

String _sourceLabel(EvidenceIntelligenceSource source) => switch (source) {
      EvidenceIntelligenceSource.directCapture => 'Direct capture',
      EvidenceIntelligenceSource.assignment => 'Assignment',
      EvidenceIntelligenceSource.incident => 'Incident',
      EvidenceIntelligenceSource.fieldReport => 'Field report',
      EvidenceIntelligenceSource.result => 'Result form',
    };

Color _sourceColor(EvidenceIntelligenceSource source) => switch (source) {
      EvidenceIntelligenceSource.directCapture => TgcgColors.primary,
      EvidenceIntelligenceSource.assignment => TgcgColors.ai,
      EvidenceIntelligenceSource.incident => TgcgColors.danger,
      EvidenceIntelligenceSource.fieldReport => TgcgColors.info,
      EvidenceIntelligenceSource.result => TgcgColors.success,
    };

String _evidenceTypeLabel(EvidenceType type) => switch (type) {
      EvidenceType.photo => 'Photo',
      EvidenceType.video => 'Video',
      EvidenceType.audio => 'Audio',
      EvidenceType.location => 'Location',
      EvidenceType.document => 'Document',
      EvidenceType.resultForm => 'Result form',
    };

IconData _evidenceIcon(EvidenceType type) => switch (type) {
      EvidenceType.photo => Icons.photo_outlined,
      EvidenceType.video => Icons.videocam_outlined,
      EvidenceType.audio => Icons.mic_none_rounded,
      EvidenceType.location => Icons.location_on_outlined,
      EvidenceType.document => Icons.description_outlined,
      EvidenceType.resultForm => Icons.fact_check_outlined,
    };

String _shortDate(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}

String _fullDate(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}
