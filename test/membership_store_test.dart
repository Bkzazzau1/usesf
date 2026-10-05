import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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
