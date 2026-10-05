import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/edge_ai/assignment_edge_ai_store.dart';
import 'package:usesf/tgcg/edge_ai/submitted_assignment_ai_report.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';

void main() {
  late OfflinePersistenceController persistence;
  late MembershipOperationsController membership;
  late ManagedDeviceController devices;
  late AssignmentController assignments;
  late AssignmentEdgeAiController edgeAi;

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
    membership = MembershipOperationsController.prototypeSeed(
      GeographyRegistry.prototypeSeed(),
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
  });

  test('demo individual submission builds a verified AI report', () {
    final assignment = assignments.assignmentById('ASN-DEMO-0001')!;

    final report = buildSubmittedAiReport(
      children: [assignment],
      title: assignment.title,
      assignments: assignments,
      edgeAi: edgeAi,
    );

    expect(report.isDemo, isTrue);
    expect(report.score, 100);
    expect(report.assessment, SubmittedAiAssessment.verified);
    expect(report.evidence, hasLength(2));
    expect(report.memberAssessments, hasLength(1));
    expect(
      report.memberAssessments.single.observations
          .map((item) => item.label),
      containsAll([
        'Fresh completion GPS',
        'Location corroborated',
        'Evidence preserved',
        'Image quality passed',
      ]),
    );
  });

  test('demo group submission aggregates every member and evidence item', () {
    final group = assignments.groupAssignmentById('GRP-DEMO-0001')!;
    final children = assignments.assignmentsForGroup(group.id);

    final report = buildSubmittedAiReport(
      children: children,
      title: group.title,
      assignments: assignments,
      edgeAi: edgeAi,
    );

    expect(report.isDemo, isTrue);
    expect(report.memberAssessments, hasLength(3));
    expect(report.evidence, hasLength(3));
    expect(report.score, 95);
    expect(report.assessment, SubmittedAiAssessment.verified);
    expect(
      report.memberAssessments.every(
        (item) => item.observations.any(
          (observation) =>
              observation.label == 'Activity evidence consistent',
        ),
      ),
      isTrue,
    );
  });

  test('AI warning present before submission reduces historical score',
      () {
    final assignment = assignments.assignmentById('ASN-DEMO-0001')!;
    final historicalEdgeAi = AssignmentEdgeAiController(
      assignments: assignments,
      devices: devices,
      persistence: persistence,
      events: [
        AssignmentEdgeAiEvent(
          id: 'AI-HIST-1',
          assignmentId: assignment.id,
          type: AssignmentEdgeAiEventType.imageQuality,
          severity: AssignmentEdgeAiSeverity.warning,
          createdAt: assignment.completedAt!.subtract(
            const Duration(minutes: 1),
          ),
          source: 'edge-image',
          confidence: .72,
          summary: 'One frame was slightly blurred',
          evidenceReference: 'EVD-DEMO-0001',
        ),
      ],
    );

    final report = buildSubmittedAiReport(
      children: [assignment],
      title: assignment.title,
      assignments: assignments,
      edgeAi: historicalEdgeAi,
    );

    expect(report.score, 95);
    expect(report.memberAssessments.single.aiEvents, hasLength(1));
    expect(
      report.memberAssessments.single.aiEvents.single.summary,
      'One frame was slightly blurred',
    );
  });

  test('AI event created after submission does not rewrite old report',
      () async {
    final assignment = assignments.assignmentById('ASN-DEMO-0001')!;
    await edgeAi.recordEvent(
      assignmentId: assignment.id,
      type: AssignmentEdgeAiEventType.imageQuality,
      severity: AssignmentEdgeAiSeverity.warning,
      source: 'edge-image',
      summary: 'Late review event',
    );

    final report = buildSubmittedAiReport(
      children: [assignment],
      title: assignment.title,
      assignments: assignments,
      edgeAi: edgeAi,
    );

    expect(report.score, 100);
    expect(report.memberAssessments.single.aiEvents, isEmpty);
  });

  test('location-flexible submitted duty is not treated as missing geofence',
      () {
    final assignment = assignments.assignmentById('ASN-DEMO-0003')!;

    final report = buildSubmittedAiReport(
      children: [assignment],
      title: assignment.title,
      assignments: assignments,
      edgeAi: edgeAi,
    );

    expect(report.score, 95);
    expect(
      report.memberAssessments.single.observations
          .map((item) => item.label),
      contains('Location-flexible duty'),
    );
    expect(
      report.memberAssessments.single.observations
          .map((item) => item.label),
      isNot(contains('Completion GPS unavailable')),
    );
  });
}
