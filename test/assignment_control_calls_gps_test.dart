import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/meeting/operational_call_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';

void main() {
  late GeographyRegistry geography;
  late OfflinePersistenceController persistence;
  late MembershipOperationsController membership;
  late ManagedDeviceController devices;
  late AssignmentController assignments;
  late OperationalCallController calls;

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
    calls = OperationalCallController(
      membership: membership,
      assignments: assignments,
      devices: devices,
      persistence: persistence,
    );
  });

  Future<void> activateGps(
    String memberId, {
    DateTime? capturedAt,
    double latitude = 10.52,
    double longitude = 7.44,
  }) async {
    var device = devices.deviceForMember(memberId);
    if (device == null) {
      final registered = await devices.registerDevice(
        label: 'GPS test phone • $memberId',
        registeredBy: 'TEST',
      );
      device = await devices.assignToMember(
        deviceId: registered.id,
        memberId: memberId,
        assignedBy: 'TEST',
        authorizedScope: GeographicScope.kaduna,
      );
    }
    devices.recordHeartbeat(
      deviceId: device.id,
      capturedAt: capturedAt ?? DateTime.now().toUtc(),
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: 6,
      batteryPercent: 80,
      syncState: 'synced',
    );
  }

  group('Assignment Control operational calls', () {
    test('State Coordinator can call a registered Kaduna member with active GPS',
        () async {
      await activateGps('MEM-0012');
      final call = await calls.startDirectCall(
        recipientMemberId: 'MEM-0012',
        kind: OperationalCallKind.video,
        callerId: 'STATE-COORD',
        callerName: 'State Coordinator',
        callerRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
      );

      expect(call.status, OperationalCallStatus.ringing);
      expect(call.recipientMemberIds, ['MEM-0012']);
      expect(call.hasGpsForAllRecipients, isTrue);
      expect(call.recipientGps, hasLength(1));
      expect(
        call.recipientGps.single.source,
        OperationalCallGpsSource.managedDeviceHeartbeat,
      );
      expect(calls.incomingForMember('MEM-0012'), hasLength(1));
    });

    test('operational call is rejected when recipient GPS is inactive',
        () async {
      await expectLater(
        calls.startDirectCall(
          recipientMemberId: 'MEM-0003',
          kind: OperationalCallKind.audio,
          callerId: 'STATE-COORD',
          callerName: 'State Coordinator',
          callerRole: TgcgRole.stateCoordinator,
          authorizedScope: GeographicScope.kaduna,
        ),
        throwsStateError,
      );
    });

    test('GPS older than seven minutes is not active for a call', () async {
      await activateGps(
        'MEM-0003',
        capturedAt: DateTime.now().toUtc().subtract(
          const Duration(minutes: 8),
        ),
      );

      expect(calls.gpsActiveForMember('MEM-0003'), isFalse);
      await expectLater(
        calls.startDirectCall(
          recipientMemberId: 'MEM-0003',
          kind: OperationalCallKind.video,
          callerId: 'STATE-COORD',
          callerName: 'State Coordinator',
          callerRole: TgcgRole.stateCoordinator,
          authorizedScope: GeographicScope.kaduna,
        ),
        throwsStateError,
      );
    });

    test('non-State Coordinator cannot start Assignment Control calls',
        () async {
      await expectLater(
        calls.startDirectCall(
          recipientMemberId: 'MEM-0001',
          kind: OperationalCallKind.audio,
          callerId: 'LGA-COORD',
          callerName: 'LGA Coordinator',
          callerRole: TgcgRole.lgaCoordinator,
          authorizedScope: GeographicScope.kaduna,
        ),
        throwsStateError,
      );
    });

    test('member answer, GPS snapshot and end states persist', () async {
      await activateGps('MEM-0001', latitude: 10.5111, longitude: 7.4222);
      final call = await calls.startDirectCall(
        recipientMemberId: 'MEM-0001',
        kind: OperationalCallKind.video,
        callerId: 'STATE-COORD',
        callerName: 'State Coordinator',
        callerRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
        assignmentId: 'ASN-TEST',
      );

      final active = await calls.answerCall(
        callId: call.id,
        memberId: 'MEM-0001',
      );
      expect(active.status, OperationalCallStatus.active);
      expect(active.joinedMemberIds, contains('MEM-0001'));

      await calls.endCall(
        callId: call.id,
        actorId: 'STATE-COORD',
      );

      final restored = OperationalCallController(
        membership: membership,
        assignments: assignments,
        devices: devices,
        persistence: persistence,
      );
      await restored.hydrateFromOffline();
      final saved = restored.callById(call.id);
      expect(saved, isNotNull);
      expect(saved!.status, OperationalCallStatus.ended);
      expect(saved.assignmentId, 'ASN-TEST');
      expect(saved.answeredAt, isNotNull);
      expect(saved.endedAt, isNotNull);
      expect(saved.hasGpsForAllRecipients, isTrue);
      expect(saved.gpsForMember('MEM-0001')!.latitude, 10.5111);
      expect(saved.gpsForMember('MEM-0001')!.longitude, 7.4222);
    });

    test('group conference targets every selected GPS-active member',
        () async {
      await activateGps('MEM-0001');
      await activateGps('MEM-0002');
      await activateGps('MEM-0003');
      final call = await calls.startConference(
        recipientMemberIds: const [
          'MEM-0001',
          'MEM-0002',
          'MEM-0003',
        ],
        callerId: 'STATE-COORD',
        callerName: 'State Coordinator',
        callerRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
        groupAssignmentId: 'GRP-TEST',
      );

      expect(call.kind, OperationalCallKind.conference);
      expect(call.recipientMemberIds, hasLength(3));
      expect(call.recipientGps, hasLength(3));
      expect(call.hasGpsForAllRecipients, isTrue);
      expect(calls.incomingForMember('MEM-0003'), hasLength(1));
    });

    test('group conference is blocked if one member lacks active GPS',
        () async {
      await activateGps('MEM-0001');
      await activateGps('MEM-0002');

      await expectLater(
        calls.startConference(
          recipientMemberIds: const [
            'MEM-0001',
            'MEM-0002',
            'MEM-0003',
          ],
          callerId: 'STATE-COORD',
          callerName: 'State Coordinator',
          callerRole: TgcgRole.stateCoordinator,
          authorizedScope: GeographicScope.kaduna,
          groupAssignmentId: 'GRP-TEST',
        ),
        throwsStateError,
      );
    });
  });

  group('Manual polling-unit coordinates', () {
    test('manual coordinate becomes reusable polling-unit reference GPS',
        () async {
      final unit = geography.pollingUnits.firstWhere(
        (item) =>
            item.operationalLatitude == null ||
            item.operationalLongitude == null,
      );

      final updated = await membership.addManualPollingUnitCoordinate(
        pollingUnitId: unit.code,
        latitude: 10.523456,
        longitude: 7.438765,
        recordedBy: 'STATE-COORD',
        recordedByRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
      );

      expect(updated.referenceLatitude, 10.523456);
      expect(updated.referenceLongitude, 7.438765);
      expect(updated.operationalLatitude, 10.523456);
      expect(updated.operationalLongitude, 7.438765);
      expect(updated.referenceSource, contains('manual-state-coordinator'));

      final audits = await persistence.readEntities(
        entityType: 'polling_unit_coordinate_audit',
      );
      expect(audits, hasLength(1));
      expect(audits.first['pollingUnitId'], unit.code);
      expect(audits.first['recordedBy'], 'STATE-COORD');
    });

    test('manual entry never overwrites an existing operational coordinate',
        () async {
      final unit = geography.pollingUnits.firstWhere(
        (item) =>
            item.operationalLatitude == null ||
            item.operationalLongitude == null,
      );
      await membership.addManualPollingUnitCoordinate(
        pollingUnitId: unit.code,
        latitude: 10.5,
        longitude: 7.4,
        recordedBy: 'STATE-COORD',
        recordedByRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
      );

      await expectLater(
        membership.addManualPollingUnitCoordinate(
          pollingUnitId: unit.code,
          latitude: 11.0,
          longitude: 8.0,
          recordedBy: 'STATE-COORD',
          recordedByRole: TgcgRole.stateCoordinator,
          authorizedScope: GeographicScope.kaduna,
        ),
        throwsStateError,
      );

      final saved = geography.pollingUnit(unit.code)!;
      expect(saved.operationalLatitude, 10.5);
      expect(saved.operationalLongitude, 7.4);
    });

    test('non-State Coordinator cannot add manual polling-unit GPS',
        () async {
      final unit = geography.pollingUnits.firstWhere(
        (item) =>
            item.operationalLatitude == null ||
            item.operationalLongitude == null,
      );

      await expectLater(
        membership.addManualPollingUnitCoordinate(
          pollingUnitId: unit.code,
          latitude: 10.7,
          longitude: 7.7,
          recordedBy: 'LGA-COORD',
          recordedByRole: TgcgRole.lgaCoordinator,
          authorizedScope: GeographicScope.kaduna,
        ),
        throwsStateError,
      );
    });

    test('manual coordinates hydrate for later assignments', () async {
      final unit = geography.pollingUnits.firstWhere(
        (item) =>
            item.operationalLatitude == null ||
            item.operationalLongitude == null,
      );
      await membership.addManualPollingUnitCoordinate(
        pollingUnitId: unit.code,
        latitude: 10.61,
        longitude: 7.51,
        recordedBy: 'STATE-COORD',
        recordedByRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
      );

      final restoredGeography = GeographyRegistry.prototypeSeed();
      final restoredMembership =
          MembershipOperationsController.prototypeSeed(
        restoredGeography,
        persistence: persistence,
      );
      await restoredMembership.hydrateFromOffline();

      final restored = restoredGeography.pollingUnit(unit.code)!;
      expect(restored.operationalLatitude, 10.61);
      expect(restored.operationalLongitude, 7.51);
    });
  });
}
