import 'package:flutter/widgets.dart';

import '../domain/local_id.dart';
import '../domain/models.dart';
import '../geography/geography_registry.dart';
import '../governance/governance_store.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

enum CommandMeetingStatus { scheduled, live, completed, cancelled }

enum MeetingActionStatus { open, completed }

class MeetingActionItem {
  const MeetingActionItem({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.createdBy,
    required this.status,
    this.ownerMemberId,
    this.dueAt,
    this.completedAt,
    this.completedBy,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final String createdBy;
  final MeetingActionStatus status;
  final String? ownerMemberId;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String? completedBy;

  MeetingActionItem copyWith({
    MeetingActionStatus? status,
    DateTime? completedAt,
    String? completedBy,
  }) =>
      MeetingActionItem(
        id: id,
        title: title,
        createdAt: createdAt,
        createdBy: createdBy,
        status: status ?? this.status,
        ownerMemberId: ownerMemberId,
        dueAt: dueAt,
        completedAt: completedAt ?? this.completedAt,
        completedBy: completedBy ?? this.completedBy,
      );
}

class CommandMeeting {
  const CommandMeeting({
    required this.id,
    required this.title,
    required this.scope,
    required this.inviteeMemberIds,
    required this.createdBy,
    required this.createdAt,
    required this.scheduledAt,
    required this.status,
    this.agenda,
    this.targetRoles = const [],
    this.groupAssignmentId,
    this.operationalCallId,
    this.startedAt,
    this.endedAt,
    this.attendedMemberIds = const [],
    this.declinedMemberIds = const [],
    this.actionItems = const [],
  });

  final String id;
  final String title;
  final String? agenda;
  final GeographicScope scope;
  final List<TgcgRole> targetRoles;
  final String? groupAssignmentId;
  final List<String> inviteeMemberIds;
  final String createdBy;
  final DateTime createdAt;
  final DateTime scheduledAt;
  final CommandMeetingStatus status;
  final String? operationalCallId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<String> attendedMemberIds;
  final List<String> declinedMemberIds;
  final List<MeetingActionItem> actionItems;

  bool get isOpen =>
      status == CommandMeetingStatus.scheduled ||
      status == CommandMeetingStatus.live;

  int get noShowCount => inviteeMemberIds
      .where(
        (id) =>
            !attendedMemberIds.contains(id) &&
            !declinedMemberIds.contains(id),
      )
      .length;

  int get openActionCount =>
      actionItems.where((item) => item.status == MeetingActionStatus.open).length;

  CommandMeeting copyWith({
    CommandMeetingStatus? status,
    String? operationalCallId,
    DateTime? startedAt,
    DateTime? endedAt,
    List<String>? attendedMemberIds,
    List<String>? declinedMemberIds,
    List<MeetingActionItem>? actionItems,
  }) =>
      CommandMeeting(
        id: id,
        title: title,
        agenda: agenda,
        scope: scope,
        targetRoles: targetRoles,
        groupAssignmentId: groupAssignmentId,
        inviteeMemberIds: inviteeMemberIds,
        createdBy: createdBy,
        createdAt: createdAt,
        scheduledAt: scheduledAt,
        status: status ?? this.status,
        operationalCallId: operationalCallId ?? this.operationalCallId,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        attendedMemberIds: attendedMemberIds ?? this.attendedMemberIds,
        declinedMemberIds: declinedMemberIds ?? this.declinedMemberIds,
        actionItems: actionItems ?? this.actionItems,
      );
}

class CommandMeetingController extends ChangeNotifier {
  CommandMeetingController({
    required OfflinePersistenceController persistence,
    required GovernanceOperationsController governance,
    List<CommandMeeting> meetings = const [],
  })  : _persistence = persistence,
        _governance = governance,
        _meetings = List<CommandMeeting>.of(meetings);

  final OfflinePersistenceController _persistence;
  final GovernanceOperationsController _governance;
  final List<CommandMeeting> _meetings;

  List<CommandMeeting> get meetings => List.unmodifiable(_meetings);

  CommandMeeting? meetingById(String id) {
    for (final item in _meetings) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<CommandMeeting> meetingsForScope(GeographicScope scope) =>
      _meetings
          .where(
            (item) =>
                GeographyRegistry.scopeContains(scope, item.scope) ||
                GeographyRegistry.scopeContains(item.scope, scope),
          )
          .toList(growable: false)
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  Future<void> hydrateFromOffline() async {
    final rows = await _persistence.readEntities(
      entityType: 'command_meeting',
    );
    var changed = false;
    for (final row in rows) {
      final restored = _meetingFromJson(row);
      if (restored == null) continue;
      final index = _meetings.indexWhere((item) => item.id == restored.id);
      if (index < 0) {
        _meetings.add(restored);
      } else {
        _meetings[index] = restored;
      }
      changed = true;
    }
    if (changed) {
      _meetings.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
      notifyListeners();
    }
  }

  Future<CommandMeeting> scheduleMeeting({
    required String title,
    required GeographicScope scope,
    required List<String> inviteeMemberIds,
    required String createdBy,
    required TgcgRole createdByRole,
    required GeographicScope authorizedScope,
    required DateTime scheduledAt,
    String? agenda,
    List<TgcgRole> targetRoles = const [],
    String? groupAssignmentId,
  }) async {
    if (createdByRole != TgcgRole.stateCoordinator ||
        authorizedScope.level != GeographyLevel.state ||
        authorizedScope.stateId != GeographicScope.kaduna.stateId) {
      throw StateError(
        'Only the Kaduna State Coordinator can schedule State Command Meetings.',
      );
    }
    if (!GeographyRegistry.scopeContains(authorizedScope, scope)) {
      throw StateError('Meeting target is outside Kaduna State scope.');
    }

    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw StateError('Meeting title is required.');
    }
    final invitees = inviteeMemberIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (invitees.isEmpty) {
      throw StateError('Select at least one meeting invitee.');
    }

    final now = DateTime.now().toUtc();
    final meeting = CommandMeeting(
      id: newLocalId('MTG', now),
      title: normalizedTitle,
      agenda: _clean(agenda),
      scope: scope,
      targetRoles: List.unmodifiable(targetRoles.toSet()),
      groupAssignmentId: _clean(groupAssignmentId),
      inviteeMemberIds: List.unmodifiable(invitees),
      createdBy: createdBy,
      createdAt: now,
      scheduledAt: scheduledAt.toUtc(),
      status: CommandMeetingStatus.scheduled,
    );
    _meetings.insert(0, meeting);
    await _persist(meeting);
    _governance.recordAudit(
      actorId: createdBy,
      action: 'command_meeting_scheduled',
      entityType: 'command_meeting',
      entityId: meeting.id,
      detail:
          '${meeting.title} scheduled for ${meeting.inviteeMemberIds.length} invitee(s).',
      scope: scope,
    );
    notifyListeners();
    return meeting;
  }

  Future<CommandMeeting> markLive({
    required String meetingId,
    required String operationalCallId,
    required String actorId,
  }) async {
    final index = _index(meetingId);
    final current = _meetings[index];
    if (current.status != CommandMeetingStatus.scheduled) {
      throw StateError('Only a scheduled meeting can be started.');
    }
    final now = DateTime.now().toUtc();
    final updated = current.copyWith(
      status: CommandMeetingStatus.live,
      operationalCallId: operationalCallId,
      startedAt: now,
    );
    _meetings[index] = updated;
    await _persist(updated);
    _governance.recordAudit(
      actorId: actorId,
      action: 'command_meeting_started',
      entityType: 'command_meeting',
      entityId: updated.id,
      detail: 'Conference call $operationalCallId linked to meeting.',
      scope: updated.scope,
    );
    notifyListeners();
    return updated;
  }

  Future<CommandMeeting> syncAttendance({
    required String meetingId,
    required List<String> joinedMemberIds,
    required List<String> declinedMemberIds,
  }) async {
    final index = _index(meetingId);
    final current = _meetings[index];
    final invitees = current.inviteeMemberIds.toSet();
    final attended = joinedMemberIds
        .where(invitees.contains)
        .toSet()
        .toList(growable: false);
    final declined = declinedMemberIds
        .where(invitees.contains)
        .toSet()
        .toList(growable: false);
    final updated = current.copyWith(
      attendedMemberIds: List.unmodifiable(attended),
      declinedMemberIds: List.unmodifiable(declined),
    );
    _meetings[index] = updated;
    await _persist(updated);
    notifyListeners();
    return updated;
  }

  Future<CommandMeeting> completeMeeting({
    required String meetingId,
    required String actorId,
    required List<String> attendedMemberIds,
    required List<String> declinedMemberIds,
  }) async {
    final index = _index(meetingId);
    final current = _meetings[index];
    if (current.status == CommandMeetingStatus.cancelled ||
        current.status == CommandMeetingStatus.completed) {
      return current;
    }
    final invitees = current.inviteeMemberIds.toSet();
    final now = DateTime.now().toUtc();
    final updated = current.copyWith(
      status: CommandMeetingStatus.completed,
      endedAt: now,
      attendedMemberIds: attendedMemberIds
          .where(invitees.contains)
          .toSet()
          .toList(growable: false),
      declinedMemberIds: declinedMemberIds
          .where(invitees.contains)
          .toSet()
          .toList(growable: false),
    );
    _meetings[index] = updated;
    await _persist(updated);
    _governance.recordAudit(
      actorId: actorId,
      action: 'command_meeting_completed',
      entityType: 'command_meeting',
      entityId: updated.id,
      detail:
          '${updated.attendedMemberIds.length}/${updated.inviteeMemberIds.length} invitees attended; ${updated.noShowCount} no-show.',
      scope: updated.scope,
    );
    notifyListeners();
    return updated;
  }

  Future<CommandMeeting> cancelMeeting({
    required String meetingId,
    required String actorId,
  }) async {
    final index = _index(meetingId);
    final current = _meetings[index];
    if (current.status == CommandMeetingStatus.completed) {
      throw StateError('Completed meetings cannot be cancelled.');
    }
    if (current.status == CommandMeetingStatus.cancelled) return current;
    final updated = current.copyWith(
      status: CommandMeetingStatus.cancelled,
      endedAt: DateTime.now().toUtc(),
    );
    _meetings[index] = updated;
    await _persist(updated);
    _governance.recordAudit(
      actorId: actorId,
      action: 'command_meeting_cancelled',
      entityType: 'command_meeting',
      entityId: updated.id,
      scope: updated.scope,
    );
    notifyListeners();
    return updated;
  }

  Future<CommandMeeting> addActionItem({
    required String meetingId,
    required String title,
    required String createdBy,
    String? ownerMemberId,
    DateTime? dueAt,
  }) async {
    final index = _index(meetingId);
    final current = _meetings[index];
    if (current.status != CommandMeetingStatus.completed &&
        current.status != CommandMeetingStatus.live) {
      throw StateError(
        'Action items can be added only to live or completed meetings.',
      );
    }
    final normalized = title.trim();
    if (normalized.isEmpty) {
      throw StateError('Action item title is required.');
    }
    final now = DateTime.now().toUtc();
    final action = MeetingActionItem(
      id: newLocalId('MTG-ACT', now),
      title: normalized,
      createdAt: now,
      createdBy: createdBy,
      status: MeetingActionStatus.open,
      ownerMemberId: _clean(ownerMemberId),
      dueAt: dueAt?.toUtc(),
    );
    final updated = current.copyWith(
      actionItems: List.unmodifiable([...current.actionItems, action]),
    );
    _meetings[index] = updated;
    await _persist(updated);
    _governance.recordAudit(
      actorId: createdBy,
      action: 'meeting_action_created',
      entityType: 'command_meeting',
      entityId: current.id,
      detail: action.title,
      scope: current.scope,
    );
    notifyListeners();
    return updated;
  }

  Future<CommandMeeting> completeActionItem({
    required String meetingId,
    required String actionItemId,
    required String completedBy,
  }) async {
    final index = _index(meetingId);
    final current = _meetings[index];
    final actionIndex =
        current.actionItems.indexWhere((item) => item.id == actionItemId);
    if (actionIndex < 0) {
      throw ArgumentError('Unknown meeting action item: $actionItemId');
    }
    final actions = List<MeetingActionItem>.of(current.actionItems);
    final action = actions[actionIndex];
    if (action.status == MeetingActionStatus.completed) return current;
    actions[actionIndex] = action.copyWith(
      status: MeetingActionStatus.completed,
      completedAt: DateTime.now().toUtc(),
      completedBy: completedBy,
    );
    final updated =
        current.copyWith(actionItems: List.unmodifiable(actions));
    _meetings[index] = updated;
    await _persist(updated);
    _governance.recordAudit(
      actorId: completedBy,
      action: 'meeting_action_completed',
      entityType: 'command_meeting',
      entityId: current.id,
      detail: action.title,
      scope: current.scope,
    );
    notifyListeners();
    return updated;
  }

  int _index(String meetingId) {
    final index = _meetings.indexWhere((item) => item.id == meetingId);
    if (index < 0) throw ArgumentError('Unknown meeting: $meetingId');
    return index;
  }

  Future<void> _persist(CommandMeeting meeting) =>
      _persistence.persistMutation(
        entityType: 'command_meeting',
        entityId: meeting.id,
        mutationType: SyncMutationType.upsert,
        scopeKey: scopeStorageKey(meeting.scope),
        ownerId: meeting.createdBy,
        payload: _meetingToJson(meeting),
      );
}

Map<String, Object?> _meetingToJson(CommandMeeting meeting) => {
      'id': meeting.id,
      'title': meeting.title,
      'agenda': meeting.agenda,
      'scope': geographicScopeToJson(meeting.scope),
      'targetRoles':
          meeting.targetRoles.map((item) => item.name).toList(growable: false),
      'groupAssignmentId': meeting.groupAssignmentId,
      'inviteeMemberIds': meeting.inviteeMemberIds,
      'createdBy': meeting.createdBy,
      'createdAt': meeting.createdAt.toUtc().toIso8601String(),
      'scheduledAt': meeting.scheduledAt.toUtc().toIso8601String(),
      'status': meeting.status.name,
      'operationalCallId': meeting.operationalCallId,
      'startedAt': meeting.startedAt?.toUtc().toIso8601String(),
      'endedAt': meeting.endedAt?.toUtc().toIso8601String(),
      'attendedMemberIds': meeting.attendedMemberIds,
      'declinedMemberIds': meeting.declinedMemberIds,
      'actionItems': meeting.actionItems
          .map(
            (item) => {
              'id': item.id,
              'title': item.title,
              'createdAt': item.createdAt.toUtc().toIso8601String(),
              'createdBy': item.createdBy,
              'status': item.status.name,
              'ownerMemberId': item.ownerMemberId,
              'dueAt': item.dueAt?.toUtc().toIso8601String(),
              'completedAt': item.completedAt?.toUtc().toIso8601String(),
              'completedBy': item.completedBy,
            },
          )
          .toList(growable: false),
    };

CommandMeeting? _meetingFromJson(Map<String, Object?> row) {
  final id = row['id']?.toString();
  final title = row['title']?.toString();
  final scope = geographicScopeFromJson(row['scope']);
  final createdBy = row['createdBy']?.toString();
  final createdAt = _date(row['createdAt']);
  final scheduledAt = _date(row['scheduledAt']);
  final status = _meetingStatus(row['status']);
  final invitees = _stringList(row['inviteeMemberIds']);
  if (id == null ||
      title == null ||
      scope == null ||
      createdBy == null ||
      createdAt == null ||
      scheduledAt == null ||
      status == null ||
      invitees.isEmpty) {
    return null;
  }

  final roles = <TgcgRole>[];
  for (final value in _stringList(row['targetRoles'])) {
    for (final role in TgcgRole.values) {
      if (role.name == value) {
        roles.add(role);
        break;
      }
    }
  }

  final actions = <MeetingActionItem>[];
  final rawActions = row['actionItems'];
  if (rawActions is List) {
    for (final value in rawActions) {
      if (value is! Map) continue;
      final map = value.map((key, item) => MapEntry(key.toString(), item));
      final actionId = map['id']?.toString();
      final actionTitle = map['title']?.toString();
      final actionCreatedAt = _date(map['createdAt']);
      final actionCreatedBy = map['createdBy']?.toString();
      final actionStatus = _actionStatus(map['status']);
      if (actionId == null ||
          actionTitle == null ||
          actionCreatedAt == null ||
          actionCreatedBy == null ||
          actionStatus == null) {
        continue;
      }
      actions.add(
        MeetingActionItem(
          id: actionId,
          title: actionTitle,
          createdAt: actionCreatedAt,
          createdBy: actionCreatedBy,
          status: actionStatus,
          ownerMemberId: _clean(map['ownerMemberId']?.toString()),
          dueAt: _date(map['dueAt']),
          completedAt: _date(map['completedAt']),
          completedBy: _clean(map['completedBy']?.toString()),
        ),
      );
    }
  }

  return CommandMeeting(
    id: id,
    title: title,
    agenda: _clean(row['agenda']?.toString()),
    scope: scope,
    targetRoles: List.unmodifiable(roles),
    groupAssignmentId: _clean(row['groupAssignmentId']?.toString()),
    inviteeMemberIds: List.unmodifiable(invitees),
    createdBy: createdBy,
    createdAt: createdAt,
    scheduledAt: scheduledAt,
    status: status,
    operationalCallId: _clean(row['operationalCallId']?.toString()),
    startedAt: _date(row['startedAt']),
    endedAt: _date(row['endedAt']),
    attendedMemberIds:
        List.unmodifiable(_stringList(row['attendedMemberIds'])),
    declinedMemberIds:
        List.unmodifiable(_stringList(row['declinedMemberIds'])),
    actionItems: List.unmodifiable(actions),
  );
}

CommandMeetingStatus? _meetingStatus(Object? value) {
  final name = value?.toString();
  for (final item in CommandMeetingStatus.values) {
    if (item.name == name) return item;
  }
  return null;
}

MeetingActionStatus? _actionStatus(Object? value) {
  final name = value?.toString();
  for (final item in MeetingActionStatus.values) {
    if (item.name == name) return item;
  }
  return null;
}

List<String> _stringList(Object? value) => value is List
    ? value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false)
    : const <String>[];

DateTime? _date(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toUtc();

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class CommandMeetings extends InheritedNotifier<CommandMeetingController> {
  const CommandMeetings({
    super.key,
    required CommandMeetingController controller,
    required super.child,
  }) : super(notifier: controller);

  static CommandMeetingController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<CommandMeetings>();
      assert(value != null, 'CommandMeetings is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<CommandMeetings>();
    final value = element?.widget as CommandMeetings?;
    assert(value != null, 'CommandMeetings is missing above this context.');
    return value!.notifier!;
  }
}
