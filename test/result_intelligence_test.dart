import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/evidence/device_evidence_service.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/results/result_form_capture_service.dart';
import 'package:usesf/tgcg/results/result_intelligence_page.dart';
import 'package:usesf/tgcg/results/result_operations_store.dart';

void main() {
  group('Result Intelligence accounting', () {
    test('prototype accounting distinguishes missing, review and conflict PUs', () {
      final geography = GeographyRegistry.prototypeSeed();
      final results = ResultOperationsController.prototypeSeed();

      final accounts = buildPollingUnitResultAccounts(
        units: geography.pollingUnits,
        submissions: results.submissions,
      );

      expect(accounts, hasLength(6));
      expect(
        accounts.where((item) => item.state == ResultAccountingState.missing),
        hasLength(3),
      );
      expect(
        accounts.where((item) => item.state == ResultAccountingState.conflict),
        hasLength(1),
      );
      expect(
        accounts.where((item) => item.state == ResultAccountingState.aiReview),
        hasLength(1),
      );
      expect(
        accounts.where((item) => item.state == ResultAccountingState.received),
        hasLength(1),
      );
    });

    test('human verified record wins after competing result is disputed', () {
      final geography = GeographyRegistry.prototypeSeed();
      final unit = geography.pollingUnits.first;
      final scope = unit.scope;
      final now = DateTime.utc(2026, 10, 6, 8);

      ElectionResultSubmission item(
        String id,
        RecordStatus status,
      ) =>
          ElectionResultSubmission(
            id: id,
            pollingUnitScope: scope,
            submittedBy: 'MEM-0001',
            submittedAt: now,
            status: status,
            source: SubmissionSource.app,
            partyVotes: const {'P1': 100, 'P2': 50},
            totalVotesRecorded: 150,
            accreditedVoters: 160,
          );

      final accounts = buildPollingUnitResultAccounts(
        units: [unit],
        submissions: [
          item('RES-A', RecordStatus.verified),
          item('RES-B', RecordStatus.disputed),
        ],
      );

      expect(accounts.single.hasConflict, isFalse);
      expect(accounts.single.state, ResultAccountingState.verified);
    });

    test('rejected result does not satisfy polling-unit accounting', () {
      final geography = GeographyRegistry.prototypeSeed();
      final unit = geography.pollingUnits.first;
      final result = ElectionResultSubmission(
        id: 'RES-REJECTED',
        pollingUnitScope: unit.scope,
        submittedBy: 'MEM-0001',
        submittedAt: DateTime.utc(2026, 10, 6),
        status: RecordStatus.rejected,
        source: SubmissionSource.app,
        partyVotes: const {'P1': 10},
        totalVotesRecorded: 10,
        accreditedVoters: 12,
      );

      final accounts = buildPollingUnitResultAccounts(
        units: [unit],
        submissions: [result],
      );

      expect(accounts.single.hasSubmission, isFalse);
      expect(accounts.single.state, ResultAccountingState.missing);
    });
  });

  group('Result AI assessment', () {
    test('clean OCR-matched form scores as clean', () {
      final results = ResultOperationsController.prototypeSeed();
      final item = results.submissions.firstWhere(
        (value) => value.id == 'RES-0001',
      );

      final assessment = buildResultAiAssessment(item);

      expect(assessment.score, 95);
      expect(assessment.state, ResultAiState.clean);
      expect(
        assessment.findings.map((item) => item.label),
        contains('AI OCR matched'),
      );
    });

    test('OCR mismatch is routed to AI review', () {
      final results = ResultOperationsController.prototypeSeed();
      final item = results.submissions.firstWhere(
        (value) => value.id == 'RES-0002',
      );

      final assessment = buildResultAiAssessment(item);

      expect(assessment.score, lessThan(75));
      expect(assessment.state, ResultAiState.review);
      expect(
        assessment.findings.map((item) => item.label),
        contains('AI OCR mismatch'),
      );
    });

    test('duplicate result with no form becomes AI risk', () {
      final results = ResultOperationsController.prototypeSeed();
      final item = results.submissions.firstWhere(
        (value) => value.id == 'RES-0004',
      );

      final assessment = buildResultAiAssessment(
        item,
        accountConflict: true,
      );

      expect(assessment.state, ResultAiState.risk);
      expect(
        assessment.findings.map((item) => item.label),
        contains('Duplicate / conflict detected'),
      );
    });
  });

  group('On-device result form parser', () {
    test('extracts party and voter-accounting figures from OCR text', () {
      final captured = ResultFormParser.parse(
        evidence: CapturedEvidence(
          type: EvidenceType.resultForm,
          fileName: 'form.jpg',
          mimeType: 'image/jpeg',
          createdAt: DateTime.utc(2026, 10, 6),
          contentHash: 'sha256:test',
        ),
        rawText: '''
P1 120
P2 80
P3 40
P4 10
TOTAL 250
ACCREDITED VOTERS 262
REJECTED VOTES 12
REGISTERED VOTERS 600
''',
      );

      expect(captured.partyVotes, {
        'P1': 120,
        'P2': 80,
        'P3': 40,
        'P4': 10,
      });
      expect(captured.totalVotes, 250);
      expect(captured.accreditedVoters, 262);
      expect(captured.rejectedVotes, 12);
      expect(captured.registeredVoters, 600);
      expect(captured.extractionConfidence, 1);
    });

    test('partial OCR extraction reports partial coverage without invention', () {
      final captured = ResultFormParser.parse(
        evidence: CapturedEvidence(
          type: EvidenceType.resultForm,
          fileName: 'partial.jpg',
          mimeType: 'image/jpeg',
          createdAt: DateTime.utc(2026, 10, 6),
        ),
        rawText: 'P1 120\nP2 80\nTOTAL 200',
      );

      expect(captured.partyVotes['P1'], 120);
      expect(captured.partyVotes['P2'], 80);
      expect(captured.partyVotes.containsKey('P3'), isFalse);
      expect(captured.extractionConfidence, lessThan(1));
    });
  });

  group('OCR persistence', () {
    test('AI-extracted figures survive offline hydration', () async {
      final persistence = OfflinePersistenceController(
        openDatabase: () async => InMemoryOfflineDatabase(),
      );
      await persistence.initialize();

      final geography = GeographyRegistry.prototypeSeed();
      final controller = ResultOperationsController.prototypeSeed(
        persistence: persistence,
      );
      final unit = geography.pollingUnits[1];

      final saved = await controller.submit(
        pollingUnitScope: unit.scope,
        submittedBy: 'MEM-0001',
        source: SubmissionSource.app,
        partyVotes: const {'P1': 70, 'P2': 30},
        totalVotesRecorded: 100,
        accreditedVoters: 110,
        rejectedVotes: 10,
        registeredVoters: unit.registeredVoters,
        resultForm: EvidenceAttachment(
          id: 'FORM-OCR-PERSIST',
          type: EvidenceType.resultForm,
          fileName: 'persist.jpg',
          createdAt: DateTime.utc(2026, 10, 6),
          uploaderId: 'MEM-0001',
          contentHash: 'sha256:persist',
          mimeType: 'image/jpeg',
        ),
        ocrPartyVotes: const {'P1': 70, 'P2': 30},
        ocrConfidence: 1,
      );

      final restored = ResultOperationsController.prototypeSeed(
        persistence: persistence,
      );
      await restored.hydrateFromOffline();

      final hydrated = restored.submissions.firstWhere(
        (item) => item.id == saved.id,
      );
      expect(hydrated.ocrPartyVotes, const {'P1': 70, 'P2': 30});
      expect(hydrated.validation?.ocrMatchedManualEntry, isTrue);
    });
  });
}
