import 'package:flutter/material.dart';

import '../access/access_policy.dart';
import '../assignments/assignment_control_actions.dart';
import '../assignments/assignment_store.dart';
import '../devices/managed_device_store.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../membership/membership_store.dart';
import '../meeting/operational_call_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

class FieldAssignmentCallPanel extends StatelessWidget {
  const FieldAssignmentCallPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (session.role != TgcgRole.stateCoordinator) {
      return const SizedBox.shrink();
    }

    final assignments = Assignments.of(context);
    // Managed-device GPS can satisfy the active-GPS call requirement even
    // when an assignment heartbeat is not the freshest source.
    ManagedDevices.of(context);
    final membership = MembershipOperations.of(context);
    final calls = OperationalCalls.of(context);
    final stateScope = TgcgAccessPolicy.authorizingScope(
          context,
          TgcgCapability.viewIncidents,
        ) ??
        GeographicScope.kaduna;

    final groups = assignments.groupAssignments
        .where(
          (group) =>
              !group.isTerminal &&
              group.targetScopes.any(
                (scope) =>
                    TgcgPermissionPolicy.scopeAllows(stateScope, scope),
              ),
        )
        .toList(growable: false);

    final individuals = assignments
        .assignmentsForScope(stateScope)
        .where(
          (item) => !item.isTerminal && item.groupAssignmentId == null,
        )
        .toList(growable: false);

    return TgcgSectionCard(
      title: 'Live field communication',
      trailing: TgcgStatusPill(
        label: '${groups.length + individuals.length} ACTIVE',
        color: groups.isEmpty && individuals.isEmpty
            ? TgcgColors.muted
            : TgcgColors.success,
        icon: Icons.cell_tower_rounded,
        compact: true,
      ),
      child: groups.isEmpty && individuals.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.assignment_turned_in_outlined,
              title: 'No live field assignment',
              message: 'Active field work will appear here.',
            )
          : Column(
              children: [
                for (final group in groups)
                  _GroupFieldCallCard(
                    group: group,
                    assignments: assignments,
                    membership: membership,
                    calls: calls,
                    session: session,
                    stateScope: stateScope,
                  ),
                for (final assignment in individuals)
                  _IndividualFieldCallCard(
                    assignment: assignment,
                    membership: membership,
                    calls: calls,
                    session: session,
                    stateScope: stateScope,
                  ),
              ],
            ),
    );
  }
}

class _GroupFieldCallCard extends StatelessWidget {
  const _GroupFieldCallCard({
    required this.group,
    required this.assignments,
    required this.membership,
    required this.calls,
    required this.session,
    required this.stateScope,
  });

  final GroupAssignment group;
  final AssignmentController assignments;
  final MembershipOperationsController membership;
  final OperationalCallController calls;
  final TgcgSessionController session;
  final GeographicScope stateScope;

  @override
  Widget build(BuildContext context) {
    final children = assignments
        .assignmentsForGroup(group.id)
        .where((item) => !item.isTerminal)
        .toList(growable: false);
    final memberIds = children.map((item) => item.memberId).toList();
    final chairman = membership.memberById(group.chairmanMemberId);
    final chairmanAssignment = children
        .where((item) => item.memberId == group.chairmanMemberId)
        .firstOrNull;
    final gpsActive = memberIds
        .where(
          (memberId) => calls.gpsActiveForMember(
            memberId,
            groupAssignmentId: group.id,
          ),
        )
        .length;
    final allGps = memberIds.isNotEmpty && gpsActive == memberIds.length;
    final chairmanGps = calls.gpsActiveForMember(
      group.chairmanMemberId,
      assignmentId: chairmanAssignment?.id,
      groupAssignmentId: group.id,
    );

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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: TgcgColors.ai.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(TgcgRadius.sm),
                ),
                child: const Icon(
                  Icons.groups_2_outlined,
                  color: TgcgColors.ai,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      chairman == null
                          ? 'Chairman • ${group.chairmanMemberId}'
                          : 'Chairman • ${chairman.fullName}',
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              TgcgStatusPill(
                label: 'GPS $gpsActive/${memberIds.length}',
                color: allGps ? TgcgColors.success : TgcgColors.warning,
                icon: Icons.gps_fixed_rounded,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: chairman == null || !chairmanGps
                    ? null
                    : () => _callDirect(
                          context,
                          member: chairman,
                          assignmentId: chairmanAssignment?.id,
                          kind: OperationalCallKind.audio,
                        ),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: const Text('Chairman audio'),
              ),
              OutlinedButton.icon(
                onPressed: chairman == null || !chairmanGps
                    ? null
                    : () => _callDirect(
                          context,
                          member: chairman,
                          assignmentId: chairmanAssignment?.id,
                          kind: OperationalCallKind.video,
                        ),
                icon: const Icon(Icons.videocam_outlined, size: 18),
                label: const Text('Chairman video'),
              ),
              OutlinedButton.icon(
                onPressed: memberIds.isEmpty
                    ? null
                    : () => _showMemberCallDialog(
                          context,
                          children: children,
                        ),
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: const Text('Call member'),
              ),
              FilledButton.icon(
                onPressed: allGps
                    ? () => _callGroup(context, memberIds)
                    : null,
                icon: const Icon(Icons.video_call_outlined, size: 19),
                label: const Text('Conference all'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _callDirect(
    BuildContext context, {
    required TgcgMember member,
    required OperationalCallKind kind,
    String? assignmentId,
  }) async {
    try {
      await startStateCoordinatorMemberCall(
        context,
        calls: calls,
        session: session,
        stateScope: stateScope,
        member: member,
        kind: kind,
        assignmentId: assignmentId,
        groupAssignmentId: group.id,
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _callGroup(
    BuildContext context,
    List<String> memberIds,
  ) async {
    try {
      await startStateCoordinatorGroupCall(
        context,
        calls: calls,
        session: session,
        stateScope: stateScope,
        memberIds: memberIds,
        groupAssignmentId: group.id,
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _showMemberCallDialog(
    BuildContext context, {
    required List<MemberAssignment> children,
  }) async {
    final rows = children
        .map(
          (assignment) => (
            assignment: assignment,
            member: membership.memberById(assignment.memberId),
            gps: calls.gpsSnapshotForMember(
              assignment.memberId,
              assignmentId: assignment.id,
              groupAssignmentId: group.id,
            ),
          ),
        )
        .where((row) => row.member != null)
        .toList(growable: false);
    if (rows.isEmpty) return;

    var selectedId = rows
        .where((row) => row.gps != null)
        .map((row) => row.assignment.memberId)
        .firstOrNull;
    var kind = OperationalCallKind.video;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Call group member'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<OperationalCallKind>(
                  segments: const [
                    ButtonSegment(
                      value: OperationalCallKind.audio,
                      icon: Icon(Icons.call_outlined),
                      label: Text('Audio'),
                    ),
                    ButtonSegment(
                      value: OperationalCallKind.video,
                      icon: Icon(Icons.videocam_outlined),
                      label: Text('Video'),
                    ),
                  ],
                  selected: {kind},
                  onSelectionChanged: (values) =>
                      setDialogState(() => kind = values.first),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 310,
                  child: RadioGroup<String>(
                    groupValue: selectedId,
                    onChanged: (value) => setDialogState(() {
                      selectedId = value;
                    }),
                    child: ListView(
                      children: [
                        for (final row in rows)
                          RadioListTile<String>(
                            value: row.assignment.memberId,
                            enabled: row.gps != null,
                            title: Text(row.member!.fullName),
                            subtitle: Text(
                              row.gps == null
                                  ? 'GPS inactive'
                                  : 'GPS active • ${_gpsAge(row.gps!.capturedAt)}',
                            ),
                            secondary: Icon(
                              row.gps == null
                                  ? Icons.gps_off_rounded
                                  : Icons.gps_fixed_rounded,
                              color: row.gps == null
                                  ? TgcgColors.warning
                                  : TgcgColors.success,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: selectedId == null
                  ? null
                  : () => Navigator.pop(dialogContext, selectedId),
              icon: Icon(
                kind == OperationalCallKind.audio
                    ? Icons.call_rounded
                    : Icons.videocam_rounded,
              ),
              label: const Text('Call'),
            ),
          ],
        ),
      ),
    );

    if (selected == null || !context.mounted) return;
    final row = rows.firstWhere(
      (item) => item.assignment.memberId == selected,
    );
    await _callDirect(
      context,
      member: row.member!,
      assignmentId: row.assignment.id,
      kind: kind,
    );
  }
}

class _IndividualFieldCallCard extends StatelessWidget {
  const _IndividualFieldCallCard({
    required this.assignment,
    required this.membership,
    required this.calls,
    required this.session,
    required this.stateScope,
  });

  final MemberAssignment assignment;
  final MembershipOperationsController membership;
  final OperationalCallController calls;
  final TgcgSessionController session;
  final GeographicScope stateScope;

  @override
  Widget build(BuildContext context) {
    final member = membership.memberById(assignment.memberId);
    final gps = calls.gpsSnapshotForMember(
      assignment.memberId,
      assignmentId: assignment.id,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
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
            child: const Icon(
              Icons.person_pin_circle_outlined,
              color: TgcgColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member?.fullName ?? assignment.memberId,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${assignment.title} • ${assignment.targetScope.label}',
                  maxLines: 1,
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
          TgcgStatusPill(
            label: gps == null ? 'GPS INACTIVE' : 'GPS ACTIVE',
            color: gps == null ? TgcgColors.warning : TgcgColors.success,
            icon:
                gps == null ? Icons.gps_off_rounded : Icons.gps_fixed_rounded,
            compact: true,
          ),
          const SizedBox(width: 7),
          IconButton.filledTonal(
            tooltip: 'Audio call',
            onPressed: member == null || gps == null
                ? null
                : () => _call(
                      context,
                      member,
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
                      member,
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
    TgcgMember member,
    OperationalCallKind kind,
  ) async {
    try {
      await startStateCoordinatorMemberCall(
        context,
        calls: calls,
        session: session,
        stateScope: stateScope,
        member: member,
        kind: kind,
        assignmentId: assignment.id,
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }
}

String _gpsAge(DateTime capturedAt) {
  final age = DateTime.now().toUtc().difference(capturedAt.toUtc()).abs();
  if (age.inSeconds < 60) return '${age.inSeconds}s ago';
  return '${age.inMinutes}m ago';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
