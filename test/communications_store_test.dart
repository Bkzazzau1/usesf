import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/communications/communications_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('CommunicationsController', () {
    test('production foundation starts clean and hydrates durable records',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final persistence = OfflinePersistenceController(
        openDatabase: () async => InMemoryOfflineDatabase(),
      );
      await persistence.initialize();
      final governance = GovernanceOperationsController.productionFoundation(
        persistence: persistence,
      );
      final store = CommunicationsController.productionFoundation(
        governance: governance,
        persistence: persistence,
      );

      expect(store.rooms, isNotEmpty);
      expect(store.messages, isEmpty);
      expect(store.broadcasts, isEmpty);

      final messageQueued = await store.sendMessage(
        roomId: 'ROOM-STATE',
        senderId: 'ADMIN-001',
        body: 'Durable operational message',
        role: TgcgRole.stateAdministrator,
        userScope: GeographicScope.kaduna,
      );
      final broadcastQueued = await store.sendBroadcast(
        title: 'Durable notice',
        body: 'Persist this command broadcast.',
        targetScope: GeographicScope.kaduna,
        senderId: 'ADMIN-001',
        role: TgcgRole.stateAdministrator,
        userScope: GeographicScope.kaduna,
      );

      expect(messageQueued, isTrue);
      expect(broadcastQueued, isTrue);
      expect(store.messages.single.deliveryState,
          MessageDeliveryState.localQueued);
      expect(store.broadcasts.single.deliveryState,
          BroadcastDeliveryState.queued);

      final messageMutation = persistence.outbox.lastWhere(
        (item) => item.entityType == 'communication_message',
      );
      final broadcastMutation = persistence.outbox.lastWhere(
        (item) => item.entityType == 'operational_broadcast',
      );
      expect(messageMutation.state, SyncState.queued);
      expect(broadcastMutation.state, SyncState.queued);

      final restored = CommunicationsController.productionFoundation(
        governance: governance,
        persistence: persistence,
      );
      expect(restored.messages, isEmpty);
      expect(restored.broadcasts, isEmpty);

      await restored.hydrateFromOffline();

      expect(restored.messages, hasLength(1));
      expect(restored.broadcasts, hasLength(1));
      expect(restored.messages.single.body, 'Durable operational message');
      expect(restored.messages.single.deliveryState,
          MessageDeliveryState.localQueued);
      expect(restored.broadcasts.single.title, 'Durable notice');
      expect(restored.broadcasts.single.deliveryState,
          BroadcastDeliveryState.queued);
      expect(
        restored.messages.any(
          (item) => const {
            'MSG-0002',
            'MSG-0003',
            'MSG-0004',
            'MSG-0005',
            'MSG-0006',
          }.contains(item.id),
        ),
        isFalse,
      );
    });

    test('authorized message is locally queued and audited', () async {
      final governance = GovernanceOperationsController.prototypeSeed();
      final store = CommunicationsController.prototypeSeed(governance);
      final initialAuditCount = governance.auditEvents.length;

      final sent = await store.sendMessage(
        roomId: 'ROOM-STATE',
        senderId: 'ADMIN-001',
        body: 'Operational test message',
        role: TgcgRole.stateAdministrator,
        userScope: GeographicScope.kaduna,
      );

      expect(sent, isTrue);
      expect(store.messages.last.body, 'Operational test message');
      expect(
        store.messages.last.deliveryState,
        MessageDeliveryState.localQueued,
      );
      expect(governance.auditEvents.length, initialAuditCount + 1);
      expect(governance.auditEvents.first.action, 'operational_message_created');
    });

    test('read-only executive cannot send operational message', () async {
      final governance = GovernanceOperationsController.prototypeSeed();
      final store = CommunicationsController.prototypeSeed(governance);
      final initialCount = store.messages.length;

      final sent = await store.sendMessage(
        roomId: 'ROOM-STATE',
        senderId: 'VIEWER-001',
        body: 'Should not be accepted',
        role: TgcgRole.readOnlyExecutive,
        userScope: GeographicScope.kaduna,
      );

      expect(sent, isFalse);
      expect(store.messages.length, initialCount);
    });

    test('broadcast cannot target outside operator geographic scope', () async {
      final governance = GovernanceOperationsController.prototypeSeed();
      final store = CommunicationsController.prototypeSeed(governance);
      const kadunaCentral = GeographicScope(
        level: GeographyLevel.senatorialDistrict,
        country: 'Nigeria',
        zoneId: 'NW',
        zoneName: 'North West',
        stateId: 'KD',
        stateName: 'Kaduna',
        senatorialDistrictId: 'SD/053/KD',
        senatorialDistrictName: 'Kaduna Central',
      );

      final sent = await store.sendBroadcast(
        title: 'Outside scope',
        body:
            'This state-wide broadcast should be rejected for a senatorial-zone user.',
        targetScope: GeographicScope.kaduna,
        senderId: 'KC-COORD',
        role: TgcgRole.senatorialCoordinator,
        userScope: kadunaCentral,
      );

      expect(sent, isFalse);
    });
  });
}
