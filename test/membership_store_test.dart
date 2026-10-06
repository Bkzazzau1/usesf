import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';

void main() {
  group('MembershipOperationsController', () {
    late GeographyRegistry geography;
    late MembershipOperationsController store;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
    });

    setUp(() {
      geography = GeographyRegistry.prototypeSeed();
      store = MembershipOperationsController.prototypeSeed(
        geography,
        persistence: OfflinePersistenceController(
          openDatabase: () async => InMemoryOfflineDatabase(),
        ),
      );
    });

    tearDown(() => store.dispose());

    test('production membership, devices and assignments restart cleanly',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final persistence = OfflinePersistenceController(
        openDatabase: () async => InMemoryOfflineDatabase(),
      );
      await persistence.initialize();
      final productionGeography = GeographyRegistry.prototypeSeed();
      final membership =
          MembershipOperationsController.productionFoundation(
        productionGeography,
        persistence: persistence,
      );
      final devices = ManagedDeviceController.productionFoundation(
        membership: membership,
        persistence: persistence,
      );
      final assignments = AssignmentController.productionFoundation(
        membership: membership,
        devices: devices,
        persistence: persistence,
      );

      expect(membership.members, isEmpty);
      expect(devices.devices, isEmpty);
      expect(assignments.assignments, isEmpty);
      expect(assignments.groupAssignments, isEmpty);
      expect(membership.geography.lgaCount, 23);
      expect(membership.geography.pollingUnits, isNotEmpty);

      final zaria = productionGeography.lga('KD-ZARIA')!;
      final member = await membership.createMember(
        fullName: 'Persisted Field Member',
        phoneNumber: '+2348012345678',
        registrationScope: zaria.scope,
      );
      final device = await devices.registerDevice(
        label: 'Field Device',
        registeredBy: 'STATE-COORD',
      );
      final assignedDevice = await devices.assignToMember(
        deviceId: device.id,
        memberId: member.id,
        assignedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
      );
      final assignment = await assignments.createAssignment(
        title: 'Persisted field duty',
        memberId: member.id,
        targetScopeOverride: zaria.scope,
        assignedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
        assignerCapabilities: const {},
      );

      expect(assignedDevice.assignedMemberId, member.id);
      expect(assignment.memberId, member.id);
      expect(assignment.deviceId, device.id);

      final restoredGeography = GeographyRegistry.prototypeSeed();
      final restoredMembership =
          MembershipOperationsController.productionFoundation(
        restoredGeography,
        persistence: persistence,
      );
      final restoredDevices = ManagedDeviceController.productionFoundation(
        membership: restoredMembership,
        persistence: persistence,
      );
      final restoredAssignments = AssignmentController.productionFoundation(
        membership: restoredMembership,
        devices: restoredDevices,
        persistence: persistence,
      );

      await restoredMembership.hydrateFromOffline();
      await restoredDevices.hydrateFromOffline();
      await restoredAssignments.hydrateFromOffline();

      expect(restoredMembership.members, hasLength(1));
      expect(restoredMembership.members.single.id, member.id);
      expect(restoredMembership.members.single.fullName, 'Persisted Field Member');
      expect(
        restoredMembership.members.any(
          (item) => const {
            'Amina Yusuf',
            'Samuel Terna',
            'Chinedu Okafor',
          }.contains(item.fullName),
        ),
        isFalse,
      );
      expect(restoredDevices.devices, hasLength(1));
      expect(restoredDevices.devices.single.id, device.id);
      expect(restoredDevices.devices.single.assignedMemberId, member.id);
      expect(restoredAssignments.assignments, hasLength(1));
      expect(restoredAssignments.assignments.single.id, assignment.id);
      expect(restoredAssignments.assignments.single.memberId, member.id);
      expect(restoredAssignments.assignments.single.deviceId, device.id);
      expect(restoredAssignments.groupAssignments, isEmpty);

      membership.dispose();
      devices.dispose();
      assignments.dispose();
      restoredMembership.dispose();
      restoredDevices.dispose();
      restoredAssignments.dispose();
    });

    test('creates a member without a phone number', () async {
      final before = store.members.length;
      final member = await store.createMember(
        fullName: 'Test Member',
      );

      expect(store.members.length, before + 1);
      expect(member.status, RecordStatus.submitted);
      expect(member.phoneNumber, isEmpty);
      expect(member.membershipNumber, isNotNull);
    });

    test('stores PVC VIN and prevents duplicate registration', () async {
      const vin = '90F5A1B2C3D4E5F67890';
      final member = await store.createMember(
        fullName: 'PVC Member',
        pvcVin: vin,
      );

      expect(member.pvcVin, vin);
      expect((await store.memberByPvcVin(vin))?.id, member.id);

      expect(
        () => store.createMember(
          fullName: 'Duplicate PVC Member',
          pvcVin: vin,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('password credential authenticates the member', () async {
      final member = await store.createMember(
        fullName: 'Password Member',
      );

      await store.setMemberPassword(
        memberId: member.id,
        password: 'SecurePass123!',
      );

      expect(
        await store.hasMemberPasswordCredential(member.id),
        isTrue,
      );
      expect(
        await store.verifyMemberPassword(
          memberId: member.id,
          password: 'SecurePass123!',
        ),
        isTrue,
      );
      expect(
        await store.verifyMemberPassword(
          memberId: member.id,
          password: 'WrongPassword',
        ),
        isFalse,
      );
    });

    test('verified email cannot be changed by member profile operation', () async {
      final member = await store.createMember(
        fullName: 'Verified Email Member',
        email: 'member@example.com',
        emailVerified: true,
      );

      expect(
        () => store.updateMemberContact(
          memberId: member.id,
          email: 'changed@example.com',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('identity review can block and reactivate the same member', () async {
      final member = await store.createMember(
        fullName: 'Review Member',
      );

      final blocked = await store.setIdentityReview(
        memberId: member.id,
        review: MemberIdentityReview.suspicious,
      );
      expect(blocked.isBlocked, isTrue);

      final restored = await store.setIdentityReview(
        memberId: member.id,
        review: MemberIdentityReview.verified,
      );
      expect(restored.isBlocked, isFalse);
      expect(restored.id, member.id);
    });
  });
}
