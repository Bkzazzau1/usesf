import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/domain/permissions.dart';
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
  });

  Future<GroupAssignment> createGroup({
    GroupAssignmentDistribution distribution =
        GroupAssignmentDistribution.automatic,
    String? chairmanMemberId = 'MEM-0001',
    Map<String, GeographicScope> manualTargets = const {},
    Set<TgcgCapability> grants = const {},
  }) =>
      assignments.createGroupAssignment(
        title: 'Mobilization team',
        memberIds: const ['MEM-0001', 'MEM-0002'],
        targetScopes: [
          geography.lga('KD-KADUNA-NORTH')!.scope,
          geography.lga('KD-ZARIA')!.scope,
        ],
        distribution: distribution,
        assignedBy: 'STATE-COORD',
        assignedByRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
        chairmanMemberId: chairmanMemberId,
        manualTargetsByMember: manualTargets,
        grantedCapabilities: grants,
        assignerCapabilities: {
          ...grants,
          TgcgCapability.viewDiscussionRoom,
          TgcgCapability.joinMeeting,
        },
      );

  group('State group assignments', () {
    test('only State Coordinator can create a group assignment', () async {
      await expectLater(
        assignments.createGroupAssignment(
          title: 'LGA team',
          memberIds: const ['MEM-0001', 'MEM-0002'],
          targetScopes: [geography.lga('KD-ZARIA')!.scope],
          distribution: GroupAssignmentDistribution.together,
          assignedBy: 'LGA-COORD',
          assignedByRole: TgcgRole.lgaCoordinator,
          authorizedScope: GeographicScope.kaduna,
          assignerCapabilities: const {},
        ),
        throwsStateError,
      );
    });

    test('automatic distribution follows selected geography when possible',
        () async {
      final group = await createGroup();

      expect(group.chairmanMemberId, 'MEM-0001');
      expect(group.targetScopes, hasLength(2));
      final children = assignments.assignmentsForGroup(group.id);
      expect(children, hasLength(2));
      expect(children.every((item) => item.systemIntelligenceRestricted), isTrue);
      expect(children.where((item) => item.isGroupChairman), hasLength(1));

      final kadunaNorth =
          children.firstWhere((item) => item.memberId == 'MEM-0001');
      final zaria = children.firstWhere((item) => item.memberId == 'MEM-0002');
      expect(kadunaNorth.targetScope.lgaId, 'KD-KADUNA-NORTH');
      expect(zaria.targetScope.lgaId, 'KD-ZARIA');
    });

    test('move-together keeps one group while member jobs stay flexible',
        () async {
      final group = await createGroup(
        distribution: GroupAssignmentDistribution.together,
        chairmanMemberId: null,
      );

      expect(group.memberIds, hasLength(2));
      expect(group.chairmanMemberId, isIn(group.memberIds));
      final children = assignments.assignmentsForGroup(group.id);
      expect(
        children.every(
          (item) =>
              item.locationMode == AssignmentLocationMode.none &&
              item.targetScope.level == GeographyLevel.state,
        ),
        isTrue,
      );
    });

    test('manual distribution uses the State Coordinator member map', () async {
      final kadunaNorth = geography.lga('KD-KADUNA-NORTH')!.scope;
      final zaria = geography.lga('KD-ZARIA')!.scope;
      final group = await createGroup(
        distribution: GroupAssignmentDistribution.manual,
        manualTargets: {
          'MEM-0001': zaria,
          'MEM-0002': kadunaNorth,
        },
      );

      final children = assignments.assignmentsForGroup(group.id);
      expect(
        children.firstWhere((item) => item.memberId == 'MEM-0001').targetScope.lgaId,
        'KD-ZARIA',
      );
      expect(
        children.firstWhere((item) => item.memberId == 'MEM-0002').targetScope.lgaId,
        'KD-KADUNA-NORTH',
      );
    });

    test('group assignments cannot expose internal media intelligence',
        () async {
      await expectLater(
        createGroup(
          grants: const {TgcgCapability.viewMediaIntelligence},
        ),
        throwsStateError,
      );
      expect(assignments.groupAssignments, isEmpty);
      expect(assignments.assignments, isEmpty);
    });

    test('only chairman submits and individual completion is blocked',
        () async {
      final group = await createGroup(
        distribution: GroupAssignmentDistribution.together,
      );
      final chairman = assignments
          .assignmentsForGroup(group.id)
          .firstWhere((item) => item.memberId == group.chairmanMemberId);

      await expectLater(
        assignments.transition(
          assignmentId: chairman.id,
          status: AssignmentStatus.completed,
          actorId: chairman.memberId,
        ),
        throwsStateError,
      );

      await assignments.transition(
        assignmentId: chairman.id,
        status: AssignmentStatus.accepted,
        actorId: chairman.memberId,
      );
      await assignments.transition(
        assignmentId: chairman.id,
        status: AssignmentStatus.enRoute,
        actorId: chairman.memberId,
      );
      await assignments.transition(
        assignmentId: chairman.id,
        status: AssignmentStatus.checkedIn,
        actorId: chairman.memberId,
      );
      await assignments.transition(
        assignmentId: chairman.id,
        status: AssignmentStatus.active,
        actorId: chairman.memberId,
      );

      await expectLater(
        assignments.submitGroupAssignment(
          groupAssignmentId: group.id,
          chairmanMemberId: 'MEM-0002',
        ),
        throwsStateError,
      );

      final submitted = await assignments.submitGroupAssignment(
        groupAssignmentId: group.id,
        chairmanMemberId: group.chairmanMemberId,
      );
      expect(submitted.status, GroupAssignmentStatus.submitted);
      expect(
        assignments
            .assignmentsForGroup(group.id)
            .every((item) => item.status == AssignmentStatus.completed),
        isTrue,
      );
    });

    test('group and child links hydrate from encrypted offline storage',
        () async {
      final group = await createGroup(
        distribution: GroupAssignmentDistribution.together,
      );

      final restored = AssignmentController(
        membership: membership,
        devices: devices,
        persistence: persistence,
      );
      await restored.hydrateFromOffline();

      expect(restored.groupAssignmentById(group.id), isNotNull);
      expect(restored.assignmentsForGroup(group.id), hasLength(2));
      expect(
        restored.assignmentsForGroup(group.id).every(
              (item) =>
                  item.groupAssignmentId == group.id &&
                  item.systemIntelligenceRestricted,
            ),
        isTrue,
      );
    });
  });
}
