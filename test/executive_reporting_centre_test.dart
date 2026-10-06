import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/domain/permissions.dart';
import 'package:usesf/tgcg/edge_ai/assignment_edge_ai_store.dart';
import 'package:usesf/tgcg/evidence/evidence_store.dart';
import 'package:usesf/tgcg/field/field_operations_store.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/meeting/operational_call_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/reports/executive_reporting_centre_page.dart';
import 'package:usesf/tgcg/reports/report_store.dart';
import 'package:usesf/tgcg/results/result_operations_store.dart';

void main() {
  late GeographyRegistry geography;
  late OfflinePersistenceController persistence;
  late MembershipOperationsController membership;
  late ManagedDeviceController devices;
  late AssignmentController assignments;
  late GovernanceOperationsController governance;
  late FieldOperationsController field;
  late ResultOperationsController results;
  late OperationalCallController calls;
  late AssignmentEdgeAiController edgeAi;
  late EvidenceOperationsController evidence;
  late ReportOperationsController reports;

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
    field = FieldOperationsController.prototypeSeed(
      persistence: persistence,
    );
    results = ResultOperationsController.prototypeSeed(
      persistence: persistence,
    );
    calls = OperationalCallController(
      membership: membership,
      assignments: assignments,
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
    reports = ReportOperationsController.prototypeSeed(governance);
  });

  ExecutiveBriefingSnapshot snapshot() => buildExecutiveBriefingSnapshot(
        membership: membership,
        assignments: assignments,
        devices: devices,
        governance: governance,
        field: field,
        results: results,
        calls: calls,
        edgeAi: edgeAi,
        evidence: evidence,
        now: DateTime.utc(2026, 9, 27, 8, 30),
      );

  group('Executive briefing snapshot', () {
    test('builds the direct 23-LGA statewide performance board', () {
      final value = snapshot();

      expect(value.lgaCoverage, hasLength(23));
      expect(value.leadership.lgaExpected, 23);
      expect(value.totalMembers, membership.members.length);
      expect(value.generatedAt, DateTime.utc(2026, 9, 27, 8, 30));
    });

    test('uses real operational stores rather than hard-coded metrics', () {
      final value = snapshot();

      expect(value.openIncidents, greaterThan(0));
      expect(value.evidenceRecords, greaterThan(0));
      expect(value.aiReviewCases, isNotEmpty);
      expect(
        value.hashedEvidenceRecords,
        lessThanOrEqualTo(value.evidenceRecords),
      );
      expect(
        value.stateCoverage.receivedResultPollingUnits,
        greaterThanOrEqualTo(value.stateCoverage.verifiedResultPollingUnits),
      );
    });

    test('executive priorities aggregate leadership vacancies', () {
      final priorities = buildExecutivePriorities(snapshot());

      final leadership = priorities
          .where((item) => item.title == 'LGA leadership vacancies')
          .toList(growable: false);

      expect(leadership, hasLength(1));
      expect(leadership.single.detail, contains('23/23'));
    });

    test('critical priorities sort before warning priorities', () {
      final priorities = buildExecutivePriorities(snapshot());
      final firstWarning =
          priorities.indexWhere((item) => item.severity == 3);
      final lastCritical =
          priorities.lastIndexWhere((item) => item.severity >= 4);

      if (firstWarning >= 0 && lastCritical >= 0) {
        expect(lastCritical, lessThan(firstWarning));
      }
    });
  });

  group('Executive Brief export authority', () {
    test('State Coordinator can queue a statewide Executive Brief', () {
      final beforeAudit = governance.auditEvents.length;

      final job = reports.requestExport(
        kind: ReportKind.executiveBrief,
        format: ExportFormat.pdf,
        targetScope: GeographicScope.kaduna,
        actorId: 'STATE-COORD',
        role: TgcgRole.stateCoordinator,
        userScope: GeographicScope.kaduna,
        effectiveCapabilities: TgcgPermissionPolicy.capabilitiesFor(
          TgcgRole.stateCoordinator,
        ),
        recordCount: 23,
      );

      expect(job, isNotNull);
      expect(job!.kind, ReportKind.executiveBrief);
      expect(job.status, ExportJobStatus.queued);
      expect(governance.auditEvents.length, beforeAudit + 1);
      expect(governance.auditEvents.first.action, 'report_export_requested');
    });

    test('Executive Brief cannot target an LGA', () {
      final lga = geography.lga('KD-ZARIA')!;

      final job = reports.requestExport(
        kind: ReportKind.executiveBrief,
        format: ExportFormat.pdf,
        targetScope: lga.scope,
        actorId: 'STATE-COORD',
        role: TgcgRole.stateCoordinator,
        userScope: GeographicScope.kaduna,
        effectiveCapabilities: TgcgPermissionPolicy.capabilitiesFor(
          TgcgRole.stateCoordinator,
        ),
      );

      expect(job, isNull);
    });

    test('Senatorial Coordinator cannot export the State Executive Brief', () {
      final job = reports.requestExport(
        kind: ReportKind.executiveBrief,
        format: ExportFormat.pdf,
        targetScope: GeographicScope.kaduna,
        actorId: 'SENATORIAL-COORD',
        role: TgcgRole.senatorialCoordinator,
        userScope: GeographicScope.kaduna,
        effectiveCapabilities: TgcgPermissionPolicy.capabilitiesFor(
          TgcgRole.senatorialCoordinator,
        ),
      );

      expect(job, isNull);
    });

    test('ordinary State Coordinator report permissions remain unchanged', () {
      final incident = reports.requestExport(
        kind: ReportKind.incidentSummary,
        format: ExportFormat.pdf,
        targetScope: GeographicScope.kaduna,
        actorId: 'STATE-COORD',
        role: TgcgRole.stateCoordinator,
        userScope: GeographicScope.kaduna,
        effectiveCapabilities: TgcgPermissionPolicy.capabilitiesFor(
          TgcgRole.stateCoordinator,
        ),
      );
      final audit = reports.requestExport(
        kind: ReportKind.auditTrail,
        format: ExportFormat.csv,
        targetScope: GeographicScope.kaduna,
        actorId: 'STATE-COORD',
        role: TgcgRole.stateCoordinator,
        userScope: GeographicScope.kaduna,
        effectiveCapabilities: TgcgPermissionPolicy.capabilitiesFor(
          TgcgRole.stateCoordinator,
        ),
      );

      expect(incident, isNotNull);
      expect(audit, isNull);
    });
  });
}
