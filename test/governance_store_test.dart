import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/sync/sync_models.dart';

void main() {
  late OfflinePersistenceController persistence;
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
    governance = GovernanceOperationsController.productionFoundation(
      persistence: persistence,
    );
  });

  group('GovernanceOperationsController', () {
    test('durable outbox retry uses the authoritative persistence queue',
        () async {
      final receipt = await persistence.persistMutation(
        entityType: 'field_report',
        entityId: 'RPT-TEST',
        mutationType: SyncMutationType.create,
        payload: const {'id': 'RPT-TEST'},
      );
      await persistence.markFailed(receipt.outbox.id, 'offline');

      await governance.queueForRetry(
        receipt.outbox.id,
        actorId: 'ADMIN-001',
        actorRole: TgcgRole.stateAdministrator,
        authorizedScope: GeographicScope.kaduna,
      );

      final updated =
          governance.outbox.firstWhere((item) => item.id == receipt.outbox.id);
      expect(updated.state, SyncState.queued);
      expect(updated.lastError, isNull);
      expect(governance.auditEvents.first.action, 'sync_retry_queued');
    });

    test('protected setting persists and hydrates', () async {
      final setting = governance.settings.first;

      await governance.setSetting(
        settingId: setting.id,
        value: !setting.value,
        actorId: 'ADMIN-001',
        actorRole: TgcgRole.stateAdministrator,
        authorizedScope: GeographicScope.kaduna,
      );

      final restored = GovernanceOperationsController.productionFoundation(
        persistence: persistence,
      );
      await restored.hydrateFromOffline();

      final updated =
          restored.settings.firstWhere((item) => item.id == setting.id);
      expect(updated.value, !setting.value);
      expect(updated.updatedBy, 'ADMIN-001');
      expect(
        restored.auditEvents.any(
          (item) => item.action == 'system_setting_changed',
        ),
        isTrue,
      );
      restored.dispose();
    });

    test('role grant persists and hydrates with scope provenance', () async {
      const scope = GeographicScope(
        level: GeographyLevel.lga,
        country: 'Nigeria',
        zoneId: 'NW',
        stateId: 'KD',
        stateName: 'Kaduna',
        lgaId: 'KD-ZARIA',
        lgaName: 'Zaria',
      );

      final role = await governance.assignRole(
        subjectId: 'MEM-TEST',
        subjectName: 'Test Member',
        role: TgcgRole.lgaCoordinator,
        scope: scope,
        assignedBy: 'STATE-COORD',
        actorRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
      );

      final restored = GovernanceOperationsController.productionFoundation(
        persistence: persistence,
      );
      await restored.hydrateFromOffline();

      final hydrated =
          restored.roleAssignments.firstWhere((item) => item.id == role.id);
      expect(hydrated.subjectId, 'MEM-TEST');
      expect(hydrated.role, TgcgRole.lgaCoordinator);
      expect(hydrated.scope.lgaId, 'KD-ZARIA');
      expect(hydrated.active, isTrue);
      restored.dispose();
    });

    test('role mutation rejects authority outside actor scope', () async {
      const zaria = GeographicScope(
        level: GeographyLevel.lga,
        country: 'Nigeria',
        zoneId: 'NW',
        stateId: 'KD',
        stateName: 'Kaduna',
        lgaId: 'KD-ZARIA',
        lgaName: 'Zaria',
      );
      const kadunaNorth = GeographicScope(
        level: GeographyLevel.lga,
        country: 'Nigeria',
        zoneId: 'NW',
        stateId: 'KD',
        stateName: 'Kaduna',
        lgaId: 'KD-KADUNA-NORTH',
        lgaName: 'Kaduna North',
      );

      await expectLater(
        governance.assignRole(
          subjectId: 'MEM-TEST',
          subjectName: 'Test Member',
          role: TgcgRole.wardCoordinator,
          scope: kadunaNorth,
          assignedBy: 'LGA-COORD',
          actorRole: TgcgRole.lgaCoordinator,
          authorizedScope: zaria,
        ),
        throwsStateError,
      );
      expect(governance.roleAssignments, isEmpty);
    });
  });
}
