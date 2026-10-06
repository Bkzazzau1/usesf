import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/domain/permissions.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/security/emergency_response_store.dart';
import 'package:usesf/tgcg/session.dart';
import 'package:usesf/tgcg/sync/sync_models.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Security Portal', () {
    test('security officer can only respond to dispatches', () {
      expect(
        TgcgPermissionPolicy.capabilitiesFor(TgcgRole.securityOfficer),
        {TgcgCapability.respondToDispatch},
      );
      expect(
        allowedModules(TgcgRole.securityOfficer),
        {TgcgModule.securityResponse},
      );
    });

    test('session carries the agency and clears it on sign-out', () {
      final session = TgcgSessionController()
        ..signIn(
          role: TgcgRole.securityOfficer,
          operatorName: 'Insp. Musa Bello',
          accessId: 'AP/12345',
          agencyId: 'AGENCY-POLICE',
        );

      expect(session.agencyId, 'AGENCY-POLICE');
      expect(roleLabel(session.role!), 'Security Officer');

      session.signOut();
      expect(session.agencyId, isNull);
      expect(session.isAuthenticated, isFalse);
    });

    test('officer sees only own-agency dispatches in their command area', () {
      final emergency = EmergencyResponseController.prototypeSeed(
        GovernanceOperationsController.prototypeSeed(),
      );
      final jemaa = GeographyRegistry.prototypeSeed().lga('KD-JEMAA')!.scope;

      List<String> visible(String agencyId, GeographicScope scope) => emergency
          .dispatchesForScope(scope)
          .where((item) => item.agencyId == agencyId)
          .map((item) => item.id)
          .toList();

      expect(visible('AGENCY-POLICE', jemaa), ['DSP-0002']);
      expect(visible('AGENCY-NSCDC', jemaa), ['DSP-0003']);
      expect(
        visible('AGENCY-POLICE', GeographicScope.kaduna).toSet(),
        {'DSP-0001', 'DSP-0002'},
      );
    });

    test('response updates are timestamped and audited', () async {
      final governance = GovernanceOperationsController.prototypeSeed();
      final emergency = EmergencyResponseController.prototypeSeed(governance);
      final before = governance.auditEvents.length;

      await emergency.updateStatus(
        dispatchId: 'DSP-0002',
        status: EmergencyDispatchStatus.acknowledged,
        actorId: 'AP/12345',
      );

      final updated =
          emergency.dispatches.firstWhere((item) => item.id == 'DSP-0002');
      expect(updated.status, EmergencyDispatchStatus.acknowledged);
      expect(updated.acknowledgedAt, isNotNull);
      expect(updated.lastUpdatedBy, 'AP/12345');
      expect(governance.auditEvents.length, before + 1);
    });

    test('production agencies and dispatch lifecycle survive restart', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final persistence = OfflinePersistenceController(
        openDatabase: () async => InMemoryOfflineDatabase(),
      );
      await persistence.initialize();
      final governance = GovernanceOperationsController.productionFoundation(
        persistence: persistence,
      );
      final emergency = EmergencyResponseController.productionFoundation(
        governance: governance,
        persistence: persistence,
      );

      expect(emergency.agencies, isEmpty);
      expect(emergency.dispatches, isEmpty);

      final agency = await emergency.upsertAgency(
        id: 'AGENCY-KD-POLICE',
        name: 'Kaduna Police Response Desk',
        shortName: 'Police',
        type: EmergencyAgencyType.police,
        coverage: GeographicScope.kaduna,
        commandDesk: 'Kaduna State Operations Desk',
        contactPhone: '+2348000000101',
        actorId: 'SYSTEM-ADMIN',
        actorRole: TgcgRole.stateAdministrator,
        authorizedScope: GeographicScope.kaduna,
      );
      final responder = await emergency.provisionResponder(
        agencyId: agency.id,
        serviceNumber: 'AP/REAL-001',
        displayName: 'Insp. Real Officer',
        accessCode: 'StrongAccess123!',
        responderScope: GeographicScope.kaduna,
        actorId: 'SYSTEM-ADMIN',
        actorRole: TgcgRole.stateAdministrator,
        authorizedScope: GeographicScope.kaduna,
      );
      expect(responder.serviceNumber, 'AP/REAL-001');
      expect(
        await emergency.verifyResponderCredential(
          agencyId: agency.id,
          serviceNumber: 'ap/real-001',
          accessCode: 'StrongAccess123!',
          requestedScope: GeographicScope.kaduna,
        ),
        isNotNull,
      );
      expect(
        await emergency.verifyResponderCredential(
          agencyId: agency.id,
          serviceNumber: 'AP/REAL-001',
          accessCode: 'WrongAccess123!',
          requestedScope: GeographicScope.kaduna,
        ),
        isNull,
      );

      final dispatch = await emergency.assign(
        incidentId: 'INC-REAL-001',
        agencyId: agency.id,
        scope: GeographicScope.kaduna,
        priority: EmergencyDispatchPriority.urgent,
        actorId: 'STATE-COORD',
        instructions: 'Confirm response and report status.',
      );
      await emergency.updateStatus(
        dispatchId: dispatch.id,
        status: EmergencyDispatchStatus.acknowledged,
        actorId: 'AP/REAL-001',
        actingAgencyId: agency.id,
      );

      expect(emergency.dispatches.single.acknowledgedAt, isNotNull);

      final agencyMutation = persistence.outbox.lastWhere(
        (item) => item.entityType == 'emergency_agency',
      );
      final dispatchMutations = persistence.outbox
          .where(
            (item) =>
                item.entityType == 'emergency_dispatch' &&
                item.entityId == dispatch.id,
          )
          .toList(growable: false);
      expect(agencyMutation.state, SyncState.queued);
      expect(dispatchMutations, hasLength(2));
      expect(
        dispatchMutations.every((item) => item.state == SyncState.queued),
        isTrue,
      );

      final restored = EmergencyResponseController.productionFoundation(
        governance: governance,
        persistence: persistence,
      );
      expect(restored.agencies, isEmpty);
      expect(restored.dispatches, isEmpty);

      await restored.hydrateFromOffline();

      expect(restored.agencies, hasLength(1));
      expect(restored.agencies.single.id, agency.id);
      expect(restored.agencies.single.name, 'Kaduna Police Response Desk');
      expect(restored.responders, hasLength(1));
      expect(restored.responders.single.id, responder.id);
      expect(restored.responders.single.displayName, 'Insp. Real Officer');
      expect(
        await restored.verifyResponderCredential(
          agencyId: agency.id,
          serviceNumber: 'AP/REAL-001',
          accessCode: 'StrongAccess123!',
          requestedScope: GeographicScope.kaduna,
        ),
        isNotNull,
      );
      expect(restored.dispatches, hasLength(1));
      expect(restored.dispatches.single.id, dispatch.id);
      expect(
        restored.dispatches.single.status,
        EmergencyDispatchStatus.acknowledged,
      );
      expect(restored.dispatches.single.acknowledgedAt, isNotNull);
      expect(
        restored.dispatches.any(
          (item) => const {'DSP-0001', 'DSP-0002', 'DSP-0003'}.contains(item.id),
        ),
        isFalse,
      );

      await restored.clearLocalCredentials();
      expect(
        await restored.verifyResponderCredential(
          agencyId: agency.id,
          serviceNumber: 'AP/REAL-001',
          accessCode: 'StrongAccess123!',
          requestedScope: GeographicScope.kaduna,
        ),
        isNull,
      );
    });

    test('State Coordinator cannot provision responder credentials',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final persistence = OfflinePersistenceController(
        openDatabase: () async => InMemoryOfflineDatabase(),
      );
      await persistence.initialize();
      final governance = GovernanceOperationsController.productionFoundation(
        persistence: persistence,
      );
      final emergency = EmergencyResponseController.productionFoundation(
        governance: governance,
        persistence: persistence,
      );

      final agency = await emergency.upsertAgency(
        id: 'AGENCY-KD-FRSC',
        name: 'Kaduna Road Safety Response Desk',
        shortName: 'Road Safety',
        type: EmergencyAgencyType.roadSafety,
        coverage: GeographicScope.kaduna,
        commandDesk: 'Kaduna State Operations Desk',
        contactPhone: '+2348000000103',
        actorId: 'SYSTEM-ADMIN',
        actorRole: TgcgRole.stateAdministrator,
        authorizedScope: GeographicScope.kaduna,
      );

      await expectLater(
        emergency.provisionResponder(
          agencyId: agency.id,
          serviceNumber: 'FRSC/12345',
          displayName: 'Responder Officer',
          accessCode: 'SecureAccess123!',
          responderScope: GeographicScope.kaduna,
          actorId: 'STATE-COORD',
          actorRole: TgcgRole.stateCoordinator,
          authorizedScope: GeographicScope.kaduna,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('responder credential cannot escalate beyond provisioned scope',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final persistence = OfflinePersistenceController(
        openDatabase: () async => InMemoryOfflineDatabase(),
      );
      await persistence.initialize();
      final governance = GovernanceOperationsController.productionFoundation(
        persistence: persistence,
      );
      final emergency = EmergencyResponseController.productionFoundation(
        governance: governance,
        persistence: persistence,
      );
      final geography = GeographyRegistry.prototypeSeed();
      final zaria = geography.lga('KD-ZARIA')!.scope;

      final agency = await emergency.upsertAgency(
        id: 'AGENCY-KD-NSCDC',
        name: 'Kaduna Civil Defence Response Desk',
        shortName: 'Civil Defence',
        type: EmergencyAgencyType.civilDefence,
        coverage: GeographicScope.kaduna,
        commandDesk: 'Kaduna State Operations Desk',
        contactPhone: '+2348000000102',
        actorId: 'SYSTEM-ADMIN',
        actorRole: TgcgRole.stateAdministrator,
        authorizedScope: GeographicScope.kaduna,
      );
      await emergency.provisionResponder(
        agencyId: agency.id,
        serviceNumber: 'NSCDC/45821',
        displayName: 'ASC Grace Danjuma',
        accessCode: 'ScopedAccess123!',
        responderScope: zaria,
        actorId: 'SYSTEM-ADMIN',
        actorRole: TgcgRole.stateAdministrator,
        authorizedScope: GeographicScope.kaduna,
      );

      expect(
        await emergency.verifyResponderCredential(
          agencyId: agency.id,
          serviceNumber: 'NSCDC/45821',
          accessCode: 'ScopedAccess123!',
          requestedScope: zaria,
        ),
        isNotNull,
      );
      expect(
        await emergency.verifyResponderCredential(
          agencyId: agency.id,
          serviceNumber: 'NSCDC/45821',
          accessCode: 'ScopedAccess123!',
          requestedScope: GeographicScope.kaduna,
        ),
        isNull,
      );
    });
  });
}
