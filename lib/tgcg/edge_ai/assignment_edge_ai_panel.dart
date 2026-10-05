import 'package:flutter/material.dart';

import '../assignments/assignment_store.dart';
import '../ui/tgcg_design.dart';
import 'assignment_edge_ai_store.dart';

class AssignmentEdgeAiPill extends StatelessWidget {
  const AssignmentEdgeAiPill({
    super.key,
    required this.snapshot,
  });

  final AssignmentEdgeAiSnapshot snapshot;

  @override
  Widget build(BuildContext context) => TgcgStatusPill(
        label: snapshot.enabled ? 'AI ${snapshot.score}' : 'AI OFF',
        color: assignmentEdgeAiHealthColor(snapshot.health),
        icon: Icons.memory_rounded,
        compact: true,
      );
}

class GroupAssignmentEdgeAiPill extends StatelessWidget {
  const GroupAssignmentEdgeAiPill({
    super.key,
    required this.assignments,
    required this.edgeAi,
  });

  final List<MemberAssignment> assignments;
  final AssignmentEdgeAiController edgeAi;

  @override
  Widget build(BuildContext context) {
    if (assignments.isEmpty) {
      return const TgcgStatusPill(
        label: 'AI --',
        color: TgcgColors.muted,
        icon: Icons.memory_rounded,
        compact: true,
      );
    }
    final snapshots = assignments
        .where((item) => !item.isTerminal)
        .map(edgeAi.snapshotFor)
        .toList(growable: false);
    if (snapshots.isEmpty) {
      return const TgcgStatusPill(
        label: 'AI CLOSED',
        color: TgcgColors.muted,
        icon: Icons.memory_rounded,
        compact: true,
      );
    }
    final enabled = snapshots.where((item) => item.enabled).toList();
    if (enabled.isEmpty) {
      return const TgcgStatusPill(
        label: 'AI OFF',
        color: TgcgColors.muted,
        icon: Icons.memory_rounded,
        compact: true,
      );
    }
    final score =
        enabled.fold<int>(0, (total, item) => total + item.score) ~/
            enabled.length;
    final alerts = enabled.fold<int>(
      0,
      (total, item) => total + item.alertCount,
    );
    final health = score >= 80
        ? AssignmentEdgeAiHealth.healthy
        : score >= 60
            ? AssignmentEdgeAiHealth.watch
            : AssignmentEdgeAiHealth.risk;
    return TgcgStatusPill(
      label: alerts == 0 ? 'AI $score' : 'AI $score • $alerts',
      color: assignmentEdgeAiHealthColor(health),
      icon: Icons.memory_rounded,
      compact: true,
    );
  }
}

Future<bool> showAssignmentEdgeAiDialog(
  BuildContext context, {
  required MemberAssignment assignment,
  required AssignmentEdgeAiController edgeAi,
  required String actorId,
}) async {
  final profile = edgeAi.profileFor(assignment.id);
  var enabled = profile.enabled;
  var mode = profile.mode;
  final capabilities =
      Set<AssignmentEdgeAiCapability>.of(profile.capabilities);

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final snapshot = edgeAi.snapshotFor(assignment);
        final events = edgeAi.eventsForAssignment(assignment.id);

        return AlertDialog(
          title: const Text('Assignment Edge AI'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ScoreCard(snapshot: snapshot),
                      TgcgStatusPill(
                        label: _healthLabel(snapshot.health),
                        color: assignmentEdgeAiHealthColor(snapshot.health),
                        icon: Icons.shield_outlined,
                      ),
                      TgcgStatusPill(
                        label: mode.name.toUpperCase(),
                        color: TgcgColors.info,
                        icon: Icons.tune_rounded,
                      ),
                      TgcgStatusPill(
                        label: '${snapshot.alertCount} ALERTS',
                        color: snapshot.alertCount == 0
                            ? TgcgColors.success
                            : TgcgColors.warning,
                        icon: Icons.notification_important_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: enabled,
                    title: const Text(
                      'Edge monitoring',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    onChanged: (value) =>
                        setDialogState(() => enabled = value),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<AssignmentEdgeAiMode>(
                    segments: const [
                      ButtonSegment(
                        value: AssignmentEdgeAiMode.normal,
                        label: Text('Normal'),
                      ),
                      ButtonSegment(
                        value: AssignmentEdgeAiMode.verification,
                        label: Text('Verify'),
                      ),
                      ButtonSegment(
                        value: AssignmentEdgeAiMode.event,
                        label: Text('Event'),
                      ),
                      ButtonSegment(
                        value: AssignmentEdgeAiMode.emergency,
                        label: Text('Emergency'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: enabled
                        ? (values) =>
                            setDialogState(() => mode = values.first)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  const _Heading('Active detectors'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DetectorChip(
                        label: 'GPS integrity',
                        icon: Icons.gps_fixed_rounded,
                        selected: capabilities.contains(
                          AssignmentEdgeAiCapability.gpsIntegrity,
                        ),
                        enabled: enabled,
                        onChanged: (selected) => setDialogState(() {
                          _setCapability(
                            capabilities,
                            AssignmentEdgeAiCapability.gpsIntegrity,
                            selected,
                          );
                        }),
                      ),
                      _DetectorChip(
                        label: 'Device integrity',
                        icon: Icons.phonelink_lock_outlined,
                        selected: capabilities.contains(
                          AssignmentEdgeAiCapability.deviceIntegrity,
                        ),
                        enabled: enabled,
                        onChanged: (selected) => setDialogState(() {
                          _setCapability(
                            capabilities,
                            AssignmentEdgeAiCapability.deviceIntegrity,
                            selected,
                          );
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _Heading('Live findings'),
                  if (snapshot.findings.isEmpty)
                    const TgcgStatusPill(
                      label: 'NO ACTIVE FINDINGS',
                      color: TgcgColors.success,
                      icon: Icons.verified_outlined,
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: snapshot.findings
                          .map(
                            (finding) => TgcgStatusPill(
                              label: finding.label.toUpperCase(),
                              color: _severityColor(finding.severity),
                              icon: _severityIcon(finding.severity),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 16),
                  const _Heading('AI event ledger'),
                  if (events.isEmpty)
                    const TgcgStatusPill(
                      label: 'NO RECORDED AI EVENTS',
                      color: TgcgColors.muted,
                      icon: Icons.history_rounded,
                    )
                  else
                    ...events.take(10).map(
                          (event) => _EventRow(
                            event: event,
                            onResolve: !event.isOpen
                                ? null
                                : () async {
                                    await edgeAi.resolveEvent(
                                      eventId: event.id,
                                      resolvedBy: actorId,
                                    );
                                    if (dialogContext.mounted) {
                                      setDialogState(() {});
                                    }
                                  },
                          ),
                        ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await edgeAi.updateProfile(
                  assignmentId: assignment.id,
                  updatedBy: actorId,
                  enabled: enabled,
                  mode: mode,
                  capabilities: capabilities,
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );

  return saved == true;
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.snapshot});

  final AssignmentEdgeAiSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: assignmentEdgeAiHealthColor(snapshot.health)
              .withValues(alpha: .08),
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          border: Border.all(
            color: assignmentEdgeAiHealthColor(snapshot.health)
                .withValues(alpha: .28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_alt_outlined,
              size: 18,
              color: assignmentEdgeAiHealthColor(snapshot.health),
            ),
            const SizedBox(width: 7),
            Text(
              snapshot.enabled ? '${snapshot.score}/100' : '--',
              style: TextStyle(
                color: assignmentEdgeAiHealthColor(snapshot.health),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class _DetectorChip extends StatelessWidget {
  const _DetectorChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => FilterChip(
        selected: selected,
        onSelected: enabled ? onChanged : null,
        avatar: Icon(icon, size: 17),
        label: Text(label),
      );
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.onResolve,
  });

  final AssignmentEdgeAiEvent event;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) => Container(
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
              _severityIcon(event.severity),
              color: _severityColor(event.severity),
              size: 19,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _eventLabel(event.type),
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      event.source,
                      if (event.confidence != null)
                        '${(event.confidence! * 100).round()}%',
                      if (event.summary != null) event.summary!,
                    ].join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (event.isOpen)
              IconButton(
                tooltip: 'Resolve',
                onPressed: onResolve,
                icon: const Icon(Icons.check_circle_outline_rounded),
              )
            else
              const Icon(
                Icons.verified_rounded,
                color: TgcgColors.success,
                size: 19,
              ),
          ],
        ),
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: TgcgColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .8,
          ),
        ),
      );
}

void _setCapability(
  Set<AssignmentEdgeAiCapability> capabilities,
  AssignmentEdgeAiCapability capability,
  bool selected,
) {
  if (selected) {
    capabilities.add(capability);
  } else {
    capabilities.remove(capability);
  }
}

Color assignmentEdgeAiHealthColor(AssignmentEdgeAiHealth health) =>
    switch (health) {
      AssignmentEdgeAiHealth.healthy => TgcgColors.success,
      AssignmentEdgeAiHealth.watch => TgcgColors.warning,
      AssignmentEdgeAiHealth.risk => TgcgColors.danger,
      AssignmentEdgeAiHealth.offline => TgcgColors.muted,
    };

String _healthLabel(AssignmentEdgeAiHealth health) => switch (health) {
      AssignmentEdgeAiHealth.healthy => 'AI HEALTHY',
      AssignmentEdgeAiHealth.watch => 'AI WATCH',
      AssignmentEdgeAiHealth.risk => 'AI RISK',
      AssignmentEdgeAiHealth.offline => 'AI OFF',
    };

Color _severityColor(AssignmentEdgeAiSeverity severity) =>
    switch (severity) {
      AssignmentEdgeAiSeverity.info => TgcgColors.info,
      AssignmentEdgeAiSeverity.warning => TgcgColors.warning,
      AssignmentEdgeAiSeverity.critical => TgcgColors.danger,
    };

IconData _severityIcon(AssignmentEdgeAiSeverity severity) =>
    switch (severity) {
      AssignmentEdgeAiSeverity.info => Icons.info_outline_rounded,
      AssignmentEdgeAiSeverity.warning => Icons.warning_amber_rounded,
      AssignmentEdgeAiSeverity.critical => Icons.crisis_alert_rounded,
    };

String _eventLabel(AssignmentEdgeAiEventType type) => switch (type) {
      AssignmentEdgeAiEventType.gpsMissing => 'GPS missing',
      AssignmentEdgeAiEventType.gpsStale => 'GPS stale',
      AssignmentEdgeAiEventType.gpsOutsideTarget => 'Outside target',
      AssignmentEdgeAiEventType.gpsNoGeofence => 'No geofence',
      AssignmentEdgeAiEventType.deviceMissing => 'Managed device missing',
      AssignmentEdgeAiEventType.deviceStale => 'Device heartbeat stale',
      AssignmentEdgeAiEventType.batteryLow => 'Battery low',
      AssignmentEdgeAiEventType.syncProblem => 'Sync issue',
      AssignmentEdgeAiEventType.identityCheck => 'Identity verification',
      AssignmentEdgeAiEventType.imageQuality => 'Image verification',
      AssignmentEdgeAiEventType.videoVerification => 'Video verification',
      AssignmentEdgeAiEventType.audioEvent => 'Audio event',
      AssignmentEdgeAiEventType.crowdActivity => 'Crowd activity',
      AssignmentEdgeAiEventType.locationCorroboration =>
        'Location corroboration',
      AssignmentEdgeAiEventType.evidenceIntegrity => 'Evidence integrity',
      AssignmentEdgeAiEventType.system => 'System event',
    };
