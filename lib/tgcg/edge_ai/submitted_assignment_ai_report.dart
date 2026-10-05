import 'package:flutter/material.dart';

import '../assignments/assignment_store.dart';
import '../domain/models.dart';
import '../membership/membership_store.dart';
import '../ui/tgcg_design.dart';
import 'assignment_edge_ai_store.dart';

enum SubmittedAiAssessment { verified, consistent, review, risk }

class SubmittedAiObservation {
  const SubmittedAiObservation({
    required this.label,
    required this.detail,
    required this.severity,
    this.confidence,
    this.evidenceReference,
  });

  final String label;
  final String detail;
  final AssignmentEdgeAiSeverity severity;
  final double? confidence;
  final String? evidenceReference;
}

class SubmittedAiMemberAssessment {
  const SubmittedAiMemberAssessment({
    required this.assignment,
    required this.score,
    required this.assessment,
    required this.observations,
    required this.aiEvents,
    required this.timeline,
  });

  final MemberAssignment assignment;
  final int score;
  final SubmittedAiAssessment assessment;
  final List<SubmittedAiObservation> observations;
  final List<AssignmentEdgeAiEvent> aiEvents;
  final List<AssignmentEvent> timeline;
}

class SubmittedAiReport {
  const SubmittedAiReport({
    required this.title,
    required this.generatedAt,
    required this.score,
    required this.assessment,
    required this.memberAssessments,
    required this.evidence,
    required this.isDemo,
  });

  final String title;
  final DateTime generatedAt;
  final int score;
  final SubmittedAiAssessment assessment;
  final List<SubmittedAiMemberAssessment> memberAssessments;
  final List<EvidenceAttachment> evidence;
  final bool isDemo;
}

Future<void> showSubmittedAssignmentAiReport(
  BuildContext context, {
  required MembershipOperationsController membership,
  required AssignmentController assignments,
  required AssignmentEdgeAiController edgeAi,
  MemberAssignment? assignment,
  GroupAssignment? group,
}) async {
  assert((assignment == null) != (group == null));
  final children = group == null
      ? [assignment!]
      : assignments.assignmentsForGroup(group.id);
  final report = buildSubmittedAiReport(
    children: children,
    title: group?.title ?? assignment!.title,
    assignments: assignments,
    edgeAi: edgeAi,
  );

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: TgcgColors.ai.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(TgcgRadius.md),
                    ),
                    child: const Icon(
                      Icons.psychology_alt_outlined,
                      color: TgcgColors.ai,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      report.title,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (report.isDemo)
                    const TgcgStatusPill(
                      label: 'DEMO AI REPORT',
                      color: TgcgColors.info,
                      compact: true,
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ReportSummary(report: report),
                    const SizedBox(height: 16),
                    _ReportSection(
                      title: 'AI assessment',
                      child: Column(
                        children: [
                          for (final member in report.memberAssessments)
                            _MemberAssessmentCard(
                              assessment: member,
                              membership: membership,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ReportSection(
                      title: 'Evidence',
                      child: report.evidence.isEmpty
                          ? const _EmptyReportState(
                              icon: Icons.inventory_2_outlined,
                              label: 'NO EVIDENCE',
                            )
                          : Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final item in report.evidence)
                                  _EvidenceCard(
                                    evidence: item,
                                    onTap: () => _showEvidenceDetails(
                                      dialogContext,
                                      item,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 16),
                    _ReportSection(
                      title: 'Assignment timeline',
                      child: Column(
                        children: [
                          for (final member in report.memberAssessments)
                            _TimelineCard(
                              assessment: member,
                              membership: membership,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

SubmittedAiReport buildSubmittedAiReport({
  required List<MemberAssignment> children,
  required String title,
  required AssignmentController assignments,
  required AssignmentEdgeAiController edgeAi,
}) {
  final memberReports = <SubmittedAiMemberAssessment>[];
  final evidence = <EvidenceAttachment>[];
  var demo = false;

  for (final assignment in children) {
    evidence.addAll(assignment.evidence);
    final completion = assignment.completedAt ?? assignment.assignedAt;
    final observations = <SubmittedAiObservation>[];
    var score = 100;

    final ping = assignment.lastLocation;
    if (ping == null) {
      if (assignment.locationMode == AssignmentLocationMode.none) {
        observations.add(
          const SubmittedAiObservation(
            label: 'Location-flexible duty',
            detail: 'No polling-unit geofence was required for this duty.',
            severity: AssignmentEdgeAiSeverity.info,
          ),
        );
        score -= 5;
      } else {
        observations.add(
          const SubmittedAiObservation(
            label: 'Completion GPS unavailable',
            detail: 'No final GPS fix is stored with this submission.',
            severity: AssignmentEdgeAiSeverity.warning,
          ),
        );
        score -= 22;
      }
    } else {
      final age = completion.difference(ping.capturedAt).abs();
      if (age <= const Duration(minutes: 15)) {
        observations.add(
          SubmittedAiObservation(
            label: 'Fresh completion GPS',
            detail:
                'Final location captured ${age.inMinutes} minute(s) from submission.',
            severity: AssignmentEdgeAiSeverity.info,
            confidence: .98,
          ),
        );
      } else {
        observations.add(
          SubmittedAiObservation(
            label: 'Older completion GPS',
            detail:
                'Last stored location was ${age.inMinutes} minutes from submission.',
            severity: AssignmentEdgeAiSeverity.warning,
          ),
        );
        score -= 10;
      }

      final distance = ping.distanceFromTargetMeters;
      if (assignment.locationMode == AssignmentLocationMode.pollingUnit &&
          distance != null) {
        if (distance <= 100) {
          observations.add(
            SubmittedAiObservation(
              label: 'Location corroborated',
              detail:
                  'Stored GPS was ${distance.toStringAsFixed(0)} m from the assigned polling-unit reference.',
              severity: AssignmentEdgeAiSeverity.info,
              confidence: .97,
            ),
          );
        } else if (distance <= 250) {
          observations.add(
            SubmittedAiObservation(
              label: 'Location requires review',
              detail:
                  'Stored GPS was ${distance.toStringAsFixed(0)} m from the target.',
              severity: AssignmentEdgeAiSeverity.warning,
            ),
          );
          score -= 8;
        } else {
          observations.add(
            SubmittedAiObservation(
              label: 'Location anomaly',
              detail:
                  'Stored GPS was ${distance.toStringAsFixed(0)} m from the target.',
              severity: AssignmentEdgeAiSeverity.critical,
            ),
          );
          score -= 24;
        }
      }
    }

    if (assignment.evidence.isEmpty) {
      observations.add(
        const SubmittedAiObservation(
          label: 'Evidence missing',
          detail: 'No media or document evidence is attached.',
          severity: AssignmentEdgeAiSeverity.critical,
        ),
      );
      score -= 25;
    } else {
      observations.add(
        SubmittedAiObservation(
          label: 'Evidence preserved',
          detail:
              '${assignment.evidence.length} evidence item(s) are attached to the submission.',
          severity: AssignmentEdgeAiSeverity.info,
          confidence: .99,
        ),
      );
    }

    if (assignment.requiredEvidence.isNotEmpty) {
      final available = assignment.evidence.map((item) => item.type).toSet();
      final missing =
          assignment.requiredEvidence.where((item) => !available.contains(item));
      final missingCount = missing.length;
      if (missingCount > 0) {
        observations.add(
          SubmittedAiObservation(
            label: 'Required evidence incomplete',
            detail: '${missingCount} required evidence type(s) are missing.',
            severity: AssignmentEdgeAiSeverity.warning,
          ),
        );
        score -= 10 * missingCount;
      }
    }

    final events = edgeAi.eventsForAssignment(assignment.id);
    for (final event in events) {
      score -= switch (event.severity) {
        AssignmentEdgeAiSeverity.info => 0,
        AssignmentEdgeAiSeverity.warning => 5,
        AssignmentEdgeAiSeverity.critical => 15,
      };
    }

    final demoObservations = _demoObservationsFor(assignment);
    if (demoObservations.isNotEmpty) {
      demo = true;
      observations.addAll(demoObservations);
    }

    final normalized = score.clamp(0, 100).toInt();
    memberReports.add(
      SubmittedAiMemberAssessment(
        assignment: assignment,
        score: normalized,
        assessment: _assessmentFor(normalized),
        observations: List.unmodifiable(observations),
        aiEvents: events,
        timeline: assignments.eventsForAssignment(assignment.id),
      ),
    );
  }

  final score = memberReports.isEmpty
      ? 0
      : memberReports.fold<int>(0, (total, item) => total + item.score) ~/
          memberReports.length;
  final generatedAt = children
      .map((item) => item.completedAt ?? item.assignedAt)
      .fold<DateTime>(
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        (latest, item) => item.isAfter(latest) ? item : latest,
      );

  return SubmittedAiReport(
    title: title,
    generatedAt: generatedAt,
    score: score,
    assessment: _assessmentFor(score),
    memberAssessments: List.unmodifiable(memberReports),
    evidence: List.unmodifiable(evidence),
    isDemo: demo,
  );
}

List<SubmittedAiObservation> _demoObservationsFor(
  MemberAssignment assignment,
) {
  switch (assignment.id) {
    case 'ASN-DEMO-0001':
      return const [
        SubmittedAiObservation(
          label: 'Image quality passed',
          detail: 'Opening and materials images are clear enough for review.',
          severity: AssignmentEdgeAiSeverity.info,
          confidence: .96,
          evidenceReference: 'EVD-DEMO-0001',
        ),
        SubmittedAiObservation(
          label: 'Scene consistency passed',
          detail: 'Captured images are visually consistent with one field visit.',
          severity: AssignmentEdgeAiSeverity.info,
          confidence: .92,
          evidenceReference: 'EVD-DEMO-0002',
        ),
      ];
    case 'ASN-DEMO-0002':
      return const [
        SubmittedAiObservation(
          label: 'Result form readable',
          detail: 'Form text and figures are sufficiently clear for review.',
          severity: AssignmentEdgeAiSeverity.info,
          confidence: .97,
          evidenceReference: 'EVD-DEMO-0003',
        ),
        SubmittedAiObservation(
          label: 'Posting evidence corroborated',
          detail: 'The result-posting image is consistent with the submitted form.',
          severity: AssignmentEdgeAiSeverity.info,
          confidence: .94,
          evidenceReference: 'EVD-DEMO-0004',
        ),
      ];
    case 'ASN-DEMO-0003':
      return const [
        SubmittedAiObservation(
          label: 'Document quality passed',
          detail: 'The mobilisation summary is legible and structurally complete.',
          severity: AssignmentEdgeAiSeverity.info,
          confidence: .93,
          evidenceReference: 'EVD-DEMO-0005',
        ),
      ];
    case 'ASN-DEMO-011':
    case 'ASN-DEMO-012':
    case 'ASN-DEMO-013':
      return [
        SubmittedAiObservation(
          label: 'Activity evidence consistent',
          detail:
              'Community sensitisation evidence is consistent with the assigned LGA activity.',
          severity: AssignmentEdgeAiSeverity.info,
          confidence: .91,
          evidenceReference: assignment.evidence.isEmpty
              ? null
              : assignment.evidence.first.id,
        ),
      ];
  }
  return const [];
}

class _ReportSummary extends StatelessWidget {
  const _ReportSummary({required this.report});

  final SubmittedAiReport report;

  @override
  Widget build(BuildContext context) {
    final color = _assessmentColor(report.assessment);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _SummaryMetric(
            label: 'AI SCORE',
            value: '${report.score}/100',
            color: color,
          ),
          TgcgStatusPill(
            label: _assessmentLabel(report.assessment),
            color: color,
            icon: Icons.verified_user_outlined,
          ),
          TgcgStatusPill(
            label: '${report.memberAssessments.length} MEMBER${report.memberAssessments.length == 1 ? '' : 'S'}',
            color: TgcgColors.info,
            icon: Icons.groups_outlined,
          ),
          TgcgStatusPill(
            label: '${report.evidence.length} EVIDENCE',
            color: TgcgColors.primary,
            icon: Icons.perm_media_outlined,
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class _MemberAssessmentCard extends StatelessWidget {
  const _MemberAssessmentCard({
    required this.assessment,
    required this.membership,
  });

  final SubmittedAiMemberAssessment assessment;
  final MembershipOperationsController membership;

  @override
  Widget build(BuildContext context) {
    final member = membership.memberById(assessment.assignment.memberId);
    final color = _assessmentColor(assessment.assessment);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  member?.fullName ?? assessment.assignment.memberId,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TgcgStatusPill(
                label: 'AI ${assessment.score}',
                color: color,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final observation in assessment.observations)
            _ObservationRow(observation: observation),
          if (assessment.aiEvents.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final event in assessment.aiEvents)
              _AiEventRow(event: event),
          ],
        ],
      ),
    );
  }
}

class _ObservationRow extends StatelessWidget {
  const _ObservationRow({required this.observation});

  final SubmittedAiObservation observation;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(observation.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_severityIcon(observation.severity), size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  observation.label,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  [
                    observation.detail,
                    if (observation.confidence != null)
                      '${(observation.confidence! * 100).round()}% confidence',
                  ].join(' • '),
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
    );
  }
}

class _AiEventRow extends StatelessWidget {
  const _AiEventRow({required this.event});

  final AssignmentEdgeAiEvent event;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            Icon(
              Icons.memory_rounded,
              size: 16,
              color: _severityColor(event.severity),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [
                  _eventLabel(event.type),
                  event.source,
                  if (event.confidence != null)
                    '${(event.confidence! * 100).round()}%',
                  if (event.summary != null) event.summary!,
                ].join(' • '),
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
      );
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({
    required this.evidence,
    required this.onTap,
  });

  final EvidenceAttachment evidence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 270,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(TgcgRadius.md),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TgcgColors.surfaceRaised,
                borderRadius: BorderRadius.circular(TgcgRadius.md),
                border: Border.all(color: TgcgColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: TgcgColors.primarySoft,
                      borderRadius: BorderRadius.circular(TgcgRadius.sm),
                    ),
                    child: Icon(
                      _evidenceIcon(evidence.type),
                      color: TgcgColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          evidence.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          evidence.caption ?? evidence.type.name.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.assessment,
    required this.membership,
  });

  final SubmittedAiMemberAssessment assessment;
  final MembershipOperationsController membership;

  @override
  Widget build(BuildContext context) {
    final member = membership.memberById(assessment.assignment.memberId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            member?.fullName ?? assessment.assignment.memberId,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          for (final event in assessment.timeline)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _shortTime(event.createdAt),
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '${_actionLabel(event.action)}${event.detail == null ? '' : ' • ${event.detail}'}',
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 10.5,
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
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: title,
        child: child,
      );
}

class _EmptyReportState extends StatelessWidget {
  const _EmptyReportState({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: TgcgStatusPill(
            label: label,
            color: TgcgColors.muted,
            icon: icon,
          ),
        ),
      );
}

Future<void> _showEvidenceDetails(
  BuildContext context,
  EvidenceAttachment evidence,
) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(evidence.fileName),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow('Type', evidence.type.name.toUpperCase()),
              _DetailRow('Captured', _fullTime(evidence.createdAt)),
              _DetailRow('Uploader', evidence.uploaderId),
              if (evidence.caption != null)
                _DetailRow('Caption', evidence.caption!),
              if (evidence.latitude != null && evidence.longitude != null)
                _DetailRow(
                  'GPS',
                  '${evidence.latitude!.toStringAsFixed(6)}, ${evidence.longitude!.toStringAsFixed(6)}',
                ),
              if (evidence.contentHash != null)
                _DetailRow('Integrity hash', evidence.contentHash!),
              if (evidence.mimeType != null)
                _DetailRow('Media type', evidence.mimeType!),
              if (evidence.sourceReference != null)
                _DetailRow('Reference', evidence.sourceReference!),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
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

SubmittedAiAssessment _assessmentFor(int score) => score >= 90
    ? SubmittedAiAssessment.verified
    : score >= 75
        ? SubmittedAiAssessment.consistent
        : score >= 60
            ? SubmittedAiAssessment.review
            : SubmittedAiAssessment.risk;

String _assessmentLabel(SubmittedAiAssessment assessment) =>
    switch (assessment) {
      SubmittedAiAssessment.verified => 'AI VERIFIED',
      SubmittedAiAssessment.consistent => 'AI CONSISTENT',
      SubmittedAiAssessment.review => 'REVIEW ADVISED',
      SubmittedAiAssessment.risk => 'AI RISK',
    };

Color _assessmentColor(SubmittedAiAssessment assessment) =>
    switch (assessment) {
      SubmittedAiAssessment.verified => TgcgColors.success,
      SubmittedAiAssessment.consistent => TgcgColors.info,
      SubmittedAiAssessment.review => TgcgColors.warning,
      SubmittedAiAssessment.risk => TgcgColors.danger,
    };

Color _severityColor(AssignmentEdgeAiSeverity severity) => switch (severity) {
      AssignmentEdgeAiSeverity.info => TgcgColors.info,
      AssignmentEdgeAiSeverity.warning => TgcgColors.warning,
      AssignmentEdgeAiSeverity.critical => TgcgColors.danger,
    };

IconData _severityIcon(AssignmentEdgeAiSeverity severity) =>
    switch (severity) {
      AssignmentEdgeAiSeverity.info => Icons.verified_outlined,
      AssignmentEdgeAiSeverity.warning => Icons.warning_amber_rounded,
      AssignmentEdgeAiSeverity.critical => Icons.crisis_alert_outlined,
    };

IconData _evidenceIcon(EvidenceType type) => switch (type) {
      EvidenceType.photo => Icons.photo_outlined,
      EvidenceType.video => Icons.videocam_outlined,
      EvidenceType.audio => Icons.mic_none_rounded,
      EvidenceType.document => Icons.description_outlined,
      EvidenceType.resultForm => Icons.fact_check_outlined,
      EvidenceType.location => Icons.location_on_outlined,
    };

String _eventLabel(AssignmentEdgeAiEventType type) => switch (type) {
      AssignmentEdgeAiEventType.gpsMissing => 'GPS missing',
      AssignmentEdgeAiEventType.gpsStale => 'GPS stale',
      AssignmentEdgeAiEventType.gpsOutsideTarget => 'Outside target',
      AssignmentEdgeAiEventType.gpsNoGeofence => 'No geofence',
      AssignmentEdgeAiEventType.deviceMissing => 'Device missing',
      AssignmentEdgeAiEventType.deviceStale => 'Device stale',
      AssignmentEdgeAiEventType.batteryLow => 'Battery low',
      AssignmentEdgeAiEventType.syncProblem => 'Sync issue',
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

String _actionLabel(String action) => action
    .split('_')
    .where((item) => item.isNotEmpty)
    .map((item) => '${item[0].toUpperCase()}${item.substring(1)}')
    .join(' ');

String _shortTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

String _fullTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}
