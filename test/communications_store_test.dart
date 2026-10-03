import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/communications/communications_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';

void main() {
  group('CommunicationsController', () {
    test('authorized message is locally queued and audited', () {
      final governance = GovernanceOperationsController.prototypeSeed();
      final store = CommunicationsController.prototypeSeed(governance);
      final initialAuditCount = governance.auditEvents.length;

      final sent = store.sendMessage(
        roomId: 'ROOM-STATE',
        senderId: 'ADMIN-001',
        body: 'Operational test message',
        role: TgcgRole.stateAdministrator,
        userScope: GeographicScope.kaduna,
      );

      expect(sent, isTrue);
      expect(store.messages.last.body, 'Operational test message');
      expect(store.messages.last.deliveryState, MessageDeliveryState.localQueued);
      expect(governance.auditEvents.length, initialAuditCount + 1);
      expect(governance.auditEvents.first.action, 'operational_message_created');
    });

    test('read-only executive cannot send operational message', () {
      final governance = GovernanceOperationsController.prototypeSeed();
      final store = CommunicationsController.prototypeSeed(governance);
      final initialCount = store.messages.length;

      final sent = store.sendMessage(
        roomId: 'ROOM-STATE',
        senderId: 'VIEWER-001',
        body: 'Should not be accepted',
        role: TgcgRole.readOnlyExecutive,
        userScope: GeographicScope.kaduna,
      );

      expect(sent, isFalse);
      expect(store.messages.length, initialCount);
    });

    test('broadcast cannot target outside operator geographic scope', () {
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

      final sent = store.sendBroadcast(
        title: 'Outside scope',
        body: 'This state-wide broadcast should be rejected for a senatorial-zone user.',
        targetScope: GeographicScope.kaduna,
        senderId: 'KC-COORD',
        role: TgcgRole.senatorialCoordinator,
        userScope: kadunaCentral,
      );

      expect(sent, isFalse);
    });
  });
}
