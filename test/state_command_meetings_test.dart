import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/meeting/command_meeting_store.dart';
import 'package:usesf/tgcg/meeting/operational_call_store.dart';
import 'package:usesf/tgcg/meeting/state_command_meetings_page.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';

void main() {
  late GeographyRegistry geography;
  late OfflinePersistenceController persistence;
  late MembershipOperationsController membership;
  late ManagedDeviceController devices;
  late AssignmentController assignments;
  late GovernanceOperationsController governance;
  late OperationalCallController calls;
  late CommandMeetingController meetings;

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
    calls = OperationalCallController(
      membership: membership,
      assignments: assignments,
      devices: devices,
      persistence: persistence,
    );
    meetings = CommandMeetingController(
      persistence: persistence,
      governance: governance,
      membership: membership,
    );
  });

  group('Command meeting audience', () {
    test('State audience excludes blocked members', () {
      final audience = resolveCommandMeetingAudience(
        membership: membership,
        governance: governance,
        calls: calls,
        scope: GeographicScope.kaduna,
      );

      expect(audience.total, greaterThan(0));
      expect(
        audience.memberIds.every(
          (id) => membership.memberById(id)?.isBlocked == false,
        ),
        isTrue,
      );
    });

    test('role filter selects the seeded Senatorial Coordinators', () {
      final audience = resolveCommandMeetingAudience(
        membership: membership,
        governance: governance,
        calls: calls,
        scope: GeographicScope.kaduna,
        targetRole: TgcgRole.senatorialCoordinator,
      );

      expect(audience.memberIds.toSet(), {'MEM-0005', 'MEM-0006', 'MEM-0010'});
      expect(audience.gpsReady, 0);
    });

    test('group IDs intersect with the selected role', () {
      governance.assignRole(
        subjectId: 'MEM-0001',
        subjectName: membership.memberById('MEM-0001')!.fullName,
        role: TgcgRole.mediaOfficer,
        scope: GeographicScope.kaduna,
        assignedBy: 'STATE-COORD',
      );

      final audience = resolveCommandMeetingAudience(
        membership: membership,
        governance: governance,
        calls: calls,
        scope: GeographicScope.kaduna,
        targetRole: TgcgRole.mediaOfficer,
        groupMemberIds: const ['MEM-0001', 'MEM-0005'],
      );

      expect(audience.memberIds, ['MEM-0001']);
    });
  });

  group('Durable command meeting lifecycle', () {
    test('State Coordinator schedules and hydrates a meeting', () async {
      final meeting = await meetings.scheduleMeeting(
        title: 'LGA readiness conference',
        agenda: 'Review field readiness.',
        scope: GeographicScope.kaduna,
        inviteeMemberIds: const ['MEM-0001'],
        createdBy: 'STATE-COORD',
        createdByRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
        scheduledAt: DateTime.utc(2026, 10, 7, 9),
        targetRoles: const [TgcgRole.mediaOfficer],
      );

      expect(meeting.status, CommandMeetingStatus.scheduled);
      expect(
        persistence.pendingOutbox.any(
          (item) =>
              item.entityType == 'command_meeting' &&
              item.entityId == meeting.id,
        ),
        isTrue,
      );

      final restored = CommandMeetingController(
        persistence: persistence,
        governance: governance,
        membership: membership,
      );
      await restored.hydrateFromOffline();

      final hydrated = restored.meetingById(meeting.id);
      expect(hydrated, isNotNull);
      expect(hydrated!.title, 'LGA readiness conference');
      expect(hydrated.inviteeMemberIds, ['MEM-0001']);
      expect(hydrated.targetRoles, [TgcgRole.mediaOfficer]);
    });

    test('lower coordinator cannot schedule a State command meeting', () async {
      await expectLater(
        meetings.scheduleMeeting(
          title: 'Unauthorized meeting',
          scope: GeographicScope.kaduna,
          inviteeMemberIds: const ['MEM-0001'],
          createdBy: 'LGA-COORD',
          createdByRole: TgcgRole.lgaCoordinator,
          authorizedScope: geography.lga('KD-ZARIA')!.scope,
          scheduledAt: DateTime.utc(2026, 10, 7, 9),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('conference start requires fresh GPS for every invitee', () async {
      final meeting = await meetings.scheduleMeeting(
        title: 'GPS-bound meeting',
        scope: GeographicScope.kaduna,
        inviteeMemberIds: const ['MEM-0001'],
        createdBy: 'STATE-COORD',
        createdByRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
        scheduledAt: DateTime.utc(2026, 10, 7, 9),
      );

      await expectLater(
        calls.startConference(
          recipientMemberIds: meeting.inviteeMemberIds,
          callerId: 'STATE-COORD',
          callerName: 'State Coordinator',
          callerRole: TgcgRole.stateCoordinator,
          authorizedScope: GeographicScope.kaduna,
        ),
        throwsA(isA<StateError>()),
      );

      devices.recordHeartbeat(
        deviceId: 'DEV-KD-001',
        capturedAt: DateTime.now().toUtc(),
        latitude: 11.0855,
        longitude: 7.7199,
        accuracyMeters: 5,
        batteryPercent: 80,
        syncState: 'synced',
      );

      final call = await calls.startConference(
        recipientMemberIds: meeting.inviteeMemberIds,
        callerId: 'STATE-COORD',
        callerName: 'State Coordinator',
        callerRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
      );

      expect(call.hasGpsForAllRecipients, isTrue);
      final live = await meetings.markLive(
        meetingId: meeting.id,
        operationalCallId: call.id,
        actorId: 'STATE-COORD',
      );
      expect(live.status, CommandMeetingStatus.live);
    });

    test('attendance, no-show and action items persist', () async {
      devices.recordHeartbeat(
        deviceId: 'DEV-KD-001',
        capturedAt: DateTime.now().toUtc(),
        latitude: 11.0855,
        longitude: 7.7199,
        accuracyMeters: 5,
        batteryPercent: 80,
        syncState: 'synced',
      );
      final meeting = await meetings.scheduleMeeting(
        title: 'Attendance test',
        scope: GeographicScope.kaduna,
        inviteeMemberIds: const ['MEM-0001', 'MEM-0005'],
        createdBy: 'STATE-COORD',
        createdByRole: TgcgRole.stateCoordinator,
        authorizedScope: GeographicScope.kaduna,
        scheduledAt: DateTime.utc(2026, 10, 7, 9),
      );

      final completed = await meetings.completeMeeting(
        meetingId: meeting.id,
        actorId: 'STATE-COORD',
        attendedMemberIds: const ['MEM-0001'],
        declinedMemberIds: const [],
      );

      expect(completed.attendedMemberIds, ['MEM-0001']);
      expect(completed.noShowCount, 1);

      final withAction = await meetings.addActionItem(
        meetingId: meeting.id,
        title: 'Submit LGA follow-up',
        createdBy: 'STATE-COORD',
        ownerMemberId: 'MEM-0001',
        dueAt: DateTime.utc(2026, 10, 8),
      );
      expect(withAction.openActionCount, 1);

      final actionId = withAction.actionItems.single.id;
      final actionDone = await meetings.completeActionItem(
        meetingId: meeting.id,
        actionItemId: actionId,
        completedBy: 'STATE-COORD',
      );
      expect(actionDone.openActionCount, 0);
      expect(
        actionDone.actionItems.single.status,
        MeetingActionStatus.completed,
      );

      final restored = CommandMeetingController(
        persistence: persistence,
        governance: governance,
        membership: membership,
      );
      await restored.hydrateFromOffline();
      final hydrated = restored.meetingById(meeting.id)!;

      expect(hydrated.status, CommandMeetingStatus.completed);
      expect(hydrated.noShowCount, 1);
      expect(hydrated.actionItems.single.status, MeetingActionStatus.completed);
    });
  });
}
