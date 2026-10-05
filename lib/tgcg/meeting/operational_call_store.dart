import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../geography/geography_registry.dart';\nimport '../membership/membership_store.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

enum OperationalCallKind { audio, video, conference }

enum OperationalCallStatus {
  ringing,
  active,
  ended,
  declined,
  cancelled,
  missed,
}

class OperationalCallSession {
  const OperationalCallSession({
    required this.id,
    required this.kind,
    required this.callerId,
    required this.callerName,
    required this.recipientMemberIds,
    required this.createdAt,
    required this.status,
    this.assignmentId,
    this.groupAssignmentId,
    this.answeredAt,
    this.endedAt,
    this.joinedMemberIds = const [],
    this.declinedMemberIds = const [],
  });

  final String id;
  final OperationalCallKind kind;
  final String callerId;
  final String callerName;
  final List<String> recipientMemberIds;
  final DateTime createdAt;
  final OperationalCallStatus status;
  final String? assignmentId;
  final String? groupAssignmentId;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final List<String> joinedMemberIds;
  final List<String> declinedMemberIds;

  bool get isOpen =>
      status == OperationalCallStatus.ringing ||
      status == OperationalCallStatus.active;

  bool includesMember(String memberId) =>
      recipientMemberIds.contains(memberId);

  bool awaitingMember(String memberId) =>
      isOpen &&
      includesMember(memberId) &&
      !joinedMemberIds.contains(memberId) &&
      !declinedMemberIds.contains(memberId);

  OperationalCallSession copyWith({
    OperationalCallStatus? status,
    DateTime? answeredAt,
    DateTime? endedAt,
    List<String>? joinedMemberIds,
    List<String>? declinedMemberIds,
  }) =>
      OperationalCallSession(
        id: id,
        kind: kind,
        callerId: callerId,
        callerName: callerName,
        recipientMemberIds: recipientMemberIds,
        createdAt: createdAt,
        status: status ?? this.status,
        assignmentId: assignmentId,
        groupAssignmentId: groupAssignmentId,
        answeredAt: answeredAt ?? this.answeredAt,
        endedAt: endedAt ?? this.endedAt,
        joinedMemberIds: joinedMemberIds ?? this.joinedMemberIds,
        declinedMemberIds:
            declinedMemberIds ?? this.declinedMemberIds,
      );
}

class OperationalCallController extends ChangeNotifier {
  OperationalCallController({
    required MembershipOperationsController membership,
    required OfflinePersistenceController persistence,
    List<OperationalCallSession> calls = const [],
  })  : _membership = membership,
        _persistence = persistence,
        _calls = List<OperationalCallSession>.of(calls);

  final MembershipOperationsController _membership;
  final OfflinePersistenceController _persistence;
  final List<OperationalCallSession> _calls;

  List<OperationalCallSession> get calls => List.unmodifiable(_calls);

  OperationalCallSession? callById(String id) {
    for (final call in _calls) {
      if (call.id == id) return call;
    }
    return null;
  }

  List<OperationalCallSession> incomingForMember(String memberId) =>
      _calls
          .where((call) => call.awaitingMember(memberId))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<OperationalCallSession> callsForMember(String memberId) =>
      _calls
          .where((call) => call.includesMember(memberId))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> hydrateFromOffline() async {
    final rows = await _persistence.readEntities(
      entityType: 'operational_call_session',
    );
    var changed = false;
    for (final row in rows) {
      final id = row['id']?.toString();
      final callerId = row['callerId']?.toString();
      final callerName = row['callerName']?.toString();
      final createdAt =
          DateTime.tryParse(row['createdAt']?.toString() ?? '')?.toUtc();
      final kind = _kind(row['kind']);
      final status = _status(row['status']);
      final recipients = row['recipientMemberIds'] is List
          ? (row['recipientMemberIds'] as List)
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
          : const <String>[];
      if (id == null ||
          callerId == null ||
          callerName == null ||
          createdAt == null ||
          kind == null ||
          status == null ||
          recipients.isEmpty) {
        continue;
      }

      final restored = OperationalCallSession(
        id: id,
        kind: kind,
        callerId: callerId,
        callerName: callerName,
        recipientMemberIds: recipients,
        createdAt: createdAt,
        status: status,
        assignmentId: _clean(row['assignmentId']?.toString()),
        groupAssignmentId:
            _clean(row['groupAssignmentId']?.toString()),
        answeredAt:
            DateTime.tryParse(row['answeredAt']?.toString() ?? '')?.toUtc(),
        endedAt:
            DateTime.tryParse(row['endedAt']?.toString() ?? '')?.toUtc(),
        joinedMemberIds: _stringList(row['joinedMemberIds']),
        declinedMemberIds: _stringList(row['declinedMemberIds']),
      );
      final index = _calls.indexWhere((item) => item.id == restored.id);
      if (index < 0) {
        _calls.add(restored);
      } else {
        _calls[index] = restored;
      }
      changed = true;
    }
    if (changed) {
      _calls.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }
  }

  Future<OperationalCallSession> startDirectCall({
    required String recipientMemberId,
    required OperationalCallKind kind,
    required String callerId,
    required String callerName,
    required TgcgRole callerRole,
    required GeographicScope authorizedScope,
    String? assignmentId,
  }) =>
      _startCall(
        recipientMemberIds: [recipientMemberId],
        kind: kind,
        callerId: callerId,
        callerName: callerName,
        callerRole: callerRole,
        authorizedScope: authorizedScope,
        assignmentId: assignmentId,
      );

  Future<OperationalCallSession> startConference({
    required List<String> recipientMemberIds,
    required String callerId,
    required String callerName,
    required TgcgRole callerRole,
    required GeographicScope authorizedScope,
    String? groupAssignmentId,
  }) =>
      _startCall(
        recipientMemberIds: recipientMemberIds,
        kind: OperationalCallKind.conference,
        callerId: callerId,
        callerName: callerName,
        callerRole: callerRole,
        authorizedScope: authorizedScope,
        groupAssignmentId: groupAssignmentId,
      );

  Future<OperationalCallSession> _startCall({
    required List<String> recipientMemberIds,
    required OperationalCallKind kind,
    required String callerId,
    required String callerName,
    required TgcgRole callerRole,
    required GeographicScope authorizedScope,
    String? assignmentId,
    String? groupAssignmentId,
  }) async {
    if (callerRole != TgcgRole.stateCoordinator ||
        authorizedScope.level != GeographyLevel.state ||
        authorizedScope.stateId != GeographicScope.kaduna.stateId) {
      throw StateError(
        'Only the Kaduna State Coordinator can call members from Assignment Control.',
      );
    }

    final recipients = recipientMemberIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (recipients.isEmpty) {
      throw StateError('Select at least one member.');
    }
    for (final memberId in recipients) {
      final member = _membership.memberById(memberId);
      if (member == null) {
        throw ArgumentError('Unknown member: $memberId');
      }
      if (member.isBlocked) {
        throw StateError('Blocked members cannot receive operational calls.');
      }
      final scope = _membership.registrationScopeForMember(memberId);
      if (scope != null &&
          !GeographyRegistry.scopeContains(authorizedScope, scope)) {
        throw StateError('The selected member is outside Kaduna State scope.');
      }
    }

    final now = DateTime.now().toUtc();
    final call = OperationalCallSession(
      id: 'CALL-${now.microsecondsSinceEpoch}',
      kind: kind,
      callerId: callerId,
      callerName: callerName.trim().isEmpty
          ? 'State Coordinator'
          : callerName.trim(),
      recipientMemberIds: List.unmodifiable(recipients),
      createdAt: now,
      status: OperationalCallStatus.ringing,
      assignmentId: _clean(assignmentId),
      groupAssignmentId: _clean(groupAssignmentId),
    );
    _calls.insert(0, call);
    await _persist(call);
    notifyListeners();
    return call;
  }

  Future<OperationalCallSession> answerCall({
    required String callId,
    required String memberId,
  }) async {
    final index = _calls.indexWhere((item) => item.id == callId);
    if (index < 0) throw ArgumentError('Unknown call: $callId');
    final current = _calls[index];
    if (!current.awaitingMember(memberId)) {
      throw StateError('This call is not awaiting this member.');
    }

    final joined = {...current.joinedMemberIds, memberId}.toList();
    final now = DateTime.now().toUtc();
    final updated = current.copyWith(
      status: OperationalCallStatus.active,
      answeredAt: current.answeredAt ?? now,
      joinedMemberIds: List.unmodifiable(joined),
    );
    _calls[index] = updated;
    await _persist(updated);
    notifyListeners();
    return updated;
  }

  Future<OperationalCallSession> declineCall({
    required String callId,
    required String memberId,
  }) async {
    final index = _calls.indexWhere((item) => item.id == callId);
    if (index < 0) throw ArgumentError('Unknown call: $callId');
    final current = _calls[index];
    if (!current.awaitingMember(memberId)) {
      throw StateError('This call is not awaiting this member.');
    }
    final declined = {...current.declinedMemberIds, memberId}.toList();
    final allResolved = current.recipientMemberIds.every(
      (id) => declined.contains(id) || current.joinedMemberIds.contains(id),
    );
    final nobodyJoined = current.joinedMemberIds.isEmpty;
    final updated = current.copyWith(
      status: allResolved && nobodyJoined
          ? OperationalCallStatus.declined
          : current.status,
      endedAt: allResolved && nobodyJoined
          ? DateTime.now().toUtc()
          : current.endedAt,
      declinedMemberIds: List.unmodifiable(declined),
    );
    _calls[index] = updated;
    await _persist(updated);
    notifyListeners();
    return updated;
  }

  Future<OperationalCallSession> endCall({
    required String callId,
    required String actorId,
  }) async {
    final index = _calls.indexWhere((item) => item.id == callId);
    if (index < 0) throw ArgumentError('Unknown call: $callId');
    final current = _calls[index];
    if (!current.isOpen) return current;
    if (current.callerId != actorId &&
        !current.recipientMemberIds.contains(actorId)) {
      throw StateError('This user is not part of the call.');
    }
    final updated = current.copyWith(
      status: current.status == OperationalCallStatus.ringing
          ? OperationalCallStatus.cancelled
          : OperationalCallStatus.ended,
      endedAt: DateTime.now().toUtc(),
    );
    _calls[index] = updated;
    await _persist(updated);
    notifyListeners();
    return updated;
  }

  Future<void> _persist(OperationalCallSession call) =>
      _persistence.persistMutation(
        entityType: 'operational_call_session',
        entityId: call.id,
        mutationType: SyncMutationType.upsert,
        scopeKey: scopeStorageKey(GeographicScope.kaduna),
        ownerId: call.callerId,
        payload: {
          'id': call.id,
          'kind': call.kind.name,
          'callerId': call.callerId,
          'callerName': call.callerName,
          'recipientMemberIds': call.recipientMemberIds,
          'createdAt': call.createdAt.toIso8601String(),
          'status': call.status.name,
          'assignmentId': call.assignmentId,
          'groupAssignmentId': call.groupAssignmentId,
          'answeredAt': call.answeredAt?.toIso8601String(),
          'endedAt': call.endedAt?.toIso8601String(),
          'joinedMemberIds': call.joinedMemberIds,
          'declinedMemberIds': call.declinedMemberIds,
        },
      );

  static List<String> _stringList(Object? value) => value is List
      ? value.map((item) => item.toString()).toList(growable: false)
      : const <String>[];

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static OperationalCallKind? _kind(Object? value) {
    final name = value?.toString();
    for (final item in OperationalCallKind.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static OperationalCallStatus? _status(Object? value) {
    final name = value?.toString();
    for (final item in OperationalCallStatus.values) {
      if (item.name == name) return item;
    }
    return null;
  }
}

class OperationalCalls extends InheritedNotifier<OperationalCallController> {
  const OperationalCalls({
    super.key,
    required OperationalCallController controller,
    required super.child,
  }) : super(notifier: controller);

  static OperationalCallController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<OperationalCalls>();
      assert(value != null, 'OperationalCalls is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<OperationalCalls>();
    final value = element?.widget as OperationalCalls?;
    assert(value != null, 'OperationalCalls is missing above this context.');
    return value!.notifier!;
  }
}
