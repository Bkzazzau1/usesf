import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/membership/membership_intelligence_page.dart';
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

  MemberIntelligenceSnapshot snapshot(String memberId) =>
      buildMemberIntelligenceSnapshot(
        member: membership.memberById(memberId)!,
        membership: membership,
        assignments: assignments,
        devices: devices,
        governance: governance,
        results: results,
        calls: calls,
      );

  group('Membership Intelligence identity', () {
    test('legacy system-derived verified identity is treated as ready', () {
      final member = membership.memberById('MEM-0001')!;

      expect(member.identityReview, MemberIdentityReview.pending);
      expect(member.status, RecordStatus.verified);
      expect(memberIdentityReady(member), isTrue);
      expect(
        snapshot(member.id).attentionKinds,
        isNot(contains(MemberAttentionKind.identityReview)),
      );
    });

    test('unreviewed legacy submitted identity remains in identity review', () {
      final member = membership.memberById('MEM-0003')!;

      expect(member.status, RecordStatus.submitted);
      expect(memberIdentityReady(member), isFalse);
      expect(
        snapshot(member.id).readinessState,
        MemberReadinessState.identityReview,
      );
    });

    test('State Coordinator quick-enrolled member is pending activation',
        () async {
      final member = await membership.createStateCoordinatorMember(
        fullName: 'Pending Member',
        phoneNumber: '+2348011111111',
        createdBy: 'STATE-COORD',
        createdByRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
      );

      final value = snapshot(member.id);

      expect(value.member.isPendingActivation, isTrue);
      expect(value.readinessState, MemberReadinessState.pendingActivation);
      expect(
        value.attentionKinds,
        contains(MemberAttentionKind.pendingActivation),
      );
      expect(value.attentionKinds, contains(MemberAttentionKind.noRole));
    });
  });

  group('Leadership coverage', () {
    test('seed has complete senatorial leadership and vacant LGA leadership',
        () {
      final coverage = buildLeadershipCoverage(
        membership: membership,
        governance: governance,
      );

      expect(coverage.senatorialExpected, 3);
      expect(coverage.senatorialFilled, 3);
      expect(coverage.lgaExpected, 23);
      expect(coverage.lgaFilled, 0);
    });

    test('vacancy list exposes all 23 vacant LGA coordinator posts', () {
      final vacancies = buildLeadershipVacancies(
        membership: membership,
        governance: governance,
      );

      final lgaVacancies = vacancies
          .where((item) => item.role == TgcgRole.lgaCoordinator)
          .toList(growable: false);

      expect(lgaVacancies, hasLength(23));
      expect(
        lgaVacancies.every((item) => item.scope.level == GeographyLevel.lga),
        isTrue,
      );
    });

    test('assigning exact LGA Coordinator increases leadership coverage', () {
      final lga = geography.lga('KD-ZARIA')!;
      final before = buildLeadershipCoverage(
        membership: membership,
        governance: governance,
      );

      governance.assignRole(
        subjectId: 'MEM-0001',
        subjectName: membership.memberById('MEM-0001')!.fullName,
        role: TgcgRole.lgaCoordinator,
        scope: lga.scope,
        assignedBy: 'STATE-COORD',
      );

      final after = buildLeadershipCoverage(
        membership: membership,
        governance: governance,
      );

      expect(after.lgaFilled, before.lgaFilled + 1);

      final vacancies = buildLeadershipVacancies(
        membership: membership,
        governance: governance,
      );
      expect(
        vacancies.where((item) => item.role == TgcgRole.lgaCoordinator),
        hasLength(22),
      );
    });
  });

  group('Operational readiness', () {
    test('fresh GPS moves a fully prepared active member into deployed state',
        () async {
      final member = membership.memberById('MEM-0001')!;
      final lga = geography.lga('KD-ZARIA')!;

      governance.assignRole(
        subjectId: member.id,
        subjectName: member.fullName,
        role: TgcgRole.mediaOfficer,
        scope: lga.scope,
        assignedBy: 'STATE-COORD',
      );
      await assignments.createAssignment(
        title: 'Membership intelligence GPS test',
        memberId: member.id,
        targetScopeOverride: lga.scope,
        assignedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
        assignerCapabilities: const {},
      );

      final before = snapshot(member.id);
      final device = devices.deviceForMember(member.id)!;
      devices.recordHeartbeat(
        deviceId: device.id,
        capturedAt: DateTime.now().toUtc(),
        latitude: 11.0855,
        longitude: 7.7199,
        accuracyMeters: 5,
        batteryPercent: 82,
        syncState: 'synced',
      );
      final after = snapshot(member.id);

      expect(
        before.attentionKinds,
        contains(MemberAttentionKind.gpsInactiveWhileDeployed),
      );
      expect(after.gps, isNotNull);
      expect(
        after.attentionKinds,
        isNot(contains(MemberAttentionKind.gpsInactiveWhileDeployed)),
      );
      expect(after.readinessScore, greaterThan(before.readinessScore));
      expect(after.readinessState, MemberReadinessState.deployed);
    });

    test('multiple coordinator posts are surfaced for human attention', () {
      final member = membership.memberById('MEM-0001')!;
      final lga = geography.lga('KD-ZARIA')!;
      final wardScope = geography.pollingUnits
          .firstWhere((unit) => unit.scope.lgaId == lga.id)
          .scope;
      final ward = GeographicScope(
        level: GeographyLevel.ward,
        country: wardScope.country,
        zoneId: wardScope.zoneId,
        zoneName: wardScope.zoneName,
        stateId: wardScope.stateId,
        stateName: wardScope.stateName,
        senatorialDistrictId: wardScope.senatorialDistrictId,
        senatorialDistrictName: wardScope.senatorialDistrictName,
        lgaId: wardScope.lgaId,
        lgaName: wardScope.lgaName,
        wardId: wardScope.wardId,
        wardName: wardScope.wardName,
      );

      governance.assignRole(
        subjectId: member.id,
        subjectName: member.fullName,
        role: TgcgRole.lgaCoordinator,
        scope: lga.scope,
        assignedBy: 'STATE-COORD',
      );
      governance.assignRole(
        subjectId: member.id,
        subjectName: member.fullName,
        role: TgcgRole.wardCoordinator,
        scope: ward,
        assignedBy: 'STATE-COORD',
      );

      final value = snapshot(member.id);

      expect(value.coordinatorRoleCount, 2);
      expect(
        value.attentionKinds,
        contains(MemberAttentionKind.multipleCoordinatorPosts),
      );
      expect(value.readinessState, MemberReadinessState.attention);
    });
  });
}
