import 'package:flutter/material.dart';

import '../assignments/assignment_store.dart';
import '../domain/models.dart';
import '../geography/geography_registry.dart';
import '../governance/governance_store.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'command_meeting_store.dart';
import 'operational_call_stage.dart';
import 'operational_call_store.dart';

class CommandMeetingAudience {
  const CommandMeetingAudience({
    required this.memberIds,
    required this.gpsReadyMemberIds,
  });

  final List<String> memberIds;
  final List<String> gpsReadyMemberIds;

  int get total => memberIds.length;
  int get gpsReady => gpsReadyMemberIds.length;
  int get gpsMissing => total - gpsReady;
  bool get allGpsReady => total > 0 && gpsReady == total;
}

CommandMeetingAudience resolveCommandMeetingAudience({
  required MembershipOperationsController membership,
  required GovernanceOperationsController governance,
  required OperationalCallController calls,
  required GeographicScope scope,
  TgcgRole? targetRole,
  List<String> groupMemberIds = const [],
}) {
  final groupFilter = groupMemberIds.toSet();
  final members = membership.members.where((member) {
    if (member.isBlocked) return false;

    final memberScope = membership.registrationScopeForMember(member.id);
    final scopeMatches = scope.level == GeographyLevel.state
        ? memberScope == null ||
            GeographyRegistry.scopeContains(scope, memberScope)
        : memberScope != null &&
            GeographyRegistry.scopeContains(scope, memberScope);
    if (!scopeMatches) return false;

    if (targetRole != null) {
      final hasRole = governance
          .activeRolesForMember(member.id)
          .any((item) => item.role == targetRole);
      if (!hasRole) return false;
    }

    if (groupFilter.isNotEmpty && !groupFilter.contains(member.id)) {
      return false;
    }
    return true;
  }).toList(growable: false);

  final ids = members.map((item) => item.id).toList(growable: false);
  final gps = ids
      .where((id) => calls.gpsActiveForMember(id))
      .toList(growable: false);
  return CommandMeetingAudience(
    memberIds: List.unmodifiable(ids),
    gpsReadyMemberIds: List.unmodifiable(gps),
  );
}

class StateCommandMeetingsPage extends StatefulWidget {
  const StateCommandMeetingsPage({
    super.key,
    required this.onOpenModule,
  });

  final ValueChanged<TgcgModule> onOpenModule;

  @override
  State<StateCommandMeetingsPage> createState() =>
      _StateCommandMeetingsPageState();
}

class _StateCommandMeetingsPageState extends State<StateCommandMeetingsPage> {
  final _title = TextEditingController();
  final _agenda = TextEditingController();
  GeographicScope _targetScope = GeographicScope.kaduna;
  TgcgRole? _targetRole;
  String? _groupId;
  DateTime _scheduledAt = DateTime.now().add(const Duration(minutes: 15));
  String? _selectedMeetingId;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _agenda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (session.role != TgcgRole.stateCoordinator) {
      return const Center(
        child: TgcgEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'State Command Meetings unavailable',
          message: 'State Coordinator authority is required.',
        ),
      );
    }

    final membership = MembershipOperations.of(context);
    final governance = GovernanceOperations.of(context);
    final assignments = Assignments.of(context);
    final calls = OperationalCalls.of(context);
    final meetings = CommandMeetings.of(context);

    final scopes = _meetingTargetScopes(membership);
    final matchingScope =
        scopes.where((item) => _sameScope(item, _targetScope));
    _targetScope =
        matchingScope.isEmpty ? scopes.first : matchingScope.first;

    final groups = assignments.groupAssignments
        .where((item) => !item.isTerminal)
        .toList(growable: false);
    if (_groupId != null && !groups.any((item) => item.id == _groupId)) {
      _groupId = null;
    }
    final selectedGroup = _groupId == null
        ? null
        : groups.where((item) => item.id == _groupId).firstOrNull;

    final audience = resolveCommandMeetingAudience(
      membership: membership,
      governance: governance,
      calls: calls,
      scope: _targetScope,
      targetRole: _targetRole,
      groupMemberIds: selectedGroup?.memberIds ?? const [],
    );

    final records = meetings.meetingsForScope(GeographicScope.kaduna);
    if (_selectedMeetingId == null ||
        !records.any((item) => item.id == _selectedMeetingId)) {
      _selectedMeetingId = records.isEmpty ? null : records.first.id;
    }
    final selected = _selectedMeetingId == null
        ? null
        : meetings.meetingById(_selectedMeetingId!);

    final live = records
        .where((item) => item.status == CommandMeetingStatus.live)
        .length;
    final scheduled = records
        .where((item) => item.status == CommandMeetingStatus.scheduled)
        .length;
    final completed = records
        .where((item) => item.status == CommandMeetingStatus.completed)
        .length;
    final openActions = records.fold<int>(
      0,
      (sum, item) => sum + item.openActionCount,
    );
    final noShows = records
        .where((item) => item.status == CommandMeetingStatus.completed)
        .fold<int>(0, (sum, item) => sum + item.noShowCount);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        const TgcgPageHeader(
          eyebrow: 'STATE COMMAND MEETINGS',
          title: 'State Command Meetings',
          subtitle:
              'Kaduna State • GPS-bound conferences, attendance and action tracking',
          trailing: TgcgStatusPill(
            label: 'STATE COORDINATOR',
            color: TgcgColors.primary,
            icon: Icons.video_camera_front_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _MeetingMetrics(
          live: live,
          scheduled: scheduled,
          completed: completed,
          openActions: openActions,
          noShows: noShows,
        ),
        const SizedBox(height: 16),
        _MeetingCommandActions(onOpen: widget.onOpenModule),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final composer = _MeetingComposer(
              title: _title,
              agenda: _agenda,
              scopes: scopes,
              groups: groups,
              targetScope: _targetScope,
              targetRole: _targetRole,
              groupId: _groupId,
              scheduledAt: _scheduledAt,
              audience: audience,
              busy: _busy,
              onScope: (value) => setState(() => _targetScope = value),
              onRole: (value) => setState(() => _targetRole = value),
              onGroup: (value) => setState(() => _groupId = value),
              onDateTime: _pickScheduledTime,
              onSchedule: audience.total == 0
                  ? null
                  : () => _scheduleMeeting(
                        meetings: meetings,
                        session: session,
                        audience: audience,
                        group: selectedGroup,
                      ),
            );
            final readiness = _AudienceReadinessPanel(
              audience: audience,
              membership: membership,
              calls: calls,
            );

            if (constraints.maxWidth < 1050) {
              return Column(
                children: [
                  composer,
                  const SizedBox(height: 14),
                  readiness,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: composer),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: readiness),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final register = _MeetingRegister(
              meetings: records,
              selectedMeetingId: _selectedMeetingId,
              onSelect: (id) => setState(() => _selectedMeetingId = id),
            );
            final detail = _MeetingDetailPanel(
              meeting: selected,
              membership: membership,
              calls: calls,
              busy: _busy,
              onStart: selected == null
                  ? null
                  : () => _startMeeting(
                        context,
                        meeting: selected,
                        meetings: meetings,
                        calls: calls,
                        session: session,
                      ),
              onOpenLive: selected == null
                  ? null
                  : () => _openLiveStage(context, selected, calls),
              onComplete: selected == null
                  ? null
                  : () => _completeMeeting(
                        selected,
                        meetings: meetings,
                        calls: calls,
                        session: session,
                      ),
              onCancel: selected == null
                  ? null
                  : () => _cancelMeeting(
                        selected,
                        meetings: meetings,
                        session: session,
                      ),
              onAddAction: selected == null
                  ? null
                  : () => _addActionItem(
                        context,
                        selected,
                        meetings: meetings,
                        membership: membership,
                        session: session,
                      ),
              onCompleteAction: selected == null
                  ? null
                  : (actionId) => _completeAction(
                        selected,
                        actionId,
                        meetings: meetings,
                        session: session,
                      ),
            );

            if (constraints.maxWidth < 1080) {
              return Column(
                children: [
                  register,
                  const SizedBox(height: 14),
                  detail,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: register),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: detail),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _pickScheduledTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _scheduleMeeting({
    required CommandMeetingController meetings,
    required TgcgSessionController session,
    required CommandMeetingAudience audience,
    required GroupAssignment? group,
  }) async {
    setState(() => _busy = true);
    try {
      final created = await meetings.scheduleMeeting(
        title: _title.text,
        agenda: _agenda.text,
        scope: _targetScope,
        inviteeMemberIds: audience.memberIds,
        createdBy:
            session.accessId.isEmpty ? session.operatorName : session.accessId,
        createdByRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
        scheduledAt: _scheduledAt,
        targetRoles: _targetRole == null ? const [] : [_targetRole!],
        groupAssignmentId: group?.id,
      );
      if (!mounted) return;
      _title.clear();
      _agenda.clear();
      setState(() => _selectedMeetingId = created.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${created.title} scheduled for ${created.inviteeMemberIds.length} invitee(s).',
          ),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startMeeting(
    BuildContext context, {
    required CommandMeeting meeting,
    required CommandMeetingController meetings,
    required OperationalCallController calls,
    required TgcgSessionController session,
  }) async {
    if (meeting.status != CommandMeetingStatus.scheduled) return;
    setState(() => _busy = true);
    try {
      final call = await calls.startConference(
        recipientMemberIds: meeting.inviteeMemberIds,
        callerId:
            session.accessId.isEmpty ? session.operatorName : session.accessId,
        callerName: session.operatorName,
        callerRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
        groupAssignmentId: meeting.groupAssignmentId,
      );
      await meetings.markLive(
        meetingId: meeting.id,
        operationalCallId: call.id,
        actorId:
            session.accessId.isEmpty ? session.operatorName : session.accessId,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OperationalCallStage(callId: call.id),
        ),
      );
      if (!mounted) return;
      await _syncAfterCall(
        meeting.id,
        meetings: meetings,
        calls: calls,
        session: session,
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLiveStage(
    BuildContext context,
    CommandMeeting meeting,
    OperationalCallController calls,
  ) async {
    final callId = meeting.operationalCallId;
    if (callId == null || calls.callById(callId) == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OperationalCallStage(callId: callId),
      ),
    );
    if (!mounted) return;
    final session = TgcgSession.of(context, listen: false);
    final meetings = CommandMeetings.of(context, listen: false);
    await _syncAfterCall(
      meeting.id,
      meetings: meetings,
      calls: calls,
      session: session,
    );
  }

  Future<void> _syncAfterCall(
    String meetingId, {
    required CommandMeetingController meetings,
    required OperationalCallController calls,
    required TgcgSessionController session,
  }) async {
    final meeting = meetings.meetingById(meetingId);
    if (meeting == null || meeting.operationalCallId == null) return;
    final call = calls.callById(meeting.operationalCallId!);
    if (call == null) return;
    await meetings.syncAttendance(
      meetingId: meeting.id,
      joinedMemberIds: call.joinedMemberIds,
      declinedMemberIds: call.declinedMemberIds,
    );
    if (!call.isOpen && meeting.status == CommandMeetingStatus.live) {
      await meetings.completeMeeting(
        meetingId: meeting.id,
        actorId:
            session.accessId.isEmpty ? session.operatorName : session.accessId,
        attendedMemberIds: call.joinedMemberIds,
        declinedMemberIds: call.declinedMemberIds,
      );
    }
  }

  Future<void> _completeMeeting(
    CommandMeeting meeting, {
    required CommandMeetingController meetings,
    required OperationalCallController calls,
    required TgcgSessionController session,
  }) async {
    setState(() => _busy = true);
    try {
      final actor =
          session.accessId.isEmpty ? session.operatorName : session.accessId;
      final call = meeting.operationalCallId == null
          ? null
          : calls.callById(meeting.operationalCallId!);
      if (call != null && call.isOpen) {
        await calls.endCall(callId: call.id, actorId: actor);
      }
      final latestCall = meeting.operationalCallId == null
          ? null
          : calls.callById(meeting.operationalCallId!);
      await meetings.completeMeeting(
        meetingId: meeting.id,
        actorId: actor,
        attendedMemberIds: latestCall?.joinedMemberIds ??
            meeting.attendedMemberIds,
        declinedMemberIds: latestCall?.declinedMemberIds ??
            meeting.declinedMemberIds,
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelMeeting(
    CommandMeeting meeting, {
    required CommandMeetingController meetings,
    required TgcgSessionController session,
  }) async {
    if (meeting.status == CommandMeetingStatus.live) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End the live conference before cancelling.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await meetings.cancelMeeting(
        meetingId: meeting.id,
        actorId:
            session.accessId.isEmpty ? session.operatorName : session.accessId,
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addActionItem(
    BuildContext context,
    CommandMeeting meeting, {
    required CommandMeetingController meetings,
    required MembershipOperationsController membership,
    required TgcgSessionController session,
  }) async {
    final title = TextEditingController();
    String? ownerId;
    DateTime? dueAt;
    final possibleOwners = meeting.inviteeMemberIds
        .map(membership.memberById)
        .whereType<TgcgMember>()
        .toList(growable: false);

    final create = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add meeting action'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration:
                      const InputDecoration(labelText: 'Action item'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: ownerId,
                  decoration: const InputDecoration(labelText: 'Owner'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    for (final member in possibleOwners)
                      DropdownMenuItem(
                        value: member.id,
                        child: Text(member.fullName),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => ownerId = value),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate:
                          dueAt ?? DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => dueAt = picked);
                    }
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    dueAt == null
                        ? 'Set due date'
                        : 'Due ${_dateLabel(dueAt!)}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Add action'),
            ),
          ],
        ),
      ),
    );

    if (create == true) {
      try {
        await meetings.addActionItem(
          meetingId: meeting.id,
          title: title.text,
          createdBy:
              session.accessId.isEmpty ? session.operatorName : session.accessId,
          ownerMemberId: ownerId,
          dueAt: dueAt,
        );
      } on StateError catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
    title.dispose();
  }

  Future<void> _completeAction(
    CommandMeeting meeting,
    String actionId, {
    required CommandMeetingController meetings,
    required TgcgSessionController session,
  }) async {
    await meetings.completeActionItem(
      meetingId: meeting.id,
      actionItemId: actionId,
      completedBy:
          session.accessId.isEmpty ? session.operatorName : session.accessId,
    );
  }
}

class _MeetingMetrics extends StatelessWidget {
  const _MeetingMetrics({
    required this.live,
    required this.scheduled,
    required this.completed,
    required this.openActions,
    required this.noShows,
  });

  final int live;
  final int scheduled;
  final int completed;
  final int openActions;
  final int noShows;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 980
              ? 5
              : constraints.maxWidth >= 620
                  ? 3
                  : constraints.maxWidth >= 420
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
                label: 'Live',
                value: '$live',
                detail: 'Command conferences',
                icon: Icons.fiber_manual_record_rounded,
                tone: live == 0
                    ? TgcgMetricTone.neutral
                    : TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Scheduled',
                value: '$scheduled',
                detail: 'Upcoming meetings',
                icon: Icons.calendar_month_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Completed',
                value: '$completed',
                detail: 'Attendance recorded',
                icon: Icons.task_alt_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Open actions',
                value: '$openActions',
                detail: 'Post-meeting follow-up',
                icon: Icons.checklist_rounded,
                tone: openActions == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'No-shows',
                value: '$noShows',
                detail: 'Completed meetings',
                icon: Icons.person_off_outlined,
                tone: noShows == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
            ],
          );
        },
      );
}

class _MeetingCommandActions extends StatelessWidget {
  const _MeetingCommandActions({required this.onOpen});
  final ValueChanged<TgcgModule> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Command workspaces',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.communications),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Communications Command'),
            ),
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
          ],
        ),
      );
}

class _MeetingComposer extends StatelessWidget {
  const _MeetingComposer({
    required this.title,
    required this.agenda,
    required this.scopes,
    required this.groups,
    required this.targetScope,
    required this.targetRole,
    required this.groupId,
    required this.scheduledAt,
    required this.audience,
    required this.busy,
    required this.onScope,
    required this.onRole,
    required this.onGroup,
    required this.onDateTime,
    required this.onSchedule,
  });

  final TextEditingController title;
  final TextEditingController agenda;
  final List<GeographicScope> scopes;
  final List<GroupAssignment> groups;
  final GeographicScope targetScope;
  final TgcgRole? targetRole;
  final String? groupId;
  final DateTime scheduledAt;
  final CommandMeetingAudience audience;
  final bool busy;
  final ValueChanged<GeographicScope> onScope;
  final ValueChanged<TgcgRole?> onRole;
  final ValueChanged<String?> onGroup;
  final VoidCallback onDateTime;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Schedule command meeting',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: title,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Meeting title'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<GeographicScope>(
              initialValue: targetScope,
              decoration:
                  const InputDecoration(labelText: 'Target geography'),
              items: [
                for (final scope in scopes)
                  DropdownMenuItem(
                    value: scope,
                    child: Text(_scopeLabel(scope)),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (value) {
                      if (value != null) onScope(value);
                    },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<TgcgRole?>(
              initialValue: targetRole,
              decoration: const InputDecoration(labelText: 'Role filter'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All roles'),
                ),
                for (final role in _meetingRoles)
                  DropdownMenuItem(
                    value: role,
                    child: Text(_roleLabel(role)),
                  ),
              ],
              onChanged: busy ? null : onRole,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: groupId,
              decoration:
                  const InputDecoration(labelText: 'Assignment group filter'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All members in audience'),
                ),
                for (final group in groups)
                  DropdownMenuItem(
                    value: group.id,
                    child: Text(group.title),
                  ),
              ],
              onChanged: busy ? null : onGroup,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : onDateTime,
              icon: const Icon(Icons.schedule_outlined),
              label: Text('${_dateLabel(scheduledAt)} • ${_timeLabel(scheduledAt)}'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: agenda,
              enabled: !busy,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Agenda'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : onSchedule,
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('Schedule meeting'),
            ),
          ],
        ),
      );
}

class _AudienceReadinessPanel extends StatelessWidget {
  const _AudienceReadinessPanel({
    required this.audience,
    required this.membership,
    required this.calls,
  });

  final CommandMeetingAudience audience;
  final MembershipOperationsController membership;
  final OperationalCallController calls;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Audience readiness',
        trailing: TgcgStatusPill(
          label: '${audience.gpsReady}/${audience.total} GPS',
          color:
              audience.allGpsReady ? TgcgColors.success : TgcgColors.warning,
          compact: true,
        ),
        child: audience.memberIds.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.group_off_outlined,
                title: 'No matching invitees',
                message: 'Change geography, role or group filter.',
              )
            : Column(
                children: [
                  for (final id in audience.memberIds.take(12))
                    _AudienceMemberRow(
                      name: membership.memberById(id)?.fullName ?? id,
                      gps: calls.gpsSnapshotForMember(id),
                    ),
                  if (audience.memberIds.length > 12)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+${audience.memberIds.length - 12} more invitee(s)',
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
      );
}

class _AudienceMemberRow extends StatelessWidget {
  const _AudienceMemberRow({
    required this.name,
    required this.gps,
  });

  final String name;
  final OperationalCallGpsSnapshot? gps;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceRaised,
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
              ),
            ),
            TgcgStatusPill(
              label: gps == null ? 'GPS INACTIVE' : 'GPS ACTIVE',
              color: gps == null ? TgcgColors.warning : TgcgColors.success,
              compact: true,
            ),
          ],
        ),
      );
}

class _MeetingRegister extends StatelessWidget {
  const _MeetingRegister({
    required this.meetings,
    required this.selectedMeetingId,
    required this.onSelect,
  });

  final List<CommandMeeting> meetings;
  final String? selectedMeetingId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Command meeting register',
        trailing: TgcgStatusPill(
          label: '${meetings.length} MEETINGS',
          color: TgcgColors.info,
          compact: true,
        ),
        child: meetings.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.video_camera_front_outlined,
                title: 'No command meetings',
                message: 'Schedule the first command meeting above.',
              )
            : Column(
                children: [
                  for (final meeting in meetings)
                    _MeetingRow(
                      meeting: meeting,
                      selected: meeting.id == selectedMeetingId,
                      onTap: () => onSelect(meeting.id),
                    ),
                ],
              ),
      );
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({
    required this.meeting,
    required this.selected,
    required this.onTap,
  });

  final CommandMeeting meeting;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _meetingStatusColor(meeting.status);
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
                  ? color.withValues(alpha: .05)
                  : TgcgColors.surfaceRaised,
              borderRadius: BorderRadius.circular(TgcgRadius.sm),
              border: Border.all(
                color: selected
                    ? color.withValues(alpha: .24)
                    : TgcgColors.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.video_camera_front_outlined, color: color),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meeting.title,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${meeting.scope.label} • ${_dateLabel(meeting.scheduledAt)} ${_timeLabel(meeting.scheduledAt)}',
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          TgcgStatusPill(
                            label: _meetingStatusLabel(meeting.status),
                            color: color,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label:
                                '${meeting.inviteeMemberIds.length} INVITED',
                            color: TgcgColors.info,
                            compact: true,
                          ),
                          if (meeting.status ==
                              CommandMeetingStatus.completed)
                            TgcgStatusPill(
                              label:
                                  '${meeting.attendedMemberIds.length} ATTENDED',
                              color: TgcgColors.success,
                              compact: true,
                            ),
                          if (meeting.openActionCount > 0)
                            TgcgStatusPill(
                              label:
                                  '${meeting.openActionCount} OPEN ACTIONS',
                              color: TgcgColors.warning,
                              compact: true,
                            ),
                        ],
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

class _MeetingDetailPanel extends StatelessWidget {
  const _MeetingDetailPanel({
    required this.meeting,
    required this.membership,
    required this.calls,
    required this.busy,
    required this.onStart,
    required this.onOpenLive,
    required this.onComplete,
    required this.onCancel,
    required this.onAddAction,
    required this.onCompleteAction,
  });

  final CommandMeeting? meeting;
  final MembershipOperationsController membership;
  final OperationalCallController calls;
  final bool busy;
  final VoidCallback? onStart;
  final VoidCallback? onOpenLive;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final VoidCallback? onAddAction;
  final ValueChanged<String>? onCompleteAction;

  @override
  Widget build(BuildContext context) {
    final item = meeting;
    if (item == null) {
      return const TgcgSectionCard(
        title: 'Meeting command',
        child: TgcgEmptyState(
          icon: Icons.video_camera_front_outlined,
          title: 'Select a meeting',
          message: 'Choose a command meeting from the register.',
        ),
      );
    }

    final call = item.operationalCallId == null
        ? null
        : calls.callById(item.operationalCallId!);
    final gpsReady = item.inviteeMemberIds
        .where((id) => calls.gpsActiveForMember(id))
        .length;
    final joined = call?.joinedMemberIds ?? item.attendedMemberIds;
    final declined = call?.declinedMemberIds ?? item.declinedMemberIds;
    final waiting = item.inviteeMemberIds
        .where((id) => !joined.contains(id) && !declined.contains(id))
        .toList(growable: false);

    return TgcgSectionCard(
      title: 'Meeting command',
      trailing: TgcgStatusPill(
        label: _meetingStatusLabel(item.status),
        color: _meetingStatusColor(item.status),
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.title,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (item.agenda != null) ...[
            const SizedBox(height: 5),
            Text(
              item.agenda!,
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 10.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _MeetingFact('Scope', item.scope.label),
          _MeetingFact(
            'Scheduled',
            '${_dateLabel(item.scheduledAt)} • ${_timeLabel(item.scheduledAt)}',
          ),
          _MeetingFact('Invitees', '${item.inviteeMemberIds.length}'),
          _MeetingFact('GPS ready', '$gpsReady/${item.inviteeMemberIds.length}'),
          if (item.groupAssignmentId != null)
            _MeetingFact('Group', item.groupAssignmentId!),
          if (item.operationalCallId != null)
            _MeetingFact('Call', item.operationalCallId!),
          if (item.status == CommandMeetingStatus.live ||
              item.status == CommandMeetingStatus.completed) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                TgcgStatusPill(
                  label: '${joined.length} JOINED',
                  color: TgcgColors.success,
                  compact: true,
                ),
                TgcgStatusPill(
                  label: '${declined.length} DECLINED',
                  color: TgcgColors.warning,
                  compact: true,
                ),
                TgcgStatusPill(
                  label: '${waiting.length} NO RESPONSE',
                  color: waiting.isEmpty
                      ? TgcgColors.muted
                      : TgcgColors.warning,
                  compact: true,
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          if (item.status == CommandMeetingStatus.scheduled) ...[
            FilledButton.icon(
              onPressed: busy ||
                      gpsReady != item.inviteeMemberIds.length
                  ? null
                  : onStart,
              icon: const Icon(Icons.video_call_rounded),
              label: const Text('Start GPS-bound conference'),
            ),
            const SizedBox(height: 7),
            OutlinedButton.icon(
              onPressed: busy ? null : onCancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel meeting'),
            ),
          ],
          if (item.status == CommandMeetingStatus.live) ...[
            FilledButton.icon(
              onPressed: busy ? null : onOpenLive,
              icon: const Icon(Icons.video_camera_front_rounded),
              label: const Text('Open live conference'),
            ),
            const SizedBox(height: 7),
            OutlinedButton.icon(
              onPressed: busy ? null : onComplete,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End & record attendance'),
            ),
          ],
          if (item.status == CommandMeetingStatus.completed) ...[
            const SizedBox(height: 4),
            _AttendanceList(
              title: 'Attended',
              ids: item.attendedMemberIds,
              membership: membership,
              color: TgcgColors.success,
            ),
            const SizedBox(height: 8),
            _AttendanceList(
              title: 'No-show',
              ids: item.inviteeMemberIds
                  .where(
                    (id) =>
                        !item.attendedMemberIds.contains(id) &&
                        !item.declinedMemberIds.contains(id),
                  )
                  .toList(growable: false),
              membership: membership,
              color: TgcgColors.warning,
            ),
          ],
          if (item.status == CommandMeetingStatus.live ||
              item.status == CommandMeetingStatus.completed) ...[
            const Divider(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'ACTION ITEMS',
                    style: TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy ? null : onAddAction,
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('Add action'),
                ),
              ],
            ),
            if (item.actionItems.isEmpty)
              const Text(
                'No action items recorded.',
                style: TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10,
                ),
              )
            else
              for (final action in item.actionItems)
                _ActionItemRow(
                  action: action,
                  ownerName: action.ownerMemberId == null
                      ? null
                      : membership
                          .memberById(action.ownerMemberId!)
                          ?.fullName,
                  onComplete:
                      action.status == MeetingActionStatus.open &&
                              onCompleteAction != null
                          ? () => onCompleteAction!(action.id)
                          : null,
                ),
          ],
        ],
      ),
    );
  }
}

class _AttendanceList extends StatelessWidget {
  const _AttendanceList({
    required this.title,
    required this.ids,
    required this.membership,
    required this.color,
  });

  final String title;
  final List<String> ids;
  final MembershipOperationsController membership;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          border: Border.all(color: color.withValues(alpha: .14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title • ${ids.length}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
            ),
            if (ids.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                ids
                    .map((id) => membership.memberById(id)?.fullName ?? id)
                    .join(', '),
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      );
}

class _ActionItemRow extends StatelessWidget {
  const _ActionItemRow({
    required this.action,
    required this.ownerName,
    required this.onComplete,
  });

  final MeetingActionItem action;
  final String? ownerName;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final completed = action.status == MeetingActionStatus.completed;
    return Container(
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TgcgRadius.sm),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Row(
        children: [
          Icon(
            completed
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: completed ? TgcgColors.success : TgcgColors.warning,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
                Text(
                  [
                    if (ownerName != null) ownerName!,
                    if (action.dueAt != null)
                      'Due ${_dateLabel(action.dueAt!)}',
                  ].join(' • '),
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          if (onComplete != null)
            IconButton(
              tooltip: 'Complete action',
              onPressed: onComplete,
              icon: const Icon(Icons.done_rounded),
            ),
        ],
      ),
    );
  }
}

class _MeetingFact extends StatelessWidget {
  const _MeetingFact(this.label, this.value);
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

List<GeographicScope> _meetingTargetScopes(
  MembershipOperationsController membership,
) {
  final scopes = <GeographicScope>[GeographicScope.kaduna];
  scopes.addAll(membership.geography.lgas.map((item) => item.scope));
  final wards = <String, GeographicScope>{};
  for (final unit in membership.geography.pollingUnits) {
    final wardId = unit.scope.wardId;
    if (wardId == null) continue;
    wards[wardId] = GeographicScope(
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
  scopes.addAll(wards.values);
  return List.unmodifiable(scopes);
}

const _meetingRoles = <TgcgRole>[
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
];

bool _sameScope(GeographicScope a, GeographicScope b) =>
    a.level == b.level &&
    a.stateId == b.stateId &&
    a.senatorialDistrictId == b.senatorialDistrictId &&
    a.lgaId == b.lgaId &&
    a.wardId == b.wardId &&
    a.pollingUnitId == b.pollingUnitId;

String _scopeLabel(GeographicScope scope) => switch (scope.level) {
      GeographyLevel.state => 'Kaduna State',
      GeographyLevel.lga => scope.lgaName ?? scope.label,
      GeographyLevel.ward =>
        '${scope.lgaName ?? 'LGA'} • ${scope.wardName ?? 'Ward'}',
      _ => scope.label,
    };

String _roleLabel(TgcgRole role) {
  final value = role.name.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return value.isEmpty
      ? value
      : '${value[0].toUpperCase()}${value.substring(1)}';
}

String _meetingStatusLabel(CommandMeetingStatus status) => switch (status) {
      CommandMeetingStatus.scheduled => 'SCHEDULED',
      CommandMeetingStatus.live => 'LIVE',
      CommandMeetingStatus.completed => 'COMPLETED',
      CommandMeetingStatus.cancelled => 'CANCELLED',
    };

Color _meetingStatusColor(CommandMeetingStatus status) => switch (status) {
      CommandMeetingStatus.scheduled => TgcgColors.info,
      CommandMeetingStatus.live => TgcgColors.danger,
      CommandMeetingStatus.completed => TgcgColors.success,
      CommandMeetingStatus.cancelled => TgcgColors.muted,
    };

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
