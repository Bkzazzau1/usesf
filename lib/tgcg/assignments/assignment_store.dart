import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../devices/managed_device_store.dart';
import '../geography/geography_registry.dart';
import '../membership/membership_store.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

enum AssignmentStatus {
  assigned,
  accepted,
  enRoute,
  checkedIn,
  active,
  completed,
  declined,
  reassigned,
  overdue,
  gpsMismatch,
  cancelled,
}

enum AssignmentPriority {
  normal,
  high,
  critical,
}

enum AssignmentPresence {
  unknown,
  insideGeofence,
  outsideGeofence,
  stale,
}

class PollingUnitCoverageSnapshot {
  const PollingUnitCoverageSnapshot({
    required this.unit,
    required this.activeAssignments,
    required this.atLocation,
    required this.enRoute,
    required this.staleGps,
    required this.gpsMismatch,
    required this.minimumStaffing,
  });

  final CanonicalPollingUnit unit;
  final int activeAssignments;
  final int atLocation;
  final int enRoute;
  final int staleGps;
  final int gpsMismatch;
  final int minimumStaffing;

  bool get isUnstaffed => activeAssignments == 0;
  bool get isBelowMinimum => activeAssignments < minimumStaffing;
  bool get hasPresenceGap =>
      activeAssignments > 0 && atLocation < activeAssignments;
  bool get hasGpsAlert => staleGps > 0 || gpsMismatch > 0;
  bool get needsAttention =>
      isBelowMinimum || hasPresenceGap || hasGpsAlert;
}

class AssignmentLocationPing {
  const AssignmentLocationPing({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
    required this.deviceId,
    required this.distanceFromTargetMeters,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;
  final String deviceId;
  final double? distanceFromTargetMeters;
}

class AssignmentEvent {
  const AssignmentEvent({
    required this.id,
    required this.assignmentId,
    required this.action,
    required this.actorId,
    required this.createdAt,
    this.detail,
  });

  final String id;
  final String assignmentId;
  final String action;
  final String actorId;
  final DateTime createdAt;
  final String? detail;
}

class MemberAssignment {
  const MemberAssignment({
    required this.id,
    required this.title,
    required this.memberId,
    required this.targetPollingUnitId,
    required this.targetScope,
    required this.assignedBy,
    required this.assignedAt,
    required this.status,
    required this.priority,
    this.instructions,
    this.deviceId,
    this.acceptedAt,
    this.enRouteAt,
    this.checkedInAt,
    this.activatedAt,
    this.completedAt,
    this.cancelledAt,
    this.dueAt,
    this.lastLocation,
    this.requiredEvidence = const [],
  });

  final String id;
  final String title;
  final String memberId;
  final String targetPollingUnitId;
  final GeographicScope targetScope;
  final String assignedBy;
  final DateTime assignedAt;
  final AssignmentStatus status;
  final AssignmentPriority priority;
  final String? instructions;
  final String? deviceId;
  final DateTime? acceptedAt;
  final DateTime? enRouteAt;
  final DateTime? checkedInAt;
  final DateTime? activatedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? dueAt;
  final AssignmentLocationPing? lastLocation;
  final List<EvidenceType> requiredEvidence;

  bool get isTerminal =>
      status == AssignmentStatus.completed ||
      status == AssignmentStatus.cancelled ||
      status == AssignmentStatus.declined;

  MemberAssignment copyWith({
    String? memberId,
    String? targetPollingUnitId,
    GeographicScope? targetScope,
    String? assignedBy,
    DateTime? assignedAt,
    AssignmentStatus? status,
    AssignmentPriority? priority,
    String? instructions,
    String? deviceId,
    bool clearDeviceId = false,
    DateTime? acceptedAt,
    DateTime? enRouteAt,
    DateTime? checkedInAt,
    DateTime? activatedAt,
    DateTime? completedAt,
    DateTime? cancelledAt,
    DateTime? dueAt,
    bool clearDueAt = false,
    AssignmentLocationPing? lastLocation,
  }) =>
      MemberAssignment(
        id: id,
        title: title,
        memberId: memberId ?? this.memberId,
        targetPollingUnitId:
            targetPollingUnitId ?? this.targetPollingUnitId,
        targetScope: targetScope ?? this.targetScope,
        assignedBy: assignedBy ?? this.assignedBy,
        assignedAt: assignedAt ?? this.assignedAt,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        instructions: instructions ?? this.instructions,
        deviceId: clearDeviceId ? null : deviceId ?? this.deviceId,
        acceptedAt: acceptedAt ?? this.acceptedAt,
        enRouteAt: enRouteAt ?? this.enRouteAt,
        checkedInAt: checkedInAt ?? this.checkedInAt,
        activatedAt: activatedAt ?? this.activatedAt,
        completedAt: completedAt ?? this.completedAt,
        cancelledAt: cancelledAt ?? this.cancelledAt,
        dueAt: clearDueAt ? null : dueAt ?? this.dueAt,
        lastLocation: lastLocation ?? this.lastLocation,
        requiredEvidence: requiredEvidence,
      );
}

class AssignmentController extends ChangeNotifier {
  AssignmentController({
    required MembershipOperationsController membership,
    required ManagedDeviceController devices,
    required OfflinePersistenceController persistence,
    List<MemberAssignment> assignments = const [],
    List<AssignmentEvent> events = const [],
  })  : _membership = membership,
        _devices = devices,
        _persistence = persistence,
        _assignments = List<MemberAssignment>.of(assignments),
        _events = List<AssignmentEvent>.of(events);

  factory AssignmentController.prototypeSeed({
    required MembershipOperationsController membership,
    required ManagedDeviceController devices,
    required OfflinePersistenceController persistence,
  }) =>
      AssignmentController(
        membership: membership,
        devices: devices,
        persistence: persistence,
      );

  final MembershipOperationsController _membership;
  final ManagedDeviceController _devices;
  final OfflinePersistenceController _persistence;
  final List<MemberAssignment> _assignments;
  final List<AssignmentEvent> _events;

  List<MemberAssignment> get assignments =>
      List.unmodifiable(_assignments);

  List<AssignmentEvent> get events => List.unmodifiable(_events);

  MemberAssignment? assignmentById(String id) {
    for (final assignment in _assignments) {
      if (assignment.id == id) return assignment;
    }
    return null;
  }

  List<MemberAssignment> assignmentsForMember(String memberId) =>
      _assignments
          .where((item) => item.memberId == memberId)
          .toList()
        ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

  List<MemberAssignment> activeAssignmentsForMember(String memberId) =>
      assignmentsForMember(memberId)
          .where((item) => !item.isTerminal)
          .toList(growable: false);

  List<MemberAssignment> assignmentsForScope(GeographicScope scope) =>
      _assignments
          .where(
            (item) =>
                GeographyRegistry.scopeContains(scope, item.targetScope),
          )
          .toList()
        ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

  List<AssignmentEvent> eventsForAssignment(String assignmentId) =>
      _events
          .where((item) => item.assignmentId == assignmentId)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  int get activeCount =>
      _assignments.where((item) => !item.isTerminal).length;

  int get checkedInCount => _assignments
      .where(
        (item) =>
            item.status == AssignmentStatus.checkedIn ||
            item.status == AssignmentStatus.active,
      )
      .length;

  int get gpsMismatchCount => _assignments
      .where((item) => item.status == AssignmentStatus.gpsMismatch)
      .length;

  List<PollingUnitCoverageSnapshot> coverageForScope(
    GeographicScope scope, {
    int minimumStaffing = 1,
  }) {
    final units = _membership.geography.pollingUnitsWithin(scope);
    final activeByUnit = <String, List<MemberAssignment>>{};
    for (final assignment in _assignments) {
      if (assignment.isTerminal) continue;
      activeByUnit
          .putIfAbsent(assignment.targetPollingUnitId, () => <MemberAssignment>[])
          .add(assignment);
    }

    final snapshots = <PollingUnitCoverageSnapshot>[];
    for (final unit in units) {
      final active = activeByUnit[unit.code] ?? const <MemberAssignment>[];
      var atLocation = 0;
      var enRoute = 0;
      var staleGps = 0;
      var gpsMismatch = 0;

      for (final assignment in active) {
        final presence = presenceFor(assignment);
        if (presence == AssignmentPresence.insideGeofence) {
          atLocation++;
        } else if (presence == AssignmentPresence.stale) {
          staleGps++;
        }
        if (assignment.status == AssignmentStatus.enRoute) {
          enRoute++;
        }
        if (assignment.status == AssignmentStatus.gpsMismatch ||
            presence == AssignmentPresence.outsideGeofence) {
          gpsMismatch++;
        }
      }

      snapshots.add(
        PollingUnitCoverageSnapshot(
          unit: unit,
          activeAssignments: active.length,
          atLocation: atLocation,
          enRoute: enRoute,
          staleGps: staleGps,
          gpsMismatch: gpsMismatch,
          minimumStaffing: minimumStaffing,
        ),
      );
    }
    return snapshots;
  }

  List<PollingUnitCoverageSnapshot> coverageGapsForScope(
    GeographicScope scope, {
    int minimumStaffing = 1,
  }) =>
      coverageForScope(
        scope,
        minimumStaffing: minimumStaffing,
      ).where((item) => item.needsAttention).toList(growable: false);

  int staffedPollingUnitCount(
    GeographicScope scope, {
    int minimumStaffing = 1,
  }) =>
      coverageForScope(scope, minimumStaffing: minimumStaffing)
          .where((item) => !item.isBelowMinimum)
          .length;

  Future<MemberAssignment> createAssignment({
    required String title,
    required String memberId,
    required String pollingUnitId,
    required String assignedBy,
    AssignmentPriority priority = AssignmentPriority.normal,
    String? instructions,
    DateTime? dueAt,
    List<EvidenceType> requiredEvidence = const [],
  }) async {
    final member = _membership.memberById(memberId);
    if (member == null) {
      throw ArgumentError('Unknown USESF member: $memberId');
    }
    final unit = _membership.geography.pollingUnit(pollingUnitId);
    if (unit == null) {
      throw ArgumentError(
        'Assignments must target a canonical polling unit.',
      );
    }
    final existing = activeAssignmentsForMember(memberId);
    final sameTarget = existing.any(
      (item) => item.targetPollingUnitId == unit.code,
    );
    if (sameTarget) {
      throw StateError(
        'This member already has an active assignment for the selected polling unit.',
      );
    }

    final now = DateTime.now().toUtc();
    final device = _devices.deviceForMember(memberId);
    final assignment = MemberAssignment(
      id: 'ASN-${now.microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Field Assignment' : title.trim(),
      memberId: memberId,
      targetPollingUnitId: unit.code,
      targetScope: unit.scope,
      assignedBy: assignedBy,
      assignedAt: now,
      status: AssignmentStatus.assigned,
      priority: priority,
      instructions: _clean(instructions),
      deviceId: device?.id,
      dueAt: dueAt?.toUtc(),
      requiredEvidence: List.unmodifiable(requiredEvidence),
    );
    _assignments.insert(0, assignment);
    await _appendEvent(
      assignment,
      action: 'assigned',
      actorId: assignedBy,
      detail:
          'Assigned to ${member.fullName} at ${unit.displayCode}.',
    );
    notifyListeners();
    await _persistAssignment(assignment);
    return assignment;
  }

  Future<MemberAssignment> transition({
    required String assignmentId,
    required AssignmentStatus status,
    required String actorId,
  }) async {
    final index =
        _assignments.indexWhere((item) => item.id == assignmentId);
    if (index < 0) {
      throw ArgumentError('Unknown assignment: $assignmentId');
    }
    final current = _assignments[index];
    if (!_canTransition(current.status, status)) {
      throw StateError(
        'Invalid assignment transition from ${current.status.name} to ${status.name}.',
      );
    }

    final now = DateTime.now().toUtc();
    final updated = current.copyWith(
      status: status,
      acceptedAt:
          status == AssignmentStatus.accepted ? now : current.acceptedAt,
      enRouteAt:
          status == AssignmentStatus.enRoute ? now : current.enRouteAt,
      checkedInAt:
          status == AssignmentStatus.checkedIn ? now : current.checkedInAt,
      activatedAt:
          status == AssignmentStatus.active ? now : current.activatedAt,
      completedAt:
          status == AssignmentStatus.completed ? now : current.completedAt,
      cancelledAt:
          status == AssignmentStatus.cancelled ? now : current.cancelledAt,
    );
    _assignments[index] = updated;
    await _appendEvent(
      updated,
      action: status.name,
      actorId: actorId,
    );
    notifyListeners();
    await _persistAssignment(updated);
    return updated;
  }

  Future<MemberAssignment> reassign({
    required String assignmentId,
    required String newMemberId,
    required String actorId,
  }) async {
    final index =
        _assignments.indexWhere((item) => item.id == assignmentId);
    if (index < 0) {
      throw ArgumentError('Unknown assignment: $assignmentId');
    }
    final member = _membership.memberById(newMemberId);
    if (member == null) {
      throw ArgumentError('Unknown USESF member: $newMemberId');
    }

    final current = _assignments[index];
    final now = DateTime.now().toUtc();
    final device = _devices.deviceForMember(newMemberId);
    final updated = MemberAssignment(
      id: current.id,
      title: current.title,
      memberId: newMemberId,
      targetPollingUnitId: current.targetPollingUnitId,
      targetScope: current.targetScope,
      assignedBy: actorId,
      assignedAt: now,
      status: AssignmentStatus.assigned,
      priority: current.priority,
      instructions: current.instructions,
      deviceId: device?.id,
      dueAt: current.dueAt,
      requiredEvidence: current.requiredEvidence,
    );
    _assignments[index] = updated;
    await _appendEvent(
      updated,
      action: 'reassigned',
      actorId: actorId,
      detail: 'Reassigned to ${member.fullName}.',
    );
    notifyListeners();
    await _persistAssignment(updated);
    return updated;
  }

  void recordLocationHeartbeat({
    required String assignmentId,
    required String deviceId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime capturedAt,
    int? batteryPercent,
    String? appVersion,
    String? syncState,
  }) {
    final index =
        _assignments.indexWhere((item) => item.id == assignmentId);
    if (index < 0) return;
    final current = _assignments[index];
    if (current.deviceId != null && current.deviceId != deviceId) {
      return;
    }
    final unit =
        _membership.geography.pollingUnit(current.targetPollingUnitId);
    final distance = unit?.operationalLatitude == null ||
            unit?.operationalLongitude == null
        ? null
        : _distanceMeters(
            latitude,
            longitude,
            unit!.operationalLatitude!,
            unit.operationalLongitude!,
          );

    final ping = AssignmentLocationPing(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      capturedAt: capturedAt.toUtc(),
      deviceId: deviceId,
      distanceFromTargetMeters: distance,
    );
    _assignments[index] = current.copyWith(lastLocation: ping);

    _devices.recordHeartbeat(
      deviceId: deviceId,
      capturedAt: capturedAt,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      batteryPercent: batteryPercent,
      appVersion: appVersion,
      syncState: syncState,
    );
    notifyListeners();
  }

  Future<MemberAssignment> checkIn({
    required String assignmentId,
    required String actorId,
    required String deviceId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime capturedAt,
  }) async {
    final index =
        _assignments.indexWhere((item) => item.id == assignmentId);
    if (index < 0) {
      throw ArgumentError('Unknown assignment: $assignmentId');
    }
    final current = _assignments[index];
    if (current.deviceId != null && current.deviceId != deviceId) {
      throw StateError(
        'This assignment is bound to a different managed device.',
      );
    }
    final unit =
        _membership.geography.pollingUnit(current.targetPollingUnitId);
    if (unit == null ||
        unit.operationalLatitude == null ||
        unit.operationalLongitude == null) {
      throw StateError(
        'The assigned polling unit does not yet have an operational GPS coordinate.',
      );
    }

    final distance = _distanceMeters(
      latitude,
      longitude,
      unit.operationalLatitude!,
      unit.operationalLongitude!,
    );
    final ping = AssignmentLocationPing(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      capturedAt: capturedAt.toUtc(),
      deviceId: deviceId,
      distanceFromTargetMeters: distance,
    );
    final inside = distance <= unit.geofenceRadiusMeters;
    final status = inside
        ? AssignmentStatus.checkedIn
        : AssignmentStatus.gpsMismatch;
    final updated = current.copyWith(
      status: status,
      checkedInAt: inside ? capturedAt.toUtc() : current.checkedInAt,
      lastLocation: ping,
      deviceId: deviceId,
    );
    _assignments[index] = updated;
    _devices.recordHeartbeat(
      deviceId: deviceId,
      capturedAt: capturedAt,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
    );
    await _appendEvent(
      updated,
      action: inside ? 'checked_in' : 'gps_mismatch',
      actorId: actorId,
      detail:
          'Distance from assigned polling unit: ${distance.toStringAsFixed(1)} m; GPS accuracy ±${accuracyMeters.toStringAsFixed(1)} m.',
    );
    notifyListeners();
    await _persistAssignment(updated);
    return updated;
  }

  AssignmentPresence presenceFor(
    MemberAssignment assignment, {
    DateTime? now,
    Duration staleAfter = const Duration(minutes: 7),
  }) {
    final ping = assignment.lastLocation;
    if (ping == null) return AssignmentPresence.unknown;
    final current = (now ?? DateTime.now()).toUtc();
    if (current.difference(ping.capturedAt).abs() > staleAfter) {
      return AssignmentPresence.stale;
    }
    final unit =
        _membership.geography.pollingUnit(assignment.targetPollingUnitId);
    final distance = ping.distanceFromTargetMeters;
    if (unit == null || distance == null) {
      return AssignmentPresence.unknown;
    }
    return distance <= unit.geofenceRadiusMeters
        ? AssignmentPresence.insideGeofence
        : AssignmentPresence.outsideGeofence;
  }

  Future<void> _appendEvent(
    MemberAssignment assignment, {
    required String action,
    required String actorId,
    String? detail,
  }) async {
    final now = DateTime.now().toUtc();
    final event = AssignmentEvent(
      id: 'ASE-${now.microsecondsSinceEpoch}',
      assignmentId: assignment.id,
      action: action,
      actorId: actorId,
      createdAt: now,
      detail: detail,
    );
    _events.add(event);
    await _persistence.persistMutation(
      entityType: 'assignment_event',
      entityId: event.id,
      mutationType: SyncMutationType.create,
      scopeKey: scopeStorageKey(assignment.targetScope),
      ownerId: assignment.memberId,
      payload: {
        'id': event.id,
        'assignmentId': event.assignmentId,
        'action': event.action,
        'actorId': event.actorId,
        'createdAt': event.createdAt.toIso8601String(),
        'detail': event.detail,
      },
    );
  }

  Future<void> _persistAssignment(MemberAssignment assignment) =>
      _persistence.persistMutation(
        entityType: 'member_assignment',
        entityId: assignment.id,
        mutationType: SyncMutationType.upsert,
        scopeKey: scopeStorageKey(assignment.targetScope),
        ownerId: assignment.memberId,
        payload: {
          'id': assignment.id,
          'title': assignment.title,
          'memberId': assignment.memberId,
          'targetPollingUnitId': assignment.targetPollingUnitId,
          'targetScope': geographicScopeToJson(assignment.targetScope),
          'assignedBy': assignment.assignedBy,
          'assignedAt': assignment.assignedAt.toIso8601String(),
          'status': assignment.status.name,
          'priority': assignment.priority.name,
          'instructions': assignment.instructions,
          'deviceId': assignment.deviceId,
          'acceptedAt': assignment.acceptedAt?.toIso8601String(),
          'enRouteAt': assignment.enRouteAt?.toIso8601String(),
          'checkedInAt': assignment.checkedInAt?.toIso8601String(),
          'activatedAt': assignment.activatedAt?.toIso8601String(),
          'completedAt': assignment.completedAt?.toIso8601String(),
          'cancelledAt': assignment.cancelledAt?.toIso8601String(),
          'dueAt': assignment.dueAt?.toIso8601String(),
          'requiredEvidence':
              assignment.requiredEvidence.map((item) => item.name).toList(),
          'lastLocation': assignment.lastLocation == null
              ? null
              : {
                  'latitude': assignment.lastLocation!.latitude,
                  'longitude': assignment.lastLocation!.longitude,
                  'accuracyMeters':
                      assignment.lastLocation!.accuracyMeters,
                  'capturedAt':
                      assignment.lastLocation!.capturedAt.toIso8601String(),
                  'deviceId': assignment.lastLocation!.deviceId,
                  'distanceFromTargetMeters':
                      assignment.lastLocation!.distanceFromTargetMeters,
                },
        },
      );

  static bool _canTransition(
    AssignmentStatus current,
    AssignmentStatus next,
  ) =>
      switch (current) {
        AssignmentStatus.assigned =>
          next == AssignmentStatus.accepted ||
              next == AssignmentStatus.declined ||
              next == AssignmentStatus.cancelled,
        AssignmentStatus.accepted =>
          next == AssignmentStatus.enRoute ||
              next == AssignmentStatus.cancelled ||
              next == AssignmentStatus.reassigned,
        AssignmentStatus.enRoute =>
          next == AssignmentStatus.checkedIn ||
              next == AssignmentStatus.gpsMismatch ||
              next == AssignmentStatus.cancelled ||
              next == AssignmentStatus.reassigned,
        AssignmentStatus.gpsMismatch =>
          next == AssignmentStatus.enRoute ||
              next == AssignmentStatus.checkedIn ||
              next == AssignmentStatus.cancelled ||
              next == AssignmentStatus.reassigned,
        AssignmentStatus.checkedIn =>
          next == AssignmentStatus.active ||
              next == AssignmentStatus.cancelled ||
              next == AssignmentStatus.reassigned,
        AssignmentStatus.active =>
          next == AssignmentStatus.completed ||
              next == AssignmentStatus.cancelled ||
              next == AssignmentStatus.reassigned,
        AssignmentStatus.overdue =>
          next == AssignmentStatus.enRoute ||
              next == AssignmentStatus.cancelled ||
              next == AssignmentStatus.reassigned,
        AssignmentStatus.reassigned =>
          next == AssignmentStatus.assigned,
        AssignmentStatus.completed ||
        AssignmentStatus.declined ||
        AssignmentStatus.cancelled => false,
      };

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    double radians(double degrees) => degrees * math.pi / 180;
    final dLat = radians(lat2 - lat1);
    final dLon = radians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(radians(lat1)) *
            math.cos(radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class Assignments extends InheritedNotifier<AssignmentController> {
  const Assignments({
    super.key,
    required AssignmentController controller,
    required super.child,
  }) : super(notifier: controller);

  static AssignmentController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<Assignments>();
      assert(value != null, 'Assignments is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<Assignments>();
    final value = element?.widget as Assignments?;
    assert(value != null, 'Assignments is missing above this context.');
    return value!.notifier!;
  }
}
