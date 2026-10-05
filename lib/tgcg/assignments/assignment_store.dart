import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../devices/managed_device_store.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../membership/membership_store.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

/// Capabilities that an assignment may temporarily grant. Anything else
/// (verification, broadcasts, membership or system administration) can only
/// come from a role.
const Set<TgcgCapability> assignmentGrantableCapabilities = {
  TgcgCapability.viewGeography,
  TgcgCapability.viewIncidents,
  TgcgCapability.createIncident,
  TgcgCapability.submitFieldReport,
  TgcgCapability.viewCommunications,
  TgcgCapability.sendOperationalMessage,
  TgcgCapability.viewMediaIntelligence,
  TgcgCapability.viewDiscussionRoom,
  TgcgCapability.createDiscussionThread,
  TgcgCapability.postDiscussionReply,
  TgcgCapability.viewMeetingRoom,
  TgcgCapability.startMeeting,
  TgcgCapability.joinMeeting,
  TgcgCapability.viewEvidence,
};

const Set<TgcgCapability> groupAssignmentRestrictedCapabilities = {
  TgcgCapability.viewMediaIntelligence,
};

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

enum AssignmentLocationMode {
  none,
  pollingUnit,
}

enum AssignmentPresence {
  unknown,
  insideGeofence,
  outsideGeofence,
  stale,
}

enum GroupAssignmentDistribution {
  together,
  manual,
  automatic,
}

enum GroupAssignmentStatus {
  assigned,
  active,
  submitted,
  cancelled,
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

class GroupAssignment {
  const GroupAssignment({
    required this.id,
    required this.title,
    required this.chairmanMemberId,
    required this.memberIds,
    required this.targetScopes,
    required this.distribution,
    required this.assignedBy,
    required this.assignedAt,
    required this.status,
    required this.priority,
    this.instructions,
    this.dueAt,
    this.submittedAt,
    this.submittedBy,
    this.systemIntelligenceRestricted = true,
  });

  final String id;
  final String title;
  final String chairmanMemberId;
  final List<String> memberIds;
  final List<GeographicScope> targetScopes;
  final GroupAssignmentDistribution distribution;
  final String assignedBy;
  final DateTime assignedAt;
  final GroupAssignmentStatus status;
  final AssignmentPriority priority;
  final String? instructions;
  final DateTime? dueAt;
  final DateTime? submittedAt;
  final String? submittedBy;

  /// GPS, AI-derived records and operational intelligence are coordinator /
  /// backend data. Group members never receive these records through the
  /// member-facing assignment surface.
  final bool systemIntelligenceRestricted;

  bool get isTerminal =>
      status == GroupAssignmentStatus.submitted ||
      status == GroupAssignmentStatus.cancelled;

  GroupAssignment copyWith({
    String? chairmanMemberId,
    GroupAssignmentStatus? status,
    DateTime? submittedAt,
    String? submittedBy,
  }) =>
      GroupAssignment(
        id: id,
        title: title,
        chairmanMemberId: chairmanMemberId ?? this.chairmanMemberId,
        memberIds: memberIds,
        targetScopes: targetScopes,
        distribution: distribution,
        assignedBy: assignedBy,
        assignedAt: assignedAt,
        status: status ?? this.status,
        priority: priority,
        instructions: instructions,
        dueAt: dueAt,
        submittedAt: submittedAt ?? this.submittedAt,
        submittedBy: submittedBy ?? this.submittedBy,
        systemIntelligenceRestricted: systemIntelligenceRestricted,
      );
}

class MemberAssignment {
  const MemberAssignment({
    required this.id,
    required this.title,
    required this.memberId,
    required this.targetPollingUnitId,
    required this.targetScope,
    this.locationMode = AssignmentLocationMode.pollingUnit,
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
    this.grantedCapabilities = const {},
    this.evidence = const [],
    this.groupAssignmentId,
    this.isGroupChairman = false,
    this.systemIntelligenceRestricted = false,
  });

  final String id;
  final String title;
  final String memberId;
  final String? targetPollingUnitId;
  final GeographicScope targetScope;
  final AssignmentLocationMode locationMode;
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
  final Set<TgcgCapability> grantedCapabilities;
  final List<EvidenceAttachment> evidence;
  final String? groupAssignmentId;
  final bool isGroupChairman;
  final bool systemIntelligenceRestricted;

  bool get belongsToGroup => groupAssignmentId != null;

  bool get isTerminal =>
      status == AssignmentStatus.completed ||
      status == AssignmentStatus.cancelled ||
      status == AssignmentStatus.declined;

  /// Whether this assignment currently confers its granted capabilities on
  /// the holder. Terminal assignments never do, and neither does one that is
  /// mid-handover (`reassigned`), so access is not retained by the outgoing
  /// holder.
  bool get confersAccess =>
      !isTerminal && status != AssignmentStatus.reassigned;

  MemberAssignment copyWith({
    String? memberId,
    String? targetPollingUnitId,
    GeographicScope? targetScope,
    AssignmentLocationMode? locationMode,
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
    Set<TgcgCapability>? grantedCapabilities,
    List<EvidenceAttachment>? evidence,
    String? groupAssignmentId,
    bool? isGroupChairman,
    bool? systemIntelligenceRestricted,
  }) =>
      MemberAssignment(
        id: id,
        title: title,
        memberId: memberId ?? this.memberId,
        targetPollingUnitId:
            targetPollingUnitId ?? this.targetPollingUnitId,
        targetScope: targetScope ?? this.targetScope,
        locationMode: locationMode ?? this.locationMode,
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
        grantedCapabilities:
            grantedCapabilities ?? this.grantedCapabilities,
        evidence: evidence ?? this.evidence,
        groupAssignmentId: groupAssignmentId ?? this.groupAssignmentId,
        isGroupChairman: isGroupChairman ?? this.isGroupChairman,
        systemIntelligenceRestricted:
            systemIntelligenceRestricted ?? this.systemIntelligenceRestricted,
      );
}

class AssignmentController extends ChangeNotifier {
  AssignmentController({
    required MembershipOperationsController membership,
    required ManagedDeviceController devices,
    required OfflinePersistenceController persistence,
    List<MemberAssignment> assignments = const [],
    List<GroupAssignment> groupAssignments = const [],
    List<AssignmentEvent> events = const [],
    Map<String, int> minimumStaffingByPollingUnit = const {},
  })  : _membership = membership,
        _devices = devices,
        _persistence = persistence,
        _assignments = List<MemberAssignment>.of(assignments),
        _groupAssignments = List<GroupAssignment>.of(groupAssignments),
        _events = List<AssignmentEvent>.of(events),
        _minimumStaffingByPollingUnit =
            Map<String, int>.of(minimumStaffingByPollingUnit);

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
  final List<GroupAssignment> _groupAssignments;
  final List<AssignmentEvent> _events;
  final Map<String, int> _minimumStaffingByPollingUnit;

  List<MemberAssignment> get assignments =>
      List.unmodifiable(_assignments);
  List<GroupAssignment> get groupAssignments =>
      List.unmodifiable(_groupAssignments);

  Future<void> hydrateFromOffline() async {
    final assignmentRows = await _persistence.readEntities(
      entityType: 'member_assignment',
    );
    final groupRows = await _persistence.readEntities(
      entityType: 'group_assignment',
    );
    final eventRows = await _persistence.readEntities(
      entityType: 'assignment_event',
    );
    final staffingRows = await _persistence.readEntities(
      entityType: 'polling_unit_staffing_requirement',
    );

    var changed = false;

    for (final row in assignmentRows) {
      final id = row['id']?.toString();
      final title = row['title']?.toString();
      final memberId = row['memberId']?.toString();
      final pollingUnitId = _clean(row['targetPollingUnitId']?.toString());
      final scope = geographicScopeFromJson(row['targetScope']);
      final assignedBy = row['assignedBy']?.toString();
      final assignedAt = _date(row['assignedAt']);
      final status = _assignmentStatus(row['status']);
      final priority = _assignmentPriority(row['priority']);
      if (id == null ||
          title == null ||
          memberId == null ||
          scope == null ||
          assignedBy == null ||
          assignedAt == null ||
          status == null ||
          priority == null) {
        continue;
      }

      final requiredEvidence = <EvidenceType>[];
      final requiredRaw = row['requiredEvidence'];
      if (requiredRaw is List) {
        for (final value in requiredRaw) {
          final type = _evidenceType(value);
          if (type != null) requiredEvidence.add(type);
        }
      }

      final evidence = <EvidenceAttachment>[];
      final evidenceRaw = row['evidence'];
      if (evidenceRaw is List) {
        for (final value in evidenceRaw) {
          final item = evidenceFromJson(value);
          if (item != null) evidence.add(item);
        }
      }

      AssignmentLocationPing? lastLocation;
      final locationRaw = row['lastLocation'];
      if (locationRaw is Map) {
        final location = locationRaw.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final latitude = _double(location['latitude']);
        final longitude = _double(location['longitude']);
        final accuracy = _double(location['accuracyMeters']);
        final capturedAt = _date(location['capturedAt']);
        final deviceId = location['deviceId']?.toString();
        if (latitude != null &&
            longitude != null &&
            accuracy != null &&
            capturedAt != null &&
            deviceId != null) {
          lastLocation = AssignmentLocationPing(
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracy,
            capturedAt: capturedAt,
            deviceId: deviceId,
            distanceFromTargetMeters:
                _double(location['distanceFromTargetMeters']),
          );
        }
      }

      final locationMode = _assignmentLocationMode(row['locationMode']) ??
          (pollingUnitId == null
              ? AssignmentLocationMode.none
              : AssignmentLocationMode.pollingUnit);
      final grantedCapabilities = <TgcgCapability>{};
      final capabilitiesRaw = row['grantedCapabilities'];
      if (capabilitiesRaw is List) {
        for (final value in capabilitiesRaw) {
          final capability = _capability(value);
          if (capability != null) grantedCapabilities.add(capability);
        }
      }

      final restored = MemberAssignment(
        id: id,
        title: title,
        memberId: memberId,
        targetPollingUnitId: pollingUnitId,
        targetScope: scope,
        locationMode: locationMode,
        assignedBy: assignedBy,
        assignedAt: assignedAt,
        status: status,
        priority: priority,
        instructions: row['instructions']?.toString(),
        deviceId: row['deviceId']?.toString(),
        acceptedAt: _date(row['acceptedAt']),
        enRouteAt: _date(row['enRouteAt']),
        checkedInAt: _date(row['checkedInAt']),
        activatedAt: _date(row['activatedAt']),
        completedAt: _date(row['completedAt']),
        cancelledAt: _date(row['cancelledAt']),
        dueAt: _date(row['dueAt']),
        lastLocation: lastLocation,
        requiredEvidence: List.unmodifiable(requiredEvidence),
        grantedCapabilities: Set.unmodifiable(grantedCapabilities),
        evidence: List.unmodifiable(evidence),
        groupAssignmentId: _clean(row['groupAssignmentId']?.toString()),
        isGroupChairman: row['isGroupChairman'] == true,
        systemIntelligenceRestricted:
            row['systemIntelligenceRestricted'] == true,
      );

      final index = _assignments.indexWhere((item) => item.id == id);
      if (index < 0) {
        _assignments.add(restored);
      } else {
        _assignments[index] = restored;
      }
      changed = true;
    }

    for (final row in groupRows) {
      final id = row['id']?.toString();
      final title = row['title']?.toString();
      final chairmanMemberId = row['chairmanMemberId']?.toString();
      final assignedBy = row['assignedBy']?.toString();
      final assignedAt = _date(row['assignedAt']);
      final status = _groupAssignmentStatus(row['status']);
      final distribution = _groupAssignmentDistribution(row['distribution']);
      final priority = _assignmentPriority(row['priority']);
      final memberIds = row['memberIds'] is List
          ? (row['memberIds'] as List)
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
          : const <String>[];
      final targetScopes = <GeographicScope>[];
      final targetsRaw = row['targetScopes'];
      if (targetsRaw is List) {
        for (final value in targetsRaw) {
          final target = geographicScopeFromJson(value);
          if (target != null) targetScopes.add(target);
        }
      }
      if (id == null ||
          title == null ||
          chairmanMemberId == null ||
          assignedBy == null ||
          assignedAt == null ||
          status == null ||
          distribution == null ||
          priority == null ||
          memberIds.isEmpty ||
          targetScopes.isEmpty) {
        continue;
      }

      final restored = GroupAssignment(
        id: id,
        title: title,
        chairmanMemberId: chairmanMemberId,
        memberIds: List.unmodifiable(memberIds),
        targetScopes: List.unmodifiable(targetScopes),
        distribution: distribution,
        assignedBy: assignedBy,
        assignedAt: assignedAt,
        status: status,
        priority: priority,
        instructions: _clean(row['instructions']?.toString()),
        dueAt: _date(row['dueAt']),
        submittedAt: _date(row['submittedAt']),
        submittedBy: _clean(row['submittedBy']?.toString()),
        systemIntelligenceRestricted:
            row['systemIntelligenceRestricted'] != false,
      );
      final index = _groupAssignments.indexWhere((item) => item.id == id);
      if (index < 0) {
        _groupAssignments.add(restored);
      } else {
        _groupAssignments[index] = restored;
      }
      changed = true;
    }

    for (final row in eventRows) {
      final id = row['id']?.toString();
      final assignmentId = row['assignmentId']?.toString();
      final action = row['action']?.toString();
      final actorId = row['actorId']?.toString();
      final createdAt = _date(row['createdAt']);
      if (id == null ||
          assignmentId == null ||
          action == null ||
          actorId == null ||
          createdAt == null) {
        continue;
      }
      final restored = AssignmentEvent(
        id: id,
        assignmentId: assignmentId,
        action: action,
        actorId: actorId,
        createdAt: createdAt,
        detail: row['detail']?.toString(),
      );
      final index = _events.indexWhere((item) => item.id == id);
      if (index < 0) {
        _events.add(restored);
      } else {
        _events[index] = restored;
      }
      changed = true;
    }

    for (final row in staffingRows) {
      final pollingUnitId = row['pollingUnitId']?.toString();
      final minimum = _int(row['minimumStaffing']);
      if (pollingUnitId == null || minimum == null) continue;
      _minimumStaffingByPollingUnit[pollingUnitId] =
          minimum.clamp(0, 100).toInt();
      changed = true;
    }

    if (changed) {
      _assignments.sort(
        (a, b) => b.assignedAt.compareTo(a.assignedAt),
      );
      _groupAssignments.sort(
        (a, b) => b.assignedAt.compareTo(a.assignedAt),
      );
      _events.sort(
        (a, b) => a.createdAt.compareTo(b.createdAt),
      );
      notifyListeners();
    }
  }


  List<AssignmentEvent> get events => List.unmodifiable(_events);

  GroupAssignment? groupAssignmentById(String id) {
    for (final group in _groupAssignments) {
      if (group.id == id) return group;
    }
    return null;
  }

  List<MemberAssignment> assignmentsForGroup(String groupAssignmentId) =>
      _assignments
          .where((item) => item.groupAssignmentId == groupAssignmentId)
          .toList()
        ..sort((a, b) => a.assignedAt.compareTo(b.assignedAt));

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

  Set<TgcgCapability> activeAssignmentCapabilitiesForMember(String memberId) =>
      activeAssignmentsForMember(memberId)
          .where((item) => item.confersAccess)
          .expand((item) => item.grantedCapabilities)
          .toSet();

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

  int minimumStaffingFor(
    String pollingUnitId, {
    int fallback = 1,
  }) =>
      _minimumStaffingByPollingUnit[pollingUnitId] ?? fallback;

  Future<void> setMinimumStaffing({
    required String pollingUnitId,
    required int minimumStaffing,
    required String actorId,
    GeographicScope? authorizedScope,
  }) async {
    if (minimumStaffing < 0 || minimumStaffing > 100) {
      throw ArgumentError(
        'Minimum staffing must be between 0 and 100.',
      );
    }
    final unit = _membership.geography.pollingUnit(pollingUnitId);
    if (unit == null) {
      throw ArgumentError('Unknown polling unit: $pollingUnitId');
    }
    if (authorizedScope != null &&
        !GeographyRegistry.scopeContains(authorizedScope, unit.scope)) {
      throw StateError(
        'This polling unit is outside the coordinator authorization scope.',
      );
    }

    _minimumStaffingByPollingUnit[unit.code] = minimumStaffing;
    notifyListeners();
    await _persistence.persistMutation(
      entityType: 'polling_unit_staffing_requirement',
      entityId: unit.code,
      mutationType: SyncMutationType.upsert,
      scopeKey: scopeStorageKey(unit.scope),
      payload: {
        'pollingUnitId': unit.code,
        'minimumStaffing': minimumStaffing,
        'updatedBy': actorId,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  List<PollingUnitCoverageSnapshot> coverageForScope(
    GeographicScope scope, {
    int minimumStaffing = 1,
  }) {
    final units = _membership.geography.pollingUnitsWithin(scope);
    final activeByUnit = <String, List<MemberAssignment>>{};
    for (final assignment in _assignments) {
      if (assignment.isTerminal) continue;
      final pollingUnitId = assignment.targetPollingUnitId;
      if (assignment.locationMode != AssignmentLocationMode.pollingUnit ||
          pollingUnitId == null) {
        continue;
      }
      activeByUnit
          .putIfAbsent(pollingUnitId, () => <MemberAssignment>[])
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
          minimumStaffing: minimumStaffingFor(
            unit.code,
            fallback: minimumStaffing,
          ),
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
    String? pollingUnitId,
    GeographicScope? targetScopeOverride,
    required String assignedBy,
    GeographicScope? authorizedScope,
    AssignmentPriority priority = AssignmentPriority.normal,
    String? instructions,
    DateTime? dueAt,
    List<EvidenceType> requiredEvidence = const [],
    Set<TgcgCapability> grantedCapabilities = const {},

    /// Capabilities the assigning coordinator holds through roles covering
    /// [authorizedScope]. A coordinator can never grant more than this.
    required Set<TgcgCapability> assignerCapabilities,
    String? groupAssignmentId,
    bool isGroupChairman = false,
    bool systemIntelligenceRestricted = false,
  }) async {
    final member = _membership.memberById(memberId);
    if (member == null) {
      throw ArgumentError('Unknown USESF member: $memberId');
    }

    final restricted =
        grantedCapabilities.intersection(groupAssignmentRestrictedCapabilities);
    if (groupAssignmentId != null && restricted.isNotEmpty) {
      throw StateError(
        'Internal intelligence capabilities cannot be granted to group members.',
      );
    }
    final notGrantable =
        grantedCapabilities.difference(assignmentGrantableCapabilities);
    if (notGrantable.isNotEmpty) {
      throw StateError(
        'These capabilities cannot be granted through an assignment: '
        '${notGrantable.map((item) => item.name).join(', ')}.',
      );
    }
    final notHeld = grantedCapabilities.difference(assignerCapabilities);
    if (notHeld.isNotEmpty) {
      throw StateError(
        'You cannot grant capabilities you do not hold in this area: '
        '${notHeld.map((item) => item.name).join(', ')}.',
      );
    }

    final normalizedPollingUnitId = _clean(pollingUnitId);
    final unit = normalizedPollingUnitId == null
        ? null
        : _membership.geography.pollingUnit(normalizedPollingUnitId);
    if (normalizedPollingUnitId != null && unit == null) {
      throw ArgumentError(
        'The selected polling unit is not in the canonical registry.',
      );
    }
    if (unit != null &&
        authorizedScope != null &&
        !GeographyRegistry.scopeContains(authorizedScope, unit.scope)) {
      throw StateError(
        'The selected polling unit is outside the coordinator authorization scope.',
      );
    }
    if (targetScopeOverride != null &&
        authorizedScope != null &&
        !GeographyRegistry.scopeContains(
          authorizedScope,
          targetScopeOverride,
        )) {
      throw StateError(
        'The selected assignment area is outside the coordinator authorization scope.',
      );
    }

    final memberScope = _membership.registrationScopeForMember(memberId);
    if (authorizedScope != null &&
        memberScope != null &&
        !GeographyRegistry.scopeContains(authorizedScope, memberScope)) {
      throw StateError(
        'The selected member is outside the coordinator authorization scope.',
      );
    }

    if (unit != null) {
      final sameTarget = activeAssignmentsForMember(memberId).any(
        (item) =>
            item.locationMode == AssignmentLocationMode.pollingUnit &&
            item.targetPollingUnitId == unit.code,
      );
      if (sameTarget) {
        throw StateError(
          'This member already has an active assignment for the selected polling unit.',
        );
      }
    }

    final assignmentScope = unit?.scope ??
        targetScopeOverride ??
        authorizedScope ??
        memberScope ??
        GeographicScope.kaduna;
    final locationMode = unit == null
        ? AssignmentLocationMode.none
        : AssignmentLocationMode.pollingUnit;

    final now = DateTime.now().toUtc();
    final device = _devices.deviceForMember(memberId);
    final assignment = MemberAssignment(
      id: 'ASN-${now.microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Operational Assignment' : title.trim(),
      memberId: memberId,
      targetPollingUnitId: unit?.code,
      targetScope: assignmentScope,
      locationMode: locationMode,
      assignedBy: assignedBy,
      assignedAt: now,
      status: AssignmentStatus.assigned,
      priority: priority,
      instructions: _clean(instructions),
      deviceId: device?.id,
      dueAt: dueAt?.toUtc(),
      requiredEvidence: List.unmodifiable(requiredEvidence),
      grantedCapabilities: Set.unmodifiable(grantedCapabilities),
      evidence: const [],
      groupAssignmentId: _clean(groupAssignmentId),
      isGroupChairman: isGroupChairman,
      systemIntelligenceRestricted: systemIntelligenceRestricted,
    );
    _assignments.insert(0, assignment);
    await _appendEvent(
      assignment,
      action: 'assigned',
      actorId: assignedBy,
      detail: unit == null
          ? 'Assigned to ${member.fullName} as a location-flexible assignment.'
          : 'Assigned to ${member.fullName} at ${unit.displayCode}.',
    );
    notifyListeners();
    await _persistAssignment(assignment);
    return assignment;
  }

  Future<GroupAssignment> createGroupAssignment({
    required String title,
    required List<String> memberIds,
    required List<GeographicScope> targetScopes,
    required GroupAssignmentDistribution distribution,
    required String assignedBy,
    required TgcgRole assignedByRole,
    required GeographicScope authorizedScope,
    String? chairmanMemberId,
    Map<String, GeographicScope> manualTargetsByMember = const {},
    AssignmentPriority priority = AssignmentPriority.normal,
    String? instructions,
    DateTime? dueAt,
    Set<TgcgCapability> grantedCapabilities = const {},
    required Set<TgcgCapability> assignerCapabilities,
  }) async {
    if (assignedByRole != TgcgRole.stateCoordinator ||
        authorizedScope.level != GeographyLevel.state ||
        authorizedScope.stateId != GeographicScope.kaduna.stateId) {
      throw StateError(
        'Only the Kaduna State Coordinator can create group assignments.',
      );
    }

    final uniqueMemberIds = memberIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (uniqueMemberIds.isEmpty) {
      throw StateError('Select at least one member.');
    }

    final uniqueTargets = <String, GeographicScope>{};
    for (final target in targetScopes) {
      if (!GeographyRegistry.scopeContains(authorizedScope, target)) {
        throw StateError(
          'Every group target must be inside the State Coordinator scope.',
        );
      }
      uniqueTargets[scopeStorageKey(target)] = target;
    }
    final targets = uniqueTargets.values.toList(growable: false);
    if (targets.isEmpty) {
      throw StateError('Select at least one target area.');
    }

    for (final memberId in uniqueMemberIds) {
      final member = _membership.memberById(memberId);
      if (member == null) {
        throw ArgumentError('Unknown USESF member: $memberId');
      }
      final homeScope = _membership.registrationScopeForMember(memberId);
      if (homeScope != null &&
          !GeographyRegistry.scopeContains(authorizedScope, homeScope)) {
        throw StateError(
          'Every selected member must be inside the State Coordinator scope.',
        );
      }
    }

    final restrictedGroupCapabilities =
        grantedCapabilities.intersection(groupAssignmentRestrictedCapabilities);
    if (restrictedGroupCapabilities.isNotEmpty) {
      throw StateError(
        'Internal intelligence capabilities cannot be granted to group members.',
      );
    }
    final notGrantable =
        grantedCapabilities.difference(assignmentGrantableCapabilities);
    if (notGrantable.isNotEmpty) {
      throw StateError(
        'These capabilities cannot be granted through an assignment: '
        '${notGrantable.map((item) => item.name).join(', ')}.',
      );
    }
    final notHeld = grantedCapabilities.difference(assignerCapabilities);
    if (notHeld.isNotEmpty) {
      throw StateError(
        'You cannot grant capabilities you do not hold in this area: '
        '${notHeld.map((item) => item.name).join(', ')}.',
      );
    }

    final chairman = _clean(chairmanMemberId) ??
        _automaticGroupChairman(uniqueMemberIds);
    if (!uniqueMemberIds.contains(chairman)) {
      throw StateError('The group chairman must be a selected member.');
    }

    final plannedTargets = <String, GeographicScope?>{};
    for (var index = 0; index < uniqueMemberIds.length; index++) {
      final memberId = uniqueMemberIds[index];
      GeographicScope? target;
      switch (distribution) {
        case GroupAssignmentDistribution.together:
          target = null;
          break;
        case GroupAssignmentDistribution.manual:
          target = manualTargetsByMember[memberId];
          if (target == null) {
            throw StateError(
              'Every member needs a target in manual distribution mode.',
            );
          }
          if (!uniqueTargets.containsKey(scopeStorageKey(target))) {
            throw StateError(
              'A manual member target is not part of this group assignment.',
            );
          }
          break;
        case GroupAssignmentDistribution.automatic:
          target = _automaticGroupTarget(memberId, targets, index);
          break;
      }
      plannedTargets[memberId] = target;

      if (target?.level == GeographyLevel.pollingUnit &&
          target?.pollingUnitId != null) {
        final duplicate = activeAssignmentsForMember(memberId).any(
          (item) =>
              item.locationMode == AssignmentLocationMode.pollingUnit &&
              item.targetPollingUnitId == target!.pollingUnitId,
        );
        if (duplicate) {
          throw StateError(
            'A selected member already has an active assignment for one of the target polling units.',
          );
        }
      }
    }

    final now = DateTime.now().toUtc();
    final group = GroupAssignment(
      id: 'GRP-${now.microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Group Assignment' : title.trim(),
      chairmanMemberId: chairman,
      memberIds: List.unmodifiable(uniqueMemberIds),
      targetScopes: List.unmodifiable(targets),
      distribution: distribution,
      assignedBy: assignedBy,
      assignedAt: now,
      status: GroupAssignmentStatus.assigned,
      priority: priority,
      instructions: _clean(instructions),
      dueAt: dueAt?.toUtc(),
      systemIntelligenceRestricted: true,
    );
    _groupAssignments.insert(0, group);
    await _persistGroupAssignment(group);

    for (final memberId in uniqueMemberIds) {
      final target = plannedTargets[memberId];
      final pollingUnitId =
          target?.level == GeographyLevel.pollingUnit
              ? target?.pollingUnitId
              : null;
      await createAssignment(
        title: group.title,
        memberId: memberId,
        pollingUnitId: pollingUnitId,
        targetScopeOverride: distribution == GroupAssignmentDistribution.together
            ? authorizedScope
            : target,
        assignedBy: assignedBy,
        authorizedScope: authorizedScope,
        priority: priority,
        instructions: instructions,
        dueAt: dueAt,
        grantedCapabilities: grantedCapabilities,
        assignerCapabilities: assignerCapabilities,
        groupAssignmentId: group.id,
        isGroupChairman: memberId == chairman,
        systemIntelligenceRestricted: true,
      );
    }

    notifyListeners();
    return group;
  }

  Future<GroupAssignment> submitGroupAssignment({
    required String groupAssignmentId,
    required String chairmanMemberId,
  }) async {
    final groupIndex =
        _groupAssignments.indexWhere((item) => item.id == groupAssignmentId);
    if (groupIndex < 0) {
      throw ArgumentError('Unknown group assignment: $groupAssignmentId');
    }
    final current = _groupAssignments[groupIndex];
    if (current.isTerminal) {
      throw StateError('This group assignment is already closed.');
    }
    if (current.chairmanMemberId != chairmanMemberId) {
      throw StateError(
        'Only the group chairman can submit this assignment.',
      );
    }

    final children = assignmentsForGroup(groupAssignmentId);
    MemberAssignment? chairmanAssignment;
    for (final child in children) {
      if (child.memberId == chairmanMemberId) {
        chairmanAssignment = child;
        break;
      }
    }
    if (chairmanAssignment == null) {
      throw StateError('The chairman assignment record is missing.');
    }
    if (chairmanAssignment.status == AssignmentStatus.assigned ||
        chairmanAssignment.status == AssignmentStatus.reassigned ||
        chairmanAssignment.isTerminal) {
      throw StateError(
        'The chairman must accept the assignment before submitting the group.',
      );
    }

    final now = DateTime.now().toUtc();
    for (final child in children) {
      if (child.isTerminal) continue;
      final index = _assignments.indexWhere((item) => item.id == child.id);
      if (index < 0) continue;
      final updated = child.copyWith(
        status: AssignmentStatus.completed,
        completedAt: now,
      );
      _assignments[index] = updated;
      await _appendEvent(
        updated,
        action: 'group_submitted',
        actorId: chairmanMemberId,
        detail: 'Group assignment submitted by chairman.',
      );
      await _persistAssignment(updated);
    }

    final submitted = current.copyWith(
      status: GroupAssignmentStatus.submitted,
      submittedAt: now,
      submittedBy: chairmanMemberId,
    );
    _groupAssignments[groupIndex] = submitted;
    await _persistGroupAssignment(submitted);
    notifyListeners();
    return submitted;
  }

  Future<MemberAssignment> transition({
    required String assignmentId,
    required AssignmentStatus status,
    required String actorId,
    GeographicScope? authorizedScope,
  }) async {
    final index =
        _assignments.indexWhere((item) => item.id == assignmentId);
    if (index < 0) {
      throw ArgumentError('Unknown assignment: $assignmentId');
    }
    final current = _assignments[index];
    if (current.groupAssignmentId != null) {
      throw StateError(
        'Group assignment membership cannot be changed through individual reassignment.',
      );
    }
    if (authorizedScope != null &&
        !GeographyRegistry.scopeContains(
          authorizedScope,
          current.targetScope,
        )) {
      throw StateError(
        'This assignment is outside the coordinator authorization scope.',
      );
    }
    if (current.groupAssignmentId != null &&
        status == AssignmentStatus.completed) {
      throw StateError(
        'Group assignments are submitted only by the group chairman.',
      );
    }
    if (!_canTransition(current.status, status)) {
      throw StateError(
        'Invalid assignment transition from ${current.status.name} to ${status.name}.',
      );
    }
    if (status == AssignmentStatus.completed &&
        !_hasFreshAssignmentLocation(current)) {
      throw StateError(
        'A fresh GPS fix is required before this assignment can be completed.',
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
    if (updated.groupAssignmentId != null &&
        status != AssignmentStatus.cancelled &&
        status != AssignmentStatus.declined &&
        status != AssignmentStatus.reassigned) {
      await _markGroupActive(updated.groupAssignmentId!);
    }
    notifyListeners();
    await _persistAssignment(updated);
    return updated;
  }

  Future<MemberAssignment> reassign({
    required String assignmentId,
    required String newMemberId,
    required String actorId,
    GeographicScope? authorizedScope,
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
    if (authorizedScope != null &&
        !GeographyRegistry.scopeContains(
          authorizedScope,
          current.targetScope,
        )) {
      throw StateError(
        'This assignment is outside the coordinator authorization scope.',
      );
    }
    final memberScope =
        _membership.registrationScopeForMember(newMemberId);
    if (authorizedScope != null &&
        memberScope != null &&
        !GeographyRegistry.scopeContains(authorizedScope, memberScope)) {
      throw StateError(
        'The selected member is outside the coordinator authorization scope.',
      );
    }
    final now = DateTime.now().toUtc();
    final device = _devices.deviceForMember(newMemberId);
    final updated = MemberAssignment(
      id: current.id,
      title: current.title,
      memberId: newMemberId,
      targetPollingUnitId: current.targetPollingUnitId,
      targetScope: current.targetScope,
      locationMode: current.locationMode,
      assignedBy: actorId,
      assignedAt: now,
      status: AssignmentStatus.assigned,
      priority: current.priority,
      instructions: current.instructions,
      deviceId: device?.id,
      dueAt: current.dueAt,
      requiredEvidence: current.requiredEvidence,
      grantedCapabilities: current.grantedCapabilities,
      evidence: current.evidence,
      groupAssignmentId: current.groupAssignmentId,
      isGroupChairman: current.isGroupChairman,
      systemIntelligenceRestricted: current.systemIntelligenceRestricted,
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
    final unit = current.targetPollingUnitId == null
        ? null
        : _membership.geography.pollingUnit(current.targetPollingUnitId!);
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
    final unit = current.targetPollingUnitId == null
        ? null
        : _membership.geography.pollingUnit(current.targetPollingUnitId!);
    if (current.locationMode == AssignmentLocationMode.pollingUnit &&
        (unit == null ||
            unit.operationalLatitude == null ||
            unit.operationalLongitude == null)) {
      throw StateError(
        'The assigned polling unit does not yet have an operational GPS coordinate.',
      );
    }

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
    final inside = current.locationMode == AssignmentLocationMode.none ||
        (distance != null && distance <= unit!.geofenceRadiusMeters);
    final status =
        inside ? AssignmentStatus.checkedIn : AssignmentStatus.gpsMismatch;
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
      detail: current.locationMode == AssignmentLocationMode.none
          ? 'GPS check-in captured for location-flexible assignment; accuracy ±${accuracyMeters.toStringAsFixed(1)} m.'
          : 'Distance from assigned polling unit: ${distance!.toStringAsFixed(1)} m; GPS accuracy ±${accuracyMeters.toStringAsFixed(1)} m.',
    );
    notifyListeners();
    await _persistAssignment(updated);
    return updated;
  }

  Future<MemberAssignment> attachEvidence({
    required String assignmentId,
    required EvidenceAttachment evidence,
    required String actorId,
    required String deviceId,
  }) async {
    final index =
        _assignments.indexWhere((item) => item.id == assignmentId);
    if (index < 0) {
      throw ArgumentError('Unknown assignment: $assignmentId');
    }
    final current = _assignments[index];
    if (current.deviceId != null && current.deviceId != deviceId) {
      throw StateError(
        'Evidence was captured from a device that is not bound to this assignment.',
      );
    }
    if (current.isTerminal) {
      throw StateError(
        'Evidence cannot be added after this assignment is closed.',
      );
    }
    if (!_hasFreshAssignmentLocation(current)) {
      throw StateError(
        'A fresh GPS fix is required before assignment evidence can be captured or submitted.',
      );
    }
    if (current.evidence.any((item) => item.id == evidence.id)) {
      return current;
    }

    final updated = current.copyWith(
      evidence: List.unmodifiable([...current.evidence, evidence]),
      deviceId: deviceId,
    );
    _assignments[index] = updated;

    await _persistence.persistMutation(
      entityType: 'assignment_evidence',
      entityId: evidence.id,
      mutationType: SyncMutationType.create,
      scopeKey: scopeStorageKey(updated.targetScope),
      ownerId: updated.memberId,
      payload: {
        'assignmentId': updated.id,
        'memberId': updated.memberId,
        'pollingUnitId': updated.targetPollingUnitId,
        'deviceId': deviceId,
        'evidence': evidenceToJson(evidence),
      },
    );
    await _appendEvent(
      updated,
      action: 'evidence_attached',
      actorId: actorId,
      detail:
          '${evidence.type.name} evidence ${evidence.fileName} attached from $deviceId.',
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
    if (assignment.locationMode == AssignmentLocationMode.none) {
      return AssignmentPresence.unknown;
    }
    final pollingUnitId = assignment.targetPollingUnitId;
    final unit = pollingUnitId == null
        ? null
        : _membership.geography.pollingUnit(pollingUnitId);
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
          'locationMode': assignment.locationMode.name,
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
          'grantedCapabilities':
              assignment.grantedCapabilities.map((item) => item.name).toList(),
          'evidence':
              assignment.evidence.map(evidenceToJson).toList(growable: false),
          'groupAssignmentId': assignment.groupAssignmentId,
          'isGroupChairman': assignment.isGroupChairman,
          'systemIntelligenceRestricted':
              assignment.systemIntelligenceRestricted,
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

  Future<void> _persistGroupAssignment(GroupAssignment group) =>
      _persistence.persistMutation(
        entityType: 'group_assignment',
        entityId: group.id,
        mutationType: SyncMutationType.upsert,
        scopeKey: scopeStorageKey(
          group.targetScopes.isEmpty
              ? GeographicScope.kaduna
              : group.targetScopes.first,
        ),
        ownerId: group.chairmanMemberId,
        payload: {
          'id': group.id,
          'title': group.title,
          'chairmanMemberId': group.chairmanMemberId,
          'memberIds': group.memberIds,
          'targetScopes':
              group.targetScopes.map(geographicScopeToJson).toList(),
          'distribution': group.distribution.name,
          'assignedBy': group.assignedBy,
          'assignedAt': group.assignedAt.toIso8601String(),
          'status': group.status.name,
          'priority': group.priority.name,
          'instructions': group.instructions,
          'dueAt': group.dueAt?.toIso8601String(),
          'submittedAt': group.submittedAt?.toIso8601String(),
          'submittedBy': group.submittedBy,
          'systemIntelligenceRestricted':
              group.systemIntelligenceRestricted,
        },
      );

  Future<void> _markGroupActive(String groupAssignmentId) async {
    final index =
        _groupAssignments.indexWhere((item) => item.id == groupAssignmentId);
    if (index < 0) return;
    final current = _groupAssignments[index];
    if (current.status != GroupAssignmentStatus.assigned) return;
    final updated = current.copyWith(status: GroupAssignmentStatus.active);
    _groupAssignments[index] = updated;
    await _persistGroupAssignment(updated);
  }

  String _automaticGroupChairman(List<String> memberIds) {
    for (final memberId in memberIds) {
      if (_devices.deviceForMember(memberId) != null) return memberId;
    }
    return memberIds.first;
  }

  GeographicScope _automaticGroupTarget(
    String memberId,
    List<GeographicScope> targets,
    int index,
  ) {
    final home = _membership.registrationScopeForMember(memberId);
    if (home != null) {
      for (final target in targets) {
        if (GeographyRegistry.scopeContains(target, home) ||
            GeographyRegistry.scopeContains(home, target)) {
          return target;
        }
      }
    }
    return targets[index % targets.length];
  }

  static bool _hasFreshAssignmentLocation(
    MemberAssignment assignment, {
    Duration maxAge = const Duration(minutes: 2),
  }) {
    final ping = assignment.lastLocation;
    if (ping == null) return false;
    final age = DateTime.now().toUtc().difference(ping.capturedAt).abs();
    return age <= maxAge && ping.accuracyMeters.isFinite;
  }

  static GroupAssignmentDistribution? _groupAssignmentDistribution(
    Object? value,
  ) {
    final name = value?.toString();
    for (final item in GroupAssignmentDistribution.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static GroupAssignmentStatus? _groupAssignmentStatus(Object? value) {
    final name = value?.toString();
    for (final item in GroupAssignmentStatus.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static AssignmentLocationMode? _assignmentLocationMode(Object? value) {
    final name = value?.toString();
    for (final item in AssignmentLocationMode.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static TgcgCapability? _capability(Object? value) {
    final name = value?.toString();
    for (final item in TgcgCapability.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return value == null ? null : double.tryParse(value.toString());
  }

  static int? _int(Object? value) {
    if (value is num) return value.toInt();
    return value == null ? null : int.tryParse(value.toString());
  }

  static AssignmentStatus? _assignmentStatus(Object? value) {
    final name = value?.toString();
    for (final item in AssignmentStatus.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static AssignmentPriority? _assignmentPriority(Object? value) {
    final name = value?.toString();
    for (final item in AssignmentPriority.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static EvidenceType? _evidenceType(Object? value) {
    final name = value?.toString();
    for (final item in EvidenceType.values) {
      if (item.name == name) return item;
    }
    return null;
  }

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
