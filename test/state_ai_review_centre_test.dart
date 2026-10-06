import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/ai/state_ai_review_centre_page.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/edge_ai/assignment_edge_ai_store.dart';
import 'package:usesf/tgcg/evidence/evidence_store.dart';
import 'package:usesf/tgcg/field/field_operations_store.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/results/result_operations_store.dart';

void main() {
  late GeographyRegistry geography;
  late OfflinePersistenceController persistence;
  late MembershipOperationsController membership;
  late ManagedDeviceController devices;
  late AssignmentController assignments;
  late AssignmentEdgeAiController edgeAi;
  late EvidenceOperationsController evidence;
  late FieldOperationsController field;
  late ResultOperationsController results;

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
    edgeAi = AssignmentEdgeAiController(
      assignments: assignments,
      devices: devices,
      persistence: persistence,
    );
    evidence = EvidenceOperationsController(
      persistence: persistence,
    );
    field = FieldOperationsController.prototypeSeed(
      persistence: persistence,
    );
    results = ResultOperationsController.prototypeSeed(
      persistence: persistence,
    );
  });

  List<StateAiReviewCase> queue({DateTime? now}) =>
      buildStateAiReviewCases(
        membership: membership,
        assignments: assignments,
        edgeAi: edgeAi,
        directEvidence: evidence,
        field: field,
        results: results,
        now: now ?? DateTime.utc(2026, 9, 27, 8, 10),
      );

  group('State AI identity review', () {
    test('legacy verified members are not falsely queued', () {
      final cases = queue();

      expect(
        cases.any((item) => item.id == 'IDENTITY-MEM-0001'),
        isFalse,
      );
      expect(
        cases.any((item) => item.id == 'IDENTITY-MEM-0003'),
        isTrue,
      );
    });

    test('identity cases cannot masquerade as operational approval', () {
      final identity = queue().firstWhere(
        (item) => item.id == 'IDENTITY-MEM-0003',
      );

      expect(identity.source, StateAiReviewSource.identity);
      expect(identity.targetModule.name, 'membershipNetwork');
      expect(
        identity.notes.any(
          (note) => note.contains('backend/System Admin'),
        ),
        isTrue,
      );
    });
  });

  group('Assignment AI queue', () {
    test('newly assigned work is not flagged before operational start',
        () async {
      final lga = geography.lga('KD-ZARIA')!;
      final created = await assignments.createAssignment(
        title: 'Pre-start AI queue test',
        memberId: 'MEM-0001',
        targetScopeOverride: lga.scope,
        assignedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
        assignerCapabilities: const {},
      );

      final cases = queue();

      expect(
        cases.any((item) => item.id == 'ASSIGNMENT-${created.id}'),
        isFalse,
      );
    });

    test('explicit durable AI event is queued and resolvable', () async {
      final lga = geography.lga('KD-ZARIA')!;
      final created = await assignments.createAssignment(
        title: 'Explicit AI event test',
        memberId: 'MEM-0001',
        targetScopeOverride: lga.scope,
        assignedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
        assignerCapabilities: const {},
      );
      final event = await edgeAi.recordEvent(
        assignmentId: created.id,
        type: AssignmentEdgeAiEventType.evidenceIntegrity,
        severity: AssignmentEdgeAiSeverity.critical,
        source: 'edge-device',
        summary: 'Evidence integrity mismatch.',
      );

      final before = queue();
      final reviewCase = before.firstWhere(
        (item) => item.id == 'ASSIGNMENT-${created.id}',
      );

      expect(reviewCase.severity, StateAiReviewSeverity.critical);
      expect(reviewCase.resolvableEventIds, contains(event.id));

      await edgeAi.resolveEvent(
        eventId: event.id,
        resolvedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
      );

      final after = queue();
      expect(
        after.any((item) => item.id == 'ASSIGNMENT-${created.id}'),
        isFalse,
      );
    });

    test('accepted assignment with missing live telemetry enters review',
        () async {
      final lga = geography.lga('KD-ZARIA')!;
      final created = await assignments.createAssignment(
        title: 'Operational telemetry review test',
        memberId: 'MEM-0001',
        targetScopeOverride: lga.scope,
        assignedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
        assignerCapabilities: const {},
      );
      await assignments.transition(
        assignmentId: created.id,
        status: AssignmentStatus.accepted,
        actorId: 'MEM-0001',
        authorizedScope: GeographicScope.kaduna,
      );

      final reviewCase = queue().firstWhere(
        (item) => item.id == 'ASSIGNMENT-${created.id}',
      );

      expect(reviewCase.source, StateAiReviewSource.assignment);
      expect(
        reviewCase.notes.any(
          (note) => note.contains('GPS') || note.contains('Device'),
        ),
        isTrue,
      );
    });
  });

  group('Evidence integrity queue', () {
    test('evidence without a cryptographic hash is critical', () async {
      await evidence.addCapture(
        evidence: EvidenceAttachment(
          id: 'EVD-NO-HASH',
          type: EvidenceType.photo,
          fileName: 'no-hash.jpg',
          createdAt: DateTime.utc(2026, 10, 6),
          uploaderId: 'MEM-0001',
          mimeType: 'image/jpeg',
        ),
        scope: geography.lga('KD-ZARIA')!.scope,
        reference: 'Integrity test',
      );

      final reviewCase = queue().firstWhere(
        (item) => item.id == 'EVIDENCE-EVD-NO-HASH',
      );

      expect(reviewCase.source, StateAiReviewSource.evidence);
      expect(reviewCase.severity, StateAiReviewSeverity.critical);
      expect(reviewCase.targetModule.name, 'evidenceCapture');
    });
  });

  group('Result AI queue', () {
    test('prototype conflict is represented once at polling-unit level', () {
      final conflicts = queue()
          .where(
            (item) =>
                item.source == StateAiReviewSource.result &&
                item.id.startsWith('RESULT-CONFLICT-'),
          )
          .toList(growable: false);

      expect(conflicts, hasLength(1));
      expect(conflicts.single.severity, StateAiReviewSeverity.critical);
    });

    test('critical cases sort before warning cases', () {
      final cases = queue();
      final firstWarning = cases.indexWhere(
        (item) => item.severity == StateAiReviewSeverity.warning,
      );
      final lastCritical = cases.lastIndexWhere(
        (item) => item.severity == StateAiReviewSeverity.critical,
      );

      if (firstWarning >= 0 && lastCritical >= 0) {
        expect(lastCritical, lessThan(firstWarning));
      }
    });
  });
}
