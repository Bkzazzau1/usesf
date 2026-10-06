import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/field/field_operations_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/sync/sync_models.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('FieldOperationsController', () {
    test('state scope sees all prototype incidents', () {
      final store = FieldOperationsController.prototypeSeed();

      expect(store.incidentsForScope(GeographicScope.kaduna).length, 5);
      expect(store.reportsForScope(GeographicScope.kaduna).length, 3);
    });

    test('senatorial zone scope only sees matching zone records', () {
      final store = FieldOperationsController.prototypeSeed();
      const kadunaSouth = GeographicScope(
        level: GeographyLevel.senatorialDistrict,
        country: 'Nigeria',
        zoneId: 'NW',
        zoneName: 'North West',
        stateId: 'KD',
        stateName: 'Kaduna',
        senatorialDistrictId: 'SD/054/KD',
        senatorialDistrictName: 'Kaduna South',
      );

      final all = store.incidentsForScope(GeographicScope.kaduna);
      final incidents = store.incidentsForScope(kadunaSouth);

      expect(incidents, isNotEmpty);
      expect(incidents.length, lessThan(all.length));
      expect(
        incidents.every((item) => item.scope.senatorialDistrictId == 'SD/054/KD'),
        isTrue,
      );
    });

    test('incident command transition is durable, queued, and hydrated with actor provenance',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final persistence = OfflinePersistenceController(
        openDatabase: () async => InMemoryOfflineDatabase(),
      );
      await persistence.initialize();
      final store = FieldOperationsController.prototypeSeed(
        persistence: persistence,
      );
      final before = store.incidents.firstWhere((item) => item.id == 'INC-0004');
      expect(before.status, IncidentStatus.reported);

      final changed = await store.updateIncidentStatus(
        'INC-0004',
        IncidentStatus.acknowledged,
        actorId: 'STATE-COORD',
        actorRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
      );

      expect(changed, isTrue);
      final after = store.incidents.firstWhere((item) => item.id == 'INC-0004');
      expect(after.status, IncidentStatus.acknowledged);

      final history = store.statusHistoryForIncident('INC-0004');
      expect(history, hasLength(1));
      expect(history.single.fromStatus, IncidentStatus.reported);
      expect(history.single.toStatus, IncidentStatus.acknowledged);
      expect(history.single.actorId, 'STATE-COORD');
      expect(history.single.actorRole, TgcgRole.stateCoordinator);

      final mutation = persistence.outbox.lastWhere(
        (item) =>
            item.entityType == 'field_incident' &&
            item.entityId == 'INC-0004',
      );
      expect(mutation.mutationType, SyncMutationType.update);
      expect(mutation.state, SyncState.queued);

      final payload = await persistence.payloadForOutbox(mutation.id);
      expect(payload['status'], IncidentStatus.acknowledged.name);
      final rawHistory = payload['statusHistory'] as List;
      expect(rawHistory, hasLength(1));
      final event = rawHistory.single as Map;
      expect(event['actorId'], 'STATE-COORD');
      expect(event['toStatus'], IncidentStatus.acknowledged.name);

      final restored = FieldOperationsController.prototypeSeed(
        persistence: persistence,
      );
      await restored.hydrateFromOffline();

      expect(
        restored.incidents.firstWhere((item) => item.id == 'INC-0004').status,
        IncidentStatus.acknowledged,
      );
      final restoredHistory =
          restored.statusHistoryForIncident('INC-0004');
      expect(restoredHistory, hasLength(1));
      expect(restoredHistory.single.actorId, 'STATE-COORD');
    });

    test('direct status mutation outside actor scope is rejected', () async {
      const zaria = GeographicScope(
        level: GeographyLevel.lga,
        country: 'Nigeria',
        zoneId: 'NW',
        zoneName: 'North West',
        stateId: 'KD',
        stateName: 'Kaduna',
        senatorialDistrictId: 'SD/052/KD',
        senatorialDistrictName: 'Kaduna North',
        lgaId: 'KD-ZARIA',
        lgaName: 'Zaria',
      );
      final store = FieldOperationsController.prototypeSeed();
      final before = store.incidents.firstWhere((item) => item.id == 'INC-0004');

      await expectLater(
        store.updateIncidentStatus(
          'INC-0004',
          IncidentStatus.acknowledged,
          actorId: 'ZARIA-LGA-COORD',
          actorRole: TgcgRole.lgaCoordinator,
          authorizedScope: zaria,
        ),
        throwsStateError,
      );

      final after = store.incidents.firstWhere((item) => item.id == 'INC-0004');
      expect(after.status, before.status);
      expect(store.statusHistoryForIncident('INC-0004'), isEmpty);
    });
  });
}
