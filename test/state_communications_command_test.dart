import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/communications/bulk_communications_store.dart';
import 'package:usesf/tgcg/communications/communications_store.dart';
import 'package:usesf/tgcg/communications/state_communications_command_page.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/meeting/operational_call_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';

void main() {
  late GeographyRegistry geography;
  late OfflinePersistenceController persistence;
  late MembershipOperationsController membership;
  late ManagedDeviceController devices;
  late GovernanceOperationsController governance;
  late AssignmentController assignments;
  late CommunicationsController communications;
  late BulkCommunicationsController bulk;
  late OperationalCallController calls;

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
    governance = GovernanceOperationsController.prototypeSeed();
    assignments = AssignmentController.prototypeSeed(
      membership: membership,
      devices: devices,
      persistence: persistence,
    );
    communications = CommunicationsController.prototypeSeed(governance);
    bulk = BulkCommunicationsController.productionFoundation(
      membership: membership,
      devices: devices,
      governance: governance,
      persistence: persistence,
    );
    calls = OperationalCallController(
      membership: membership,
      assignments: assignments,
      devices: devices,
      persistence: persistence,
    );
  });

  Future<void> allowSms(String memberId) async {
    final ok = await bulk.recordPreference(
      memberId: memberId,
      actorId: 'STATE-COORD',
      actorRole: TgcgRole.stateCoordinator,
      actorScope: GeographicScope.kaduna,
      source: 'State Communications test consent',
      smsOptIn: true,
      pushOptIn: false,
      emailOptIn: false,
      voiceOptIn: false,
    );
    expect(ok, isTrue);
  }

  group('Targeted bulk audience filters', () {
    test('role filter restricts target contacts before channel eligibility',
        () async {
      await allowSms('MEM-0005');

      final job = await bulk.queueJob(
        title: 'Senatorial coordination',
        body: 'Operational update',
        purpose: BulkCommunicationPurpose.operations,
        targetScope: GeographicScope.kaduna,
        channels: const [BulkCommunicationChannel.sms],
        actorId: 'STATE-COORD',
        actorRole: TgcgRole.stateCoordinator,
        actorScope: GeographicScope.kaduna,
        targetRoles: const [TgcgRole.senatorialCoordinator],
      );

      expect(job, isNotNull);
      expect(job!.targetRoles, [TgcgRole.senatorialCoordinator]);
      expect(job.targetContactCount, 3);
      expect(job.eligibleRecipientCount, 1);
      expect(job.state, BulkDeliveryJobState.waitingForProvider);
    });

    test('explicit member filter intersects with role filter', () async {
      await allowSms('MEM-0005');
      await allowSms('MEM-0001');

      final job = await bulk.queueJob(
        title: 'Filtered coordination',
        body: 'Operational update',
        purpose: BulkCommunicationPurpose.operations,
        targetScope: GeographicScope.kaduna,
        channels: const [BulkCommunicationChannel.sms],
        actorId: 'STATE-COORD',
        actorRole: TgcgRole.stateCoordinator,
        actorScope: GeographicScope.kaduna,
        targetRoles: const [TgcgRole.senatorialCoordinator],
        targetMemberIds: const ['MEM-0005', 'MEM-0001'],
      );

      expect(job, isNotNull);
      expect(job!.targetContactCount, 1);
      expect(job.eligibleRecipientCount, 1);
      expect(job.targetMemberIds, containsAll(['MEM-0005', 'MEM-0001']));
    });

    test('explicit member filter works without a role filter', () async {
      await allowSms('MEM-0001');

      final job = await bulk.queueJob(
        title: 'Group member delivery',
        body: 'Operational update',
        purpose: BulkCommunicationPurpose.logistics,
        targetScope: GeographicScope.kaduna,
        channels: const [BulkCommunicationChannel.sms],
        actorId: 'STATE-COORD',
        actorRole: TgcgRole.stateCoordinator,
        actorScope: GeographicScope.kaduna,
        targetMemberIds: const ['MEM-0001'],
      );

      expect(job, isNotNull);
      expect(job!.targetContactCount, 1);
      expect(job.eligibleRecipientCount, 1);
    });

    test('no audience filters preserves the existing scope behavior', () async {
      await allowSms('MEM-0001');

      final job = await bulk.queueJob(
        title: 'Statewide delivery',
        body: 'Operational update',
        purpose: BulkCommunicationPurpose.operations,
        targetScope: GeographicScope.kaduna,
        channels: const [BulkCommunicationChannel.sms],
        actorId: 'STATE-COORD',
        actorRole: TgcgRole.stateCoordinator,
        actorScope: GeographicScope.kaduna,
      );

      expect(job, isNotNull);
      expect(job!.targetRoles, isEmpty);
      expect(job.targetMemberIds, isEmpty);
      expect(job.targetContactCount, membership.members.length);
      expect(job.eligibleRecipientCount, 1);
    });
  });

  group('State Communications command accounting', () {
    test('snapshot uses the real communications and bulk stores', () {
      final snapshot = buildStateCommunicationSnapshot(
        communications: communications,
        bulk: bulk,
        calls: calls,
      );

      expect(snapshot.contacts, hasLength(membership.members.length));
      expect(snapshot.rooms, isNotEmpty);
      expect(snapshot.messages, isNotEmpty);
      expect(snapshot.broadcasts, isNotEmpty);
      expect(snapshot.providers, hasLength(5));
      expect(snapshot.providerReady, 0);
      expect(snapshot.providerProblems, 5);
    });

    test('provider readiness and channel gaps surface as command exceptions',
        () {
      final snapshot = buildStateCommunicationSnapshot(
        communications: communications,
        bulk: bulk,
        calls: calls,
      );
      final exceptions = buildStateCommunicationExceptions(snapshot);

      expect(
        exceptions.any(
          (item) => item.title == 'Communication provider readiness gap',
        ),
        isTrue,
      );
      expect(
        exceptions.any(
          (item) =>
              item.title == 'Members without eligible outbound channel',
        ),
        isTrue,
      );
    });

    test('State Coordinator can queue an LGA operational broadcast', () {
      final lga = geography.lga('KD-ZARIA')!;
      final beforeAudit = governance.auditEvents.length;

      final ok = communications.sendBroadcast(
        title: 'Zaria command notice',
        body: 'Operational coordination notice',
        targetScope: lga.scope,
        senderId: 'STATE-COORD',
        role: TgcgRole.stateCoordinator,
        userScope: GeographicScope.kaduna,
      );

      expect(ok, isTrue);
      expect(communications.broadcasts.first.scope.lgaId, 'KD-ZARIA');
      expect(
        communications.broadcasts.first.deliveryState,
        BroadcastDeliveryState.queued,
      );
      expect(governance.auditEvents.length, beforeAudit + 1);
      expect(governance.auditEvents.first.action, 'broadcast_created');
    });
  });
}
