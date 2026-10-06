import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/field/field_operations_store.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/geography/kaduna_geography.dart';
import 'package:usesf/tgcg/geography/state_coverage_intelligence_page.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/meeting/operational_call_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/results/result_operations_store.dart';

void main() {
  late GeographyRegistry geography;
  late OfflinePersistenceController persistence;
  late MembershipOperationsController membership;
  late ManagedDeviceController devices;
  late AssignmentController assignments;
  late GovernanceOperationsController governance;
  late FieldOperationsController field;
  late ResultOperationsController results;
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
    assignments = AssignmentController.prototypeSeed(
      membership: membership,
      devices: devices,
      persistence: persistence,
    );
    governance = GovernanceOperationsController.prototypeSeed();
    field = FieldOperationsController.prototypeSeed(
      persistence: persistence,
    );
    results = ResultOperationsController.prototypeSeed(
      persistence: persistence,
    );
    calls = OperationalCallController(
      membership: membership,
      assignments: assignments,
      devices: devices,
      persistence: persistence,
    );
  });

  CoverageAreaSnapshot snapshot(GeographicScope scope) =>
      buildCoverageAreaSnapshot(
        scope: scope,
        registry: geography,
        assignments: assignments,
        governance: governance,
        field: field,
        results: results,
        calls: calls,
      );

  group('State Coverage Intelligence hierarchy', () {
    test('State Coordinator command view exposes all 23 LGAs directly', () {
      final children = coverageChildScopes(
        geography,
        GeographicScope.kaduna,
      );

      expect(children, hasLength(kadunaLgaCount));
      expect(children.every((item) => item.level == GeographyLevel.lga), isTrue);
    });

    test('LGA without loaded polling-unit catalogue is marked pending', () {
      final lga = geography.lgas.firstWhere(
        (item) => geography.pollingUnitsWithin(item.scope).isEmpty,
      );

      final value = snapshot(lga.scope);

      expect(value.expectedPollingUnits, 0);
      expect(value.readinessScore, isNull);
      expect(
        value.readinessState,
        CoverageReadinessState.cataloguePending,
      );
    });

    test('loaded LGA receives a measurable readiness score', () {
      final lga = geography.lgas.firstWhere(
        (item) => geography.pollingUnitsWithin(item.scope).isNotEmpty,
      );

      final value = snapshot(lga.scope);

      expect(value.expectedPollingUnits, greaterThan(0));
      expect(value.readinessScore, isNotNull);
      expect(value.readinessScore, inInclusiveRange(0, 100));
    });
  });

  group('Coordinator readiness', () {
    test('adding the exact LGA Coordinator fills the coordinator component',
        () {
      final lga = geography.lga('KD-ZARIA')!;
      final before = snapshot(lga.scope);

      governance.assignRole(
        subjectId: 'MEM-0001',
        subjectName: membership.memberById('MEM-0001')!.fullName,
        role: TgcgRole.lgaCoordinator,
        scope: lga.scope,
        assignedBy: 'STATE-COORD',
      );

      final after = snapshot(lga.scope);

      expect(before.coordinatorFilled, isFalse);
      expect(after.coordinatorFilled, isTrue);
      expect(after.coordinatorNames, isNotEmpty);
      expect(after.readinessScore!, greaterThan(before.readinessScore!));
    });

    test('statewide exception queue exposes vacant LGA coordinator roles', () {
      final exceptions = buildCoverageExceptions(
        scope: GeographicScope.kaduna,
        registry: geography,
        assignments: assignments,
        governance: governance,
        field: field,
        results: results,
        resultActivityStarted: false,
      );

      final vacancies = exceptions
          .where(
            (item) =>
                item.kind == CoverageExceptionKind.missingCoordinator,
          )
          .toList();

      expect(vacancies, hasLength(kadunaLgaCount));
      expect(vacancies.every((item) => item.scope.level == GeographyLevel.lga),
          isTrue);
    });
  });

  group('Coverage exceptions', () {
    test('staffing and coordinate gaps are surfaced from canonical PU data',
        () {
      final exceptions = buildCoverageExceptions(
        scope: GeographicScope.kaduna,
        registry: geography,
        assignments: assignments,
        governance: governance,
        field: field,
        results: results,
        resultActivityStarted: false,
      );

      expect(
        exceptions.any(
          (item) =>
              item.kind == CoverageExceptionKind.unstaffedPollingUnit,
        ),
        isTrue,
      );
      expect(
        exceptions.any(
          (item) =>
              item.kind == CoverageExceptionKind.coordinateMissing,
        ),
        isTrue,
      );
    });

    test('result-missing exceptions are phase-aware', () {
      final beforeResults = buildCoverageExceptions(
        scope: GeographicScope.kaduna,
        registry: geography,
        assignments: assignments,
        governance: governance,
        field: field,
        results: results,
        resultActivityStarted: false,
      );
      final duringResults = buildCoverageExceptions(
        scope: GeographicScope.kaduna,
        registry: geography,
        assignments: assignments,
        governance: governance,
        field: field,
        results: results,
        resultActivityStarted: true,
      );

      expect(
        beforeResults.any(
          (item) => item.kind == CoverageExceptionKind.resultMissing,
        ),
        isFalse,
      );
      expect(
        duringResults.any(
          (item) => item.kind == CoverageExceptionKind.resultMissing,
        ),
        isTrue,
      );
    });

    test('fresh managed-device GPS contributes to readiness', () {
      final lga = geography.lga('KD-ZARIA')!;
      final active = assignments
          .assignmentsForScope(lga.scope)
          .where((item) => !item.isTerminal)
          .toList();
      if (active.isEmpty) return;

      final memberId = active.first.memberId;
      var device = devices.deviceForMember(memberId);
      if (device == null) {
        throw StateError('Expected a managed device for seeded field member.');
      }
      final before = snapshot(lga.scope);

      devices.recordHeartbeat(
        deviceId: device.id,
        capturedAt: DateTime.now().toUtc(),
        latitude: 11.0855,
        longitude: 7.7199,
        accuracyMeters: 5,
        batteryPercent: 80,
        syncState: 'synced',
      );

      final after = snapshot(lga.scope);

      expect(after.gpsActiveMembers, greaterThanOrEqualTo(before.gpsActiveMembers));
      expect(after.gpsActiveMembers, greaterThan(0));
    });
  });
}
