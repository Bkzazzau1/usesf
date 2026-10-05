import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/domain/permissions.dart';
import 'package:usesf/tgcg/edge_ai/assignment_edge_ai_store.dart';
import 'package:usesf/tgcg/evidence/evidence_intelligence_page.dart';
import 'package:usesf/tgcg/evidence/evidence_store.dart';
import 'package:usesf/tgcg/field/field_operations_store.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/results/result_operations_store.dart';
import 'package:usesf/tgcg/session.dart';

void main() {
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
    evidence = EvidenceOperationsController(persistence: persistence);
    field = FieldOperationsController.prototypeSeed(
      persistence: persistence,
    );
    results = ResultOperationsController.prototypeSeed(
      persistence: persistence,
    );
  });

  group('Evidence permission split', () {
    test('State Coordinator views evidence but cannot capture it', () {
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.stateCoordinator,
          TgcgCapability.viewEvidence,
        ),
        isTrue,
      );
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.stateCoordinator,
          TgcgCapability.captureEvidence,
        ),
        isFalse,
      );
      expect(
        allowedModules(TgcgRole.stateCoordinator),
        contains(TgcgModule.evidenceCapture),
      );
    });

    test('polling-unit field roles retain evidence capture authority', () {
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.pollingUnitAgent,
          TgcgCapability.captureEvidence,
        ),
        isTrue,
      );
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.pollingUnitCoordinator,
          TgcgCapability.captureEvidence,
        ),
        isTrue,
      );
    });

    test('review-only executive does not receive capture authority', () {
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.readOnlyExecutive,
          TgcgCapability.viewEvidence,
        ),
        isTrue,
      );
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.readOnlyExecutive,
          TgcgCapability.captureEvidence,
        ),
        isFalse,
      );
    });
  });

  group('Evidence capture delegation', () {
    test('State Coordinator can delegate capture without personal capture permission',
        () async {
      final assignment = await assignments.createAssignment(
        title: 'Evidence capture duty',
        memberId: 'MEM-0001',
        assignedBy: 'STATE-COORD',
        authorizedScope: GeographicScope.kaduna,
        grantedCapabilities: const {
          TgcgCapability.viewEvidence,
          TgcgCapability.captureEvidence,
        },
        assignerCapabilities: TgcgPermissionPolicy.capabilitiesFor(
          TgcgRole.stateCoordinator,
        ),
      );

      expect(
        assignment.grantedCapabilities,
        contains(TgcgCapability.captureEvidence),
      );
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.stateCoordinator,
          TgcgCapability.captureEvidence,
        ),
        isFalse,
      );
    });

    test('capture delegation still requires assignment-management authority',
        () async {
      await expectLater(
        assignments.createAssignment(
          title: 'Unauthorized evidence duty',
          memberId: 'MEM-0001',
          assignedBy: 'VIEWER',
          authorizedScope: GeographicScope.kaduna,
          grantedCapabilities: const {
            TgcgCapability.captureEvidence,
          },
          assignerCapabilities: const {
            TgcgCapability.viewEvidence,
          },
        ),
        throwsStateError,
      );
    });
  });

  group('State Evidence Intelligence aggregation', () {
    test('combines all authoritative evidence streams', () async {
      final pu = membership.geography.pollingUnit('KD-KN-W01-PU001')!;
      await evidence.addCapture(
        evidence: EvidenceAttachment(
          id: 'EVD-DIRECT-TEST',
          type: EvidenceType.audio,
          fileName: 'direct_audio.m4a',
          createdAt: DateTime.utc(2026, 9, 27, 9),
          uploaderId: 'MEM-0001',
          contentHash: 'sha256:direct-test',
          mimeType: 'audio/mp4',
          latitude: 10.5245,
          longitude: 7.4395,
        ),
        scope: pu.scope,
        reference: 'Direct field capture',
      );

      await field.submitFieldReport(
        category: 'Evidence test',
        summary: 'Field report with attached evidence.',
        scope: pu.scope,
        reporterId: 'MEM-0001',
        evidence: [
          EvidenceAttachment(
            id: 'EVD-RPT-TEST',
            type: EvidenceType.document,
            fileName: 'field_report.pdf',
            createdAt: DateTime.utc(2026, 9, 27, 9, 5),
            uploaderId: 'MEM-0001',
            contentHash: 'sha256:report-test',
            mimeType: 'application/pdf',
          ),
        ],
      );

      final records = buildEvidenceIntelligenceRecords(
        scope: GeographicScope.kaduna,
        directEvidence: evidence,
        assignments: assignments,
        field: field,
        results: results,
        edgeAi: edgeAi,
      );

      final ids = records.map((item) => item.evidence.id).toSet();
      final sources = records.map((item) => item.source).toSet();

      expect(ids, contains('EVD-DIRECT-TEST'));
      expect(ids, contains('EVD-RPT-TEST'));
      expect(ids, contains('EVD-DEMO-0001'));
      expect(ids, contains('EVD-0001'));
      expect(ids, contains('FORM-0001'));
      expect(
        sources,
        containsAll(EvidenceIntelligenceSource.values),
      );
    });

    test('scope filtering confines the intelligence register to the LGA',
        () {
      final zaria = membership.geography.lga('KD-ZARIA')!.scope;

      final records = buildEvidenceIntelligenceRecords(
        scope: zaria,
        directEvidence: evidence,
        assignments: assignments,
        field: field,
        results: results,
        edgeAi: edgeAi,
      );

      expect(records, isNotEmpty);
      expect(
        records.every((item) => item.scope.lgaId == 'KD-ZARIA'),
        isTrue,
      );
    });

    test('result validation requiring review flags its evidence', () {
      final records = buildEvidenceIntelligenceRecords(
        scope: GeographicScope.kaduna,
        directEvidence: evidence,
        assignments: assignments,
        field: field,
        results: results,
        edgeAi: edgeAi,
      );

      final zariaResult = records.firstWhere(
        (item) => item.evidence.id == 'FORM-0002',
      );
      expect(zariaResult.source, EvidenceIntelligenceSource.result);
      expect(zariaResult.requiresReview, isTrue);
    });

    test('field-report evidence survives field-controller recreation',
        () async {
      final pu = membership.geography.pollingUnit('KD-KN-W01-PU001')!;
      await field.submitFieldReport(
        category: 'Persisted report',
        summary: 'Evidence persists after restart.',
        scope: pu.scope,
        reporterId: 'MEM-0001',
        evidence: [
          EvidenceAttachment(
            id: 'EVD-FIELD-HYDRATE',
            type: EvidenceType.photo,
            fileName: 'persisted_field.jpg',
            createdAt: DateTime.utc(2026, 9, 27, 10, 10),
            uploaderId: 'MEM-0001',
            contentHash: 'sha256:field-hydrate',
            mimeType: 'image/jpeg',
          ),
        ],
      );

      final restored = FieldOperationsController.prototypeSeed(
        persistence: persistence,
      );
      await restored.hydrateFromOffline();

      expect(
        restored.reports.expand((item) => item.evidence).map((item) => item.id),
        contains('EVD-FIELD-HYDRATE'),
      );
    });

    test('result-form evidence survives result-controller recreation',
        () async {
      final pu = membership.geography.pollingUnit('KD-KN-W01-PU001')!;
      await results.submit(
        pollingUnitScope: pu.scope,
        submittedBy: 'MEM-0001',
        source: SubmissionSource.app,
        partyVotes: const {'P1': 10, 'P2': 8},
        totalVotesRecorded: 18,
        accreditedVoters: 20,
        rejectedVotes: 2,
        resultForm: EvidenceAttachment(
          id: 'EVD-RESULT-HYDRATE',
          type: EvidenceType.resultForm,
          fileName: 'persisted_result.jpg',
          createdAt: DateTime.utc(2026, 9, 27, 10, 20),
          uploaderId: 'MEM-0001',
          contentHash: 'sha256:result-hydrate',
          mimeType: 'image/jpeg',
        ),
        ocrPartyVotes: const {'P1': 10, 'P2': 8},
        ocrConfidence: .98,
      );

      final restored = ResultOperationsController.prototypeSeed(
        persistence: persistence,
      );
      await restored.hydrateFromOffline();

      expect(
        restored.submissions
            .map((item) => item.resultForm?.id)
            .whereType<String>(),
        contains('EVD-RESULT-HYDRATE'),
      );
    });

    test('direct captures hydrate back into intelligence registry', () async {
      final pu = membership.geography.pollingUnit('KD-KN-W01-PU001')!;
      await evidence.addCapture(
        evidence: EvidenceAttachment(
          id: 'EVD-HYDRATE-1',
          type: EvidenceType.photo,
          fileName: 'hydrate.jpg',
          createdAt: DateTime.utc(2026, 9, 27, 10),
          uploaderId: 'MEM-0001',
          contentHash: 'sha256:hydrate',
          mimeType: 'image/jpeg',
        ),
        scope: pu.scope,
        reference: 'Hydration test',
      );

      final restored = EvidenceOperationsController(
        persistence: persistence,
      );
      await restored.hydrateFromOffline();

      final saved = restored.records.singleWhere(
        (item) => item.evidence.id == 'EVD-HYDRATE-1',
      );
      expect(saved.scope.pollingUnitId, pu.scope.pollingUnitId);
      expect(saved.reference, 'Hydration test');
      expect(saved.evidence.contentHash, 'sha256:hydrate');
    });
  });
}
