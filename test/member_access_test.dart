import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/access/effective_member_access.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/domain/permissions.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';

void main() {
  // MEM-0001 has no seeded roles or assignments.
  const memberId = 'MEM-0001';

  late GeographyRegistry geography;
  late GovernanceOperationsController governance;
  late AssignmentController assignments;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUp(() {
    geography = GeographyRegistry.prototypeSeed();
    final persistence = OfflinePersistenceController(
      openDatabase: () async => InMemoryOfflineDatabase(),
    );
    final membership = MembershipOperationsController.prototypeSeed(
      geography,
      persistence: persistence,
    );
    final devices = ManagedDeviceController.prototypeSeed(
      membership: membership,
      persistence: persistence,
    );
    governance = GovernanceOperationsController.prototypeSeed();
    assignments = AssignmentController(
      membership: membership,
      devices: devices,
      persistence: persistence,
    );
  });

  EffectiveMemberAccess access() => EffectiveMemberAccess.resolve(
        memberId: memberId,
        governance: governance,
        assignments: assignments,
      );

  Future<MemberAssignment> grantDiscussion() => assignments.createAssignment(
        title: 'Forum moderation duty',
        memberId: memberId,
        assignedBy: 'COORD-1',
        authorizedScope: GeographicScope.kaduna,
        grantedCapabilities: const {TgcgCapability.viewDiscussionRoom},
        assignerCapabilities: const {TgcgCapability.viewDiscussionRoom},
      );

  group('Effective member access', () {
    test('membership alone grants no operational access', () {
      expect(access().hasOperationalAccess, isFalse);
      expect(access().capabilities, isEmpty);
    });

    test('several roles combine automatically, each within its own scope', () {
      final unit = geography.pollingUnit('KD-KN-W01-PU001')!.scope;
      final otherUnit = geography.pollingUnit('KD-ZA-W01-PU004')!.scope;
      final kadunaNorthLga = geography.lga('KD-KADUNA-NORTH')!.scope;
      governance.assignRole(
        subjectId: memberId,
        subjectName: 'Amina Yusuf',
        role: TgcgRole.pollingUnitAgent,
        scope: unit,
        assignedBy: 'COORD-1',
      );
      governance.assignRole(
        subjectId: memberId,
        subjectName: 'Amina Yusuf',
        role: TgcgRole.mediaOfficer,
        scope: kadunaNorthLga,
        assignedBy: 'COORD-1',
      );

      final resolved = access();
      expect(resolved.allows(TgcgCapability.submitElectionResult, targetScope: unit), isTrue);
      expect(resolved.allows(TgcgCapability.viewMediaIntelligence, targetScope: unit), isTrue);
      expect(
        resolved.allows(TgcgCapability.submitElectionResult, targetScope: otherUnit),
        isFalse,
      );
    });

    test('several active assignments are allowed and their grants combine', () async {
      await grantDiscussion();
      await assignments.createAssignment(
        title: 'Meeting support',
        memberId: memberId,
        assignedBy: 'COORD-1',
        authorizedScope: GeographicScope.kaduna,
        grantedCapabilities: const {TgcgCapability.joinMeeting},
        assignerCapabilities: const {TgcgCapability.joinMeeting},
      );

      expect(assignments.activeAssignmentsForMember(memberId), hasLength(2));
      expect(
        access().capabilities,
        containsAll({TgcgCapability.viewDiscussionRoom, TgcgCapability.joinMeeting}),
      );
    });

    test('assignment-only access disappears when the assignment is cancelled', () async {
      final assignment = await grantDiscussion();
      expect(access().allows(TgcgCapability.viewDiscussionRoom), isTrue);

      await assignments.transition(
        assignmentId: assignment.id,
        status: AssignmentStatus.cancelled,
        actorId: 'COORD-1',
      );

      expect(access().allows(TgcgCapability.viewDiscussionRoom), isFalse);
      expect(access().hasOperationalAccess, isFalse);
    });

    test('a reassigned assignment no longer grants access to its holder', () async {
      final assignment = await grantDiscussion();
      await assignments.transition(
        assignmentId: assignment.id,
        status: AssignmentStatus.accepted,
        actorId: memberId,
      );
      await assignments.transition(
        assignmentId: assignment.id,
        status: AssignmentStatus.reassigned,
        actorId: 'COORD-1',
      );

      expect(access().allows(TgcgCapability.viewDiscussionRoom), isFalse);
    });
  });

  group('Assignment capability grants', () {
    test('a coordinator cannot grant a capability they do not hold', () {
      expect(
        () => assignments.createAssignment(
          title: 'Media duty',
          memberId: memberId,
          assignedBy: 'COORD-1',
          authorizedScope: GeographicScope.kaduna,
          grantedCapabilities: const {TgcgCapability.viewMediaIntelligence},
          assignerCapabilities: const {TgcgCapability.viewDiscussionRoom},
        ),
        throwsStateError,
      );
    });

    test('role-only capabilities can never be granted by assignment', () {
      expect(
        () => assignments.createAssignment(
          title: 'Verification duty',
          memberId: memberId,
          assignedBy: 'COORD-1',
          authorizedScope: GeographicScope.kaduna,
          grantedCapabilities: const {TgcgCapability.verifyElectionResult},
          assignerCapabilities: const {TgcgCapability.verifyElectionResult},
        ),
        throwsStateError,
      );
    });
  });
}
