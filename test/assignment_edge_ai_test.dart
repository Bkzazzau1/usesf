import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/edge_ai/assignment_edge_ai_store.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';

void main() {
  late GeographyRegistry geography;
  late OfflinePersistenceController persistence;
  late MembershipOperationsController membership;
  late ManagedDeviceController devices;
  late AssignmentController assignments;
  late AssignmentEdgeAiController edgeAi;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    geography = GeographyRegistry.prototypeSeed();
    persistence = OfflinePersistenceController(
      openDatabase: () async => InMemoryOfflineDatabase(),
    );
    await persistence.initialize();
    membership = MembershipOperationsController.prototypeSeed(
      geography,
      persistence: persistence,
    );
    devices = ManagedDeviceController.prototypeSeed(
      membership: membership,
      persistence: persistence,
    );
    assignments = AssignmentController(
      membership: membership,
      devices: devices,
      persistence: persistence,
    );
    edgeAi = AssignmentEdgeAiController(
      assignments: assignments,
      devices: devices,
      persistence: persistence,
    );
  });

  Future<MemberAssignment> createAssignment() =>
      assignments.createAssignment(
        title: 'Edge AI duty',
        memberId: 'MEM-0001',
        assignedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
        assignerCapabilities: const {},
      );

  group('Assignment Edge AI', () {
    test('default foundation enables only implemented detectors', () async {
      final assignment = await createAssignment();
      final profile = edgeAi.profileFor(assignment.id);

      expect(profile.enabled, isTrue);
      expect(
        profile.capabilities,
        {
          AssignmentEdgeAiCapability.gpsIntegrity,
          AssignmentEdgeAiCapability.deviceIntegrity,
        },
      );
      expect(
        profile.capabilities,
        isNot(contains(AssignmentEdgeAiCapability.audioEventDetection)),
      );
    });

    test('missing telemetry lowers assignment health', () async {
      final assignment = await createAssignment();
      final snapshot = edgeAi.snapshotFor(
        assignment,
        now: DateTime.utc(2026, 10, 5, 12),
      );

      expect(snapshot.health, AssignmentEdgeAiHealth.risk);
      expect(snapshot.score, lessThan(60));
      expect(
        snapshot.findings.map((item) => item.type),
        contains(AssignmentEdgeAiEventType.gpsMissing),
      );
      expect(
        snapshot.findings.map((item) => item.type),
        contains(AssignmentEdgeAiEventType.deviceStale),
      );
    });

    test('fresh GPS and device heartbeat restore healthy score', () async {
      final assignment = await createAssignment();
      final deviceId = assignment.deviceId!;
      final now = DateTime.utc(2026, 10, 5, 12);

      assignments.recordLocationHeartbeat(
        assignmentId: assignment.id,
        deviceId: deviceId,
        latitude: 10.52,
        longitude: 7.44,
        accuracyMeters: 8,
        capturedAt: now,
        batteryPercent: 82,
        appVersion: '0.1.0',
        syncState: 'synced',
      );

      final updated = assignments.assignmentById(assignment.id)!;
      final snapshot = edgeAi.snapshotFor(updated, now: now);

      expect(snapshot.health, AssignmentEdgeAiHealth.healthy);
      expect(snapshot.score, 100);
      expect(snapshot.findings, isEmpty);
    });

    test('critical private AI event changes health and persists', () async {
      final assignment = await createAssignment();
      final event = await edgeAi.recordEvent(
        assignmentId: assignment.id,
        type: AssignmentEdgeAiEventType.audioEvent,
        severity: AssignmentEdgeAiSeverity.critical,
        source: 'edge-audio',
        confidence: .93,
        summary: 'High-energy acoustic event',
        evidenceReference: 'local://audio/event-1',
      );

      final snapshot = edgeAi.snapshotFor(assignment);
      expect(snapshot.openEvents, contains(event));
      expect(snapshot.score, lessThan(100));

      final restored = AssignmentEdgeAiController(
        assignments: assignments,
        devices: devices,
        persistence: persistence,
      );
      await restored.hydrateFromOffline();

      final saved = restored.eventsForAssignment(assignment.id);
      expect(saved, hasLength(1));
      expect(saved.first.type, AssignmentEdgeAiEventType.audioEvent);
      expect(saved.first.confidence, .93);
      expect(saved.first.evidenceReference, 'local://audio/event-1');
    });

    test('AI profile and resolved events hydrate from offline storage',
        () async {
      final assignment = await createAssignment();
      await edgeAi.updateProfile(
        assignmentId: assignment.id,
        updatedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
        mode: AssignmentEdgeAiMode.event,
        capabilities: const {
          AssignmentEdgeAiCapability.gpsIntegrity,
        },
      );
      final event = await edgeAi.recordEvent(
        assignmentId: assignment.id,
        type: AssignmentEdgeAiEventType.gpsStale,
        severity: AssignmentEdgeAiSeverity.warning,
        source: 'edge-sentinel',
      );
      await edgeAi.resolveEvent(
        eventId: event.id,
        resolvedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
      );

      final restored = AssignmentEdgeAiController(
        assignments: assignments,
        devices: devices,
        persistence: persistence,
      );
      await restored.hydrateFromOffline();

      final profile = restored.profileFor(assignment.id);
      expect(profile.mode, AssignmentEdgeAiMode.event);
      expect(
        profile.capabilities,
        {AssignmentEdgeAiCapability.gpsIntegrity},
      );
      final saved = restored.eventsForAssignment(assignment.id).single;
      expect(saved.isOpen, isFalse);
      expect(saved.resolvedBy, 'STATE-COORD');
      expect(saved.resolvedAt, isNotNull);
    });

    test('AI profile changes are rejected outside coordinator scope',
        () async {
      final assignment = await createAssignment();
      final zaria = geography.lga('KD-ZARIA')!.scope;

      await expectLater(
        edgeAi.updateProfile(
          assignmentId: assignment.id,
          updatedBy: 'LGA-COORD',
          authorizedScope: zaria,
          mode: AssignmentEdgeAiMode.event,
        ),
        throwsStateError,
      );
    });

    test('disabling Edge AI produces offline health state', () async {
      final assignment = await createAssignment();
      await edgeAi.updateProfile(
        assignmentId: assignment.id,
        updatedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
        enabled: false,
      );

      final snapshot = edgeAi.snapshotFor(assignment);
      expect(snapshot.enabled, isFalse);
      expect(snapshot.health, AssignmentEdgeAiHealth.offline);
      expect(snapshot.score, 0);
    });
  });
}
