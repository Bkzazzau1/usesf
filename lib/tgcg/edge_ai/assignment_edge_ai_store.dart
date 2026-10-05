import 'package:flutter/widgets.dart';

import '../assignments/assignment_store.dart';
import '../devices/managed_device_store.dart';
import '../domain/local_id.dart';
import '../domain/models.dart';
import '../geography/geography_registry.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

enum AssignmentEdgeAiMode {
  normal,
  verification,
  event,
  emergency,
}

enum AssignmentEdgeAiCapability {
  gpsIntegrity,
  deviceIntegrity,
  identityVerification,
  imageQuality,
  videoVerification,
  audioEventDetection,
  crowdActivity,
  ocrLocationCorroboration,
  evidenceIntegrity,
}

enum AssignmentEdgeAiSeverity {
  info,
  warning,
  critical,
}

enum AssignmentEdgeAiEventType {
  gpsMissing,
  gpsStale,
  gpsOutsideTarget,
  gpsNoGeofence,
  deviceMissing,
  deviceStale,
  batteryLow,
  syncProblem,
  identityCheck,
  imageQuality,
  videoVerification,
  audioEvent,
  crowdActivity,
  locationCorroboration,
  evidenceIntegrity,
  system,
}

enum AssignmentEdgeAiHealth {
  healthy,
  watch,
  risk,
  offline,
}

class AssignmentEdgeAiProfile {
  const AssignmentEdgeAiProfile({
    required this.assignmentId,
    required this.enabled,
    required this.mode,
    required this.capabilities,
    required this.updatedAt,
    required this.updatedBy,
  });

  final String assignmentId;
  final bool enabled;
  final AssignmentEdgeAiMode mode;
  final Set<AssignmentEdgeAiCapability> capabilities;
  final DateTime updatedAt;
  final String updatedBy;

  AssignmentEdgeAiProfile copyWith({
    bool? enabled,
    AssignmentEdgeAiMode? mode,
    Set<AssignmentEdgeAiCapability>? capabilities,
    DateTime? updatedAt,
    String? updatedBy,
  }) =>
      AssignmentEdgeAiProfile(
        assignmentId: assignmentId,
        enabled: enabled ?? this.enabled,
        mode: mode ?? this.mode,
        capabilities: capabilities ?? this.capabilities,
        updatedAt: updatedAt ?? this.updatedAt,
        updatedBy: updatedBy ?? this.updatedBy,
      );
}

class AssignmentEdgeAiEvent {
  const AssignmentEdgeAiEvent({
    required this.id,
    required this.assignmentId,
    required this.type,
    required this.severity,
    required this.createdAt,
    required this.source,
    this.confidence,
    this.summary,
    this.evidenceReference,
    this.resolvedAt,
    this.resolvedBy,
  });

  final String id;
  final String assignmentId;
  final AssignmentEdgeAiEventType type;
  final AssignmentEdgeAiSeverity severity;
  final DateTime createdAt;
  final String source;
  final double? confidence;
  final String? summary;
  final String? evidenceReference;
  final DateTime? resolvedAt;
  final String? resolvedBy;

  bool get isOpen => resolvedAt == null;

  AssignmentEdgeAiEvent copyWith({
    DateTime? resolvedAt,
    String? resolvedBy,
  }) =>
      AssignmentEdgeAiEvent(
        id: id,
        assignmentId: assignmentId,
        type: type,
        severity: severity,
        createdAt: createdAt,
        source: source,
        confidence: confidence,
        summary: summary,
        evidenceReference: evidenceReference,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        resolvedBy: resolvedBy ?? this.resolvedBy,
      );
}

class AssignmentEdgeAiFinding {
  const AssignmentEdgeAiFinding({
    required this.type,
    required this.severity,
    required this.label,
  });

  final AssignmentEdgeAiEventType type;
  final AssignmentEdgeAiSeverity severity;
  final String label;
}

class AssignmentEdgeAiSnapshot {
  const AssignmentEdgeAiSnapshot({
    required this.assignmentId,
    required this.enabled,
    required this.score,
    required this.health,
    required this.findings,
    required this.openEvents,
  });

  final String assignmentId;
  final bool enabled;
  final int score;
  final AssignmentEdgeAiHealth health;
  final List<AssignmentEdgeAiFinding> findings;
  final List<AssignmentEdgeAiEvent> openEvents;

  int get alertCount =>
      findings.where((item) => item.severity != AssignmentEdgeAiSeverity.info).length +
      openEvents.where((item) => item.severity != AssignmentEdgeAiSeverity.info).length;
}

class AssignmentEdgeAiController extends ChangeNotifier {
  AssignmentEdgeAiController({
    required AssignmentController assignments,
    required ManagedDeviceController devices,
    required OfflinePersistenceController persistence,
    List<AssignmentEdgeAiProfile> profiles = const [],
    List<AssignmentEdgeAiEvent> events = const [],
  })  : _assignments = assignments,
        _devices = devices,
        _persistence = persistence,
        _profiles = {
          for (final item in profiles) item.assignmentId: item,
        },
        _events = List<AssignmentEdgeAiEvent>.of(events);

  static const Set<AssignmentEdgeAiCapability> defaultCapabilities = {
    AssignmentEdgeAiCapability.gpsIntegrity,
    AssignmentEdgeAiCapability.deviceIntegrity,
  };

  final AssignmentController _assignments;
  final ManagedDeviceController _devices;
  final OfflinePersistenceController _persistence;
  final Map<String, AssignmentEdgeAiProfile> _profiles;
  final List<AssignmentEdgeAiEvent> _events;

  List<AssignmentEdgeAiEvent> get events =>
      List.unmodifiable(_events);

  AssignmentEdgeAiProfile profileFor(String assignmentId) =>
      _profiles[assignmentId] ??
      AssignmentEdgeAiProfile(
        assignmentId: assignmentId,
        enabled: true,
        mode: AssignmentEdgeAiMode.normal,
        capabilities: defaultCapabilities,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedBy: 'system-default',
      );

  List<AssignmentEdgeAiEvent> eventsForAssignment(
    String assignmentId, {
    bool openOnly = false,
  }) {
    final values = _events
        .where(
          (item) =>
              item.assignmentId == assignmentId &&
              (!openOnly || item.isOpen),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(values);
  }

  Future<void> hydrateFromOffline() async {
    final profileRows = await _persistence.readEntities(
      entityType: 'assignment_edge_ai_profile',
    );
    final eventRows = await _persistence.readEntities(
      entityType: 'assignment_edge_ai_event',
    );
    var changed = false;

    for (final row in profileRows) {
      final assignmentId = row['assignmentId']?.toString();
      final mode = _mode(row['mode']);
      final updatedAt = _date(row['updatedAt']);
      final updatedBy = row['updatedBy']?.toString();
      if (assignmentId == null ||
          mode == null ||
          updatedAt == null ||
          updatedBy == null) {
        continue;
      }
      final capabilities = <AssignmentEdgeAiCapability>{};
      final rawCapabilities = row['capabilities'];
      if (rawCapabilities is List) {
        for (final raw in rawCapabilities) {
          final capability = _capability(raw);
          if (capability != null) capabilities.add(capability);
        }
      }
      _profiles[assignmentId] = AssignmentEdgeAiProfile(
        assignmentId: assignmentId,
        enabled: row['enabled'] != false,
        mode: mode,
        capabilities: Set.unmodifiable(
          capabilities.isEmpty ? defaultCapabilities : capabilities,
        ),
        updatedAt: updatedAt,
        updatedBy: updatedBy,
      );
      changed = true;
    }

    for (final row in eventRows) {
      final id = row['id']?.toString();
      final assignmentId = row['assignmentId']?.toString();
      final type = _eventType(row['type']);
      final severity = _severity(row['severity']);
      final createdAt = _date(row['createdAt']);
      final source = row['source']?.toString();
      if (id == null ||
          assignmentId == null ||
          type == null ||
          severity == null ||
          createdAt == null ||
          source == null) {
        continue;
      }
      final restored = AssignmentEdgeAiEvent(
        id: id,
        assignmentId: assignmentId,
        type: type,
        severity: severity,
        createdAt: createdAt,
        source: source,
        confidence: _double(row['confidence']),
        summary: _clean(row['summary']?.toString()),
        evidenceReference:
            _clean(row['evidenceReference']?.toString()),
        resolvedAt: _date(row['resolvedAt']),
        resolvedBy: _clean(row['resolvedBy']?.toString()),
      );
      final index = _events.indexWhere((item) => item.id == id);
      if (index < 0) {
        _events.add(restored);
      } else {
        _events[index] = restored;
      }
      changed = true;
    }

    if (changed) {
      _events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }
  }

  Future<AssignmentEdgeAiProfile> updateProfile({
    required String assignmentId,
    required String updatedBy,
    required GeographicScope authorizedScope,
    bool? enabled,
    AssignmentEdgeAiMode? mode,
    Set<AssignmentEdgeAiCapability>? capabilities,
  }) async {
    final assignment = _assignments.assignmentById(assignmentId);
    if (assignment == null) {
      throw ArgumentError('Unknown assignment: $assignmentId');
    }
    if (!GeographyRegistry.scopeContains(
      authorizedScope,
      assignment.targetScope,
    )) {
      throw StateError(
        'This assignment is outside the coordinator authorization scope.',
      );
    }
    final current = profileFor(assignmentId);
    final updated = current.copyWith(
      enabled: enabled,
      mode: mode,
      capabilities: capabilities == null
          ? null
          : Set.unmodifiable(capabilities),
      updatedAt: DateTime.now().toUtc(),
      updatedBy: updatedBy,
    );
    _profiles[assignmentId] = updated;
    await _persistProfile(updated);
    notifyListeners();
    return updated;
  }

  Future<AssignmentEdgeAiEvent> recordEvent({
    required String assignmentId,
    required AssignmentEdgeAiEventType type,
    required AssignmentEdgeAiSeverity severity,
    required String source,
    double? confidence,
    String? summary,
    String? evidenceReference,
  }) async {
    if (_assignments.assignmentById(assignmentId) == null) {
      throw ArgumentError('Unknown assignment: $assignmentId');
    }
    final now = DateTime.now().toUtc();
    final event = AssignmentEdgeAiEvent(
      id: newLocalId('AI-EVT', now),
      assignmentId: assignmentId,
      type: type,
      severity: severity,
      createdAt: now,
      source: source.trim().isEmpty ? 'edge-device' : source.trim(),
      confidence: confidence?.clamp(0.0, 1.0).toDouble(),
      summary: _clean(summary),
      evidenceReference: _clean(evidenceReference),
    );
    _events.insert(0, event);
    await _persistEvent(event);
    notifyListeners();
    return event;
  }

  Future<AssignmentEdgeAiEvent> resolveEvent({
    required String eventId,
    required String resolvedBy,
    required GeographicScope authorizedScope,
  }) async {
    final index = _events.indexWhere((item) => item.id == eventId);
    if (index < 0) throw ArgumentError('Unknown AI event: $eventId');
    final current = _events[index];
    final assignment = _assignments.assignmentById(current.assignmentId);
    if (assignment == null) {
      throw StateError('The assignment for this AI event is unavailable.');
    }
    if (!GeographyRegistry.scopeContains(
      authorizedScope,
      assignment.targetScope,
    )) {
      throw StateError(
        'This AI event is outside the coordinator authorization scope.',
      );
    }
    if (!current.isOpen) return current;
    final updated = current.copyWith(
      resolvedAt: DateTime.now().toUtc(),
      resolvedBy: resolvedBy,
    );
    _events[index] = updated;
    await _persistEvent(updated);
    notifyListeners();
    return updated;
  }

  AssignmentEdgeAiSnapshot snapshotFor(
    MemberAssignment assignment, {
    DateTime? now,
  }) {
    final profile = profileFor(assignment.id);
    if (!profile.enabled) {
      return AssignmentEdgeAiSnapshot(
        assignmentId: assignment.id,
        enabled: false,
        score: 0,
        health: AssignmentEdgeAiHealth.offline,
        findings: const [],
        openEvents: eventsForAssignment(
          assignment.id,
          openOnly: true,
        ),
      );
    }

    final current = (now ?? DateTime.now()).toUtc();
    final findings = <AssignmentEdgeAiFinding>[];
    var score = 100;

    if (profile.capabilities.contains(
      AssignmentEdgeAiCapability.gpsIntegrity,
    )) {
      final presence = _assignments.presenceFor(
        assignment,
        now: current,
      );
      switch (presence) {
        case AssignmentPresence.unknown:
          findings.add(
            const AssignmentEdgeAiFinding(
              type: AssignmentEdgeAiEventType.gpsMissing,
              severity: AssignmentEdgeAiSeverity.warning,
              label: 'GPS missing',
            ),
          );
          score -= 25;
          break;
        case AssignmentPresence.stale:
          findings.add(
            const AssignmentEdgeAiFinding(
              type: AssignmentEdgeAiEventType.gpsStale,
              severity: AssignmentEdgeAiSeverity.warning,
              label: 'GPS stale',
            ),
          );
          score -= 24;
          break;
        case AssignmentPresence.outsideGeofence:
          findings.add(
            const AssignmentEdgeAiFinding(
              type: AssignmentEdgeAiEventType.gpsOutsideTarget,
              severity: AssignmentEdgeAiSeverity.critical,
              label: 'Outside geofence',
            ),
          );
          score -= 32;
          break;
        case AssignmentPresence.liveNoGeofence:
          if (assignment.locationMode == AssignmentLocationMode.pollingUnit) {
            findings.add(
              const AssignmentEdgeAiFinding(
                type: AssignmentEdgeAiEventType.gpsNoGeofence,
                severity: AssignmentEdgeAiSeverity.info,
                label: 'Live GPS • no geofence',
              ),
            );
            score -= 5;
          }
          break;
        case AssignmentPresence.insideGeofence:
          break;
      }
    }

    if (profile.capabilities.contains(
      AssignmentEdgeAiCapability.deviceIntegrity,
    )) {
      final device = assignment.deviceId == null
          ? _devices.deviceForMember(assignment.memberId)
          : _devices.deviceById(assignment.deviceId!);
      if (device == null) {
        findings.add(
          const AssignmentEdgeAiFinding(
            type: AssignmentEdgeAiEventType.deviceMissing,
            severity: AssignmentEdgeAiSeverity.warning,
            label: 'Managed device missing',
          ),
        );
        score -= 22;
      } else {
        final lastSeen = device.lastSeenAt;
        if (lastSeen == null ||
            current.difference(lastSeen.toUtc()).abs() >
                const Duration(minutes: 15)) {
          findings.add(
            const AssignmentEdgeAiFinding(
              type: AssignmentEdgeAiEventType.deviceStale,
              severity: AssignmentEdgeAiSeverity.warning,
              label: 'Device heartbeat stale',
            ),
          );
          score -= 20;
        }
        final battery = device.batteryPercent;
        if (battery != null && battery <= 15) {
          findings.add(
            AssignmentEdgeAiFinding(
              type: AssignmentEdgeAiEventType.batteryLow,
              severity: AssignmentEdgeAiSeverity.critical,
              label: 'Battery $battery%',
            ),
          );
          score -= 16;
        } else if (battery != null && battery <= 30) {
          findings.add(
            AssignmentEdgeAiFinding(
              type: AssignmentEdgeAiEventType.batteryLow,
              severity: AssignmentEdgeAiSeverity.warning,
              label: 'Battery $battery%',
            ),
          );
          score -= 8;
        }
        final sync = device.syncState?.toLowerCase();
        if (sync != null &&
            (sync.contains('fail') ||
                sync.contains('error') ||
                sync.contains('blocked'))) {
          findings.add(
            const AssignmentEdgeAiFinding(
              type: AssignmentEdgeAiEventType.syncProblem,
              severity: AssignmentEdgeAiSeverity.warning,
              label: 'Sync issue',
            ),
          );
          score -= 12;
        }
      }
    }

    final openEvents = eventsForAssignment(
      assignment.id,
      openOnly: true,
    );
    for (final event in openEvents) {
      score -= switch (event.severity) {
        AssignmentEdgeAiSeverity.info => 2,
        AssignmentEdgeAiSeverity.warning => 8,
        AssignmentEdgeAiSeverity.critical => 18,
      };
    }

    final normalized = score.clamp(0, 100).toInt();
    final health = normalized >= 80
        ? AssignmentEdgeAiHealth.healthy
        : normalized >= 60
            ? AssignmentEdgeAiHealth.watch
            : AssignmentEdgeAiHealth.risk;

    return AssignmentEdgeAiSnapshot(
      assignmentId: assignment.id,
      enabled: true,
      score: normalized,
      health: health,
      findings: List.unmodifiable(findings),
      openEvents: openEvents,
    );
  }

  Future<void> _persistProfile(AssignmentEdgeAiProfile profile) {
    final assignment = _assignments.assignmentById(profile.assignmentId);
    return _persistence.persistMutation(
      entityType: 'assignment_edge_ai_profile',
      entityId: profile.assignmentId,
      mutationType: SyncMutationType.upsert,
      scopeKey:
          assignment == null ? null : scopeStorageKey(assignment.targetScope),
      ownerId: assignment?.memberId,
      payload: {
        'assignmentId': profile.assignmentId,
        'enabled': profile.enabled,
        'mode': profile.mode.name,
        'capabilities':
            profile.capabilities.map((item) => item.name).toList(),
        'updatedAt': profile.updatedAt.toIso8601String(),
        'updatedBy': profile.updatedBy,
      },
    );
  }

  Future<void> _persistEvent(AssignmentEdgeAiEvent event) {
    final assignment = _assignments.assignmentById(event.assignmentId);
    return _persistence.persistMutation(
      entityType: 'assignment_edge_ai_event',
      entityId: event.id,
      mutationType: SyncMutationType.upsert,
      scopeKey:
          assignment == null ? null : scopeStorageKey(assignment.targetScope),
      ownerId: assignment?.memberId,
      payload: {
        'id': event.id,
        'assignmentId': event.assignmentId,
        'type': event.type.name,
        'severity': event.severity.name,
        'createdAt': event.createdAt.toIso8601String(),
        'source': event.source,
        'confidence': event.confidence,
        'summary': event.summary,
        'evidenceReference': event.evidenceReference,
        'resolvedAt': event.resolvedAt?.toIso8601String(),
        'resolvedBy': event.resolvedBy,
        'private': true,
      },
    );
  }

  static DateTime? _date(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static AssignmentEdgeAiMode? _mode(Object? value) {
    final name = value?.toString();
    for (final item in AssignmentEdgeAiMode.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static AssignmentEdgeAiCapability? _capability(Object? value) {
    final name = value?.toString();
    for (final item in AssignmentEdgeAiCapability.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static AssignmentEdgeAiSeverity? _severity(Object? value) {
    final name = value?.toString();
    for (final item in AssignmentEdgeAiSeverity.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static AssignmentEdgeAiEventType? _eventType(Object? value) {
    final name = value?.toString();
    for (final item in AssignmentEdgeAiEventType.values) {
      if (item.name == name) return item;
    }
    return null;
  }
}

class AssignmentEdgeAi
    extends InheritedNotifier<AssignmentEdgeAiController> {
  const AssignmentEdgeAi({
    super.key,
    required AssignmentEdgeAiController controller,
    required super.child,
  }) : super(notifier: controller);

  static AssignmentEdgeAiController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<AssignmentEdgeAi>();
      assert(value != null, 'AssignmentEdgeAi is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<AssignmentEdgeAi>();
    final value = element?.widget as AssignmentEdgeAi?;
    assert(value != null, 'AssignmentEdgeAi is missing above this context.');
    return value!.notifier!;
  }
}
