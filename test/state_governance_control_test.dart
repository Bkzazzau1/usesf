import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/permissions.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/governance/state_governance_control_page.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/session.dart';

void main() {
  late GeographyRegistry geography;
  late OfflinePersistenceController persistence;
  late MembershipOperationsController membership;
  late ManagedDeviceController devices;
  late AssignmentController assignments;
  late GovernanceOperationsController governance;

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
  });

  StateGovernanceSnapshot snapshot() => buildStateGovernanceSnapshot(
        membership: membership,
        governance: governance,
        assignments: assignments,
      );

  group('State Governance Control boundary', () {
    test('State Coordinator receives Governance module without admin powers', () {
      final modules = allowedModules(TgcgRole.stateCoordinator);
      final capabilities =
          TgcgPermissionPolicy.capabilitiesFor(TgcgRole.stateCoordinator);

      expect(modules, contains(TgcgModule.governance));
      expect(capabilities, isNot(contains(TgcgCapability.viewAudit)));
      expect(capabilities, isNot(contains(TgcgCapability.manageUsers)));
      expect(
        capabilities,
        isNot(contains(TgcgCapability.manageSystemSettings)),
      );
      expect(capabilities, contains(TgcgCapability.manageRoleAssignments));
      expect(capabilities, contains(TgcgCapability.manageRoleConflicts));
    });

    test('seeded governance snapshot uses real role/sync/safeguard state', () {
      final value = snapshot();

      expect(value.activeRoles, hasLength(3));
      expect(value.distinctRoleHolders, 3);
      expect(value.leadership.senatorialFilled, 3);
      expect(value.leadership.senatorialExpected, 3);
      expect(value.leadership.lgaFilled, 0);
      expect(value.leadership.lgaExpected, 23);
      expect(value.syncQueued, 1);
      expect(value.syncFailed, 1);
      expect(value.syncConflicts, 1);
      expect(value.safeguardsEnabled, value.settings.length);
      expect(
        value.risks.any(
          (item) => item.kind == StateGovernanceRiskKind.vacantLeadership,
        ),
        isTrue,
      );
      expect(
        value.risks.any(
          (item) => item.kind == StateGovernanceRiskKind.syncFailure,
        ),
        isTrue,
      );
      expect(
        value.risks.any(
          (item) => item.kind == StateGovernanceRiskKind.syncConflict,
        ),
        isTrue,
      );
    });
  });

  group('Authority conflicts', () {
    test('blocked member with an active role becomes critical', () async {
      await membership.setIdentityReview(
        memberId: 'MEM-0005',
        review: MemberIdentityReview.suspicious,
      );

      final value = snapshot();
      final risks = value.risks.where(
        (item) =>
            item.kind == StateGovernanceRiskKind.blockedAuthority &&
            item.memberId == 'MEM-0005',
      );

      expect(risks, isNotEmpty);
      expect(
        risks.first.severity,
        StateGovernanceRiskSeverity.critical,
      );
    });

    test('duplicate active holders for one leadership post are critical', () {
      final existing = governance.roleAssignments.firstWhere(
        (item) =>
            item.active &&
            item.role == TgcgRole.senatorialCoordinator,
      );

      governance.assignRole(
        subjectId: 'MEM-0001',
        subjectName: membership.memberById('MEM-0001')!.fullName,
        role: existing.role,
        scope: existing.scope,
        assignedBy: 'STATE-COORD',
      );

      final value = snapshot();

      expect(
        value.risks.any(
          (item) =>
              item.kind ==
              StateGovernanceRiskKind.duplicateLeadershipHolder,
        ),
        isTrue,
      );
    });

    test('coordinator role at the wrong geography level is critical', () {
      governance.assignRole(
        subjectId: 'MEM-0001',
        subjectName: membership.memberById('MEM-0001')!.fullName,
        role: TgcgRole.lgaCoordinator,
        scope: GeographicScope.kaduna,
        assignedBy: 'STATE-COORD',
      );

      final value = snapshot();
      final risk = value.risks.firstWhere(
        (item) =>
            item.kind ==
            StateGovernanceRiskKind.coordinatorScopeMismatch,
      );

      expect(risk.severity, StateGovernanceRiskSeverity.critical);
      expect(risk.memberId, 'MEM-0001');
    });

    test('one member holding multiple coordinator posts is surfaced', () {
      final district = geography.senatorialDistricts.first.scope;
      final lga = geography.lgas.first.scope;

      governance.assignRole(
        subjectId: 'MEM-0001',
        subjectName: membership.memberById('MEM-0001')!.fullName,
        role: TgcgRole.senatorialCoordinator,
        scope: district,
        assignedBy: 'STATE-COORD',
      );
      governance.assignRole(
        subjectId: 'MEM-0001',
        subjectName: membership.memberById('MEM-0001')!.fullName,
        role: TgcgRole.lgaCoordinator,
        scope: lga,
        assignedBy: 'STATE-COORD',
      );

      final value = snapshot();

      expect(
        value.risks.any(
          (item) =>
              item.kind ==
                  StateGovernanceRiskKind.multipleCoordinatorPosts &&
              item.memberId == 'MEM-0001',
        ),
        isTrue,
      );
    });
  });

  group('Delegated authority and protected controls', () {
    test('active assignment-granted capabilities are accounted separately',
        () async {
      final lga = geography.lgas.first.scope;
      final assignment = await assignments.createAssignment(
        title: 'Temporary evidence review duty',
        memberId: 'MEM-0001',
        targetScopeOverride: lga,
        assignedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
        grantedCapabilities: const {
          TgcgCapability.viewEvidence,
        },
        assignerCapabilities:
            TgcgPermissionPolicy.capabilitiesFor(TgcgRole.stateCoordinator),
      );

      final value = snapshot();

      expect(
        value.temporaryAccessAssignments.map((item) => item.id),
        contains(assignment.id),
      );
      expect(
        value.temporaryAccessAssignments
            .firstWhere((item) => item.id == assignment.id)
            .grantedCapabilities,
        contains(TgcgCapability.viewEvidence),
      );
    });

    test('disabled backend safeguard is visible as critical but not a new power',
        () {
      governance.setSetting(
        settingId: 'SET-EVIDENCE-HASH',
        value: false,
        actorId: 'SYSTEM-ADMIN',
      );

      final value = snapshot();

      expect(
        value.risks.any(
          (item) =>
              item.kind == StateGovernanceRiskKind.disabledSafeguard &&
              item.severity == StateGovernanceRiskSeverity.critical,
        ),
        isTrue,
      );
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.stateCoordinator,
          TgcgCapability.manageSystemSettings,
        ),
        isFalse,
      );
    });
  });
}
