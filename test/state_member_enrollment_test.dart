import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';

void main() {
  late OfflinePersistenceController persistence;
  late MembershipOperationsController membership;
  late GovernanceOperationsController governance;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    persistence = OfflinePersistenceController(
      openDatabase: () async => InMemoryOfflineDatabase(),
    );
    await persistence.initialize();
    membership = MembershipOperationsController.prototypeSeed(
      GeographyRegistry.prototypeSeed(),
      persistence: persistence,
    );
    governance = GovernanceOperationsController.prototypeSeed();
  });

  Future<TgcgMember> quickCreate({
    String name = 'Quick Member',
    String phone = '+2348012345678',
    String? email,
  }) =>
      membership.createStateCoordinatorMember(
        fullName: name,
        phoneNumber: phone,
        email: email,
        createdBy: 'STATE-COORD',
        createdByRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
      );

  group('State Coordinator quick member enrolment', () {
    test('creates pending member without PVC, PU or password', () async {
      final member = await quickCreate();

      expect(member.fullName, 'Quick Member');
      expect(member.phoneNumber, '+2348012345678');
      expect(member.pvcVin, isNull);
      expect(member.accountStatus, MemberAccountStatus.pendingActivation);
      expect(
        membership.homePollingUnitForMember(member.id),
        isNull,
      );
      expect(
        membership.registrationScopeForMember(member.id),
        GeographicScope.kaduna,
      );
      expect(
        await membership.hasMemberPasswordCredential(member.id),
        isFalse,
      );
    });

    test('requires phone or email but not both', () async {
      await expectLater(
        membership.createStateCoordinatorMember(
          fullName: 'No Contact',
          createdBy: 'STATE-COORD',
          createdByRole: TgcgRole.stateCoordinator,
          authorizedScope: GeographicScope.kaduna,
        ),
        throwsArgumentError,
      );

      final emailOnly = await quickCreate(
        name: 'Email Only',
        phone: '',
        email: 'email.only@example.com',
      );
      expect(emailOnly.phoneNumber, isEmpty);
      expect(emailOnly.email, 'email.only@example.com');
    });

    test('rejects duplicate coordinator contacts', () async {
      await quickCreate(
        name: 'First Contact',
        email: 'first.contact@example.com',
      );

      await expectLater(
        quickCreate(
          name: 'Duplicate Phone',
          email: 'different@example.com',
        ),
        throwsStateError,
      );

      await expectLater(
        quickCreate(
          name: 'Duplicate Email',
          phone: '+2348099999999',
          email: 'FIRST.CONTACT@example.com',
        ),
        throwsStateError,
      );
    });

    test('rejects quick enrolment outside State Coordinator authority',
        () async {
      await expectLater(
        membership.createStateCoordinatorMember(
          fullName: 'Wrong Authority',
          phoneNumber: '+2348088888888',
          createdBy: 'LGA-COORD',
          createdByRole: TgcgRole.lgaCoordinator,
          authorizedScope: GeographicScope.kaduna,
        ),
        throwsStateError,
      );
    });

    test('role can be assigned before account activation', () async {
      final member = await quickCreate(
        name: 'Pending Role Member',
        phone: '+2348077777777',
      );

      final role = await governance.assignRole(
        subjectId: member.id,
        subjectName: member.fullName,
        role: TgcgRole.mediaOfficer,
        scope: GeographicScope.kaduna,
        assignedBy: 'STATE-COORD',
        actorRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
      );

      expect(member.isPendingActivation, isTrue);
      expect(role.active, isTrue);
      expect(
        governance.activeRolesForMember(member.id).single.role,
        TgcgRole.mediaOfficer,
      );
    });

    test('setting first password activates same permanent identity', () async {
      final member = await quickCreate(
        name: 'Activate Me',
        phone: '+2348066666666',
      );

      await membership.setMemberPassword(
        memberId: member.id,
        password: 'StrongPassword123',
      );

      final activated = membership.memberById(member.id)!;
      expect(activated.id, member.id);
      expect(activated.membershipNumber, member.membershipNumber);
      expect(activated.accountStatus, MemberAccountStatus.active);
      expect(
        await membership.verifyMemberPassword(
          memberId: member.id,
          password: 'StrongPassword123',
        ),
        isTrue,
      );
    });

    test('identity verification does not bypass pending activation', () async {
      final member = await quickCreate(
        name: 'Pending Review',
        phone: '+2348055555555',
      );

      final reviewed = await membership.setIdentityReview(
        memberId: member.id,
        review: MemberIdentityReview.verified,
      );

      expect(
        reviewed.accountStatus,
        MemberAccountStatus.pendingActivation,
      );
    });

    test('suspicious review blocks pending member without activating it',
        () async {
      final member = await quickCreate(
        name: 'Review Lifecycle',
        phone: '+2348033333333',
      );

      final suspicious = await membership.setIdentityReview(
        memberId: member.id,
        review: MemberIdentityReview.suspicious,
      );
      expect(suspicious.isBlocked, isTrue);
      expect(
        suspicious.accountStatus,
        MemberAccountStatus.pendingActivation,
      );

      final cleared = await membership.setIdentityReview(
        memberId: member.id,
        review: MemberIdentityReview.verified,
      );
      expect(cleared.isBlocked, isFalse);
      expect(
        cleared.accountStatus,
        MemberAccountStatus.pendingActivation,
      );
      expect(
        await membership.hasMemberPasswordCredential(member.id),
        isFalse,
      );
    });

    test('pending activation survives offline hydration', () async {
      final member = await quickCreate(
        name: 'Persisted Pending',
        phone: '+2348044444444',
      );

      final restored = MembershipOperationsController.prototypeSeed(
        GeographyRegistry.prototypeSeed(),
        persistence: persistence,
      );
      await restored.hydrateFromOffline();

      final hydrated = restored.memberById(member.id)!;
      expect(
        hydrated.accountStatus,
        MemberAccountStatus.pendingActivation,
      );
      expect(hydrated.pvcVin, isNull);
      expect(restored.homePollingUnitForMember(member.id), isNull);
    });
  });
}
