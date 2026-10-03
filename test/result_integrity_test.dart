import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/results/result_integrity.dart';

void main() {
  const pollingUnit = GeographicScope(
    level: GeographyLevel.pollingUnit,
    country: 'Nigeria',
    zoneId: 'NG-NC',
    zoneName: 'North West',
    stateId: 'NG-BN',
    stateName: 'Kaduna',
    lgaId: 'NG-KD-ZAR',
    lgaName: 'Zaria',
    wardId: 'NG-KD-ZAR-W01',
    wardName: 'Ward 01',
    pollingUnitId: 'NG-KD-ZAR-W01-PU001',
    pollingUnitName: 'Polling Unit 001',
  );

  ElectionResultSubmission submission({
    Map<String, int> partyVotes = const {'P1': 120, 'P2': 80},
    int totalVotesRecorded = 200,
    int accreditedVoters = 230,
    int rejectedVotes = 10,
    int? registeredVoters = 300,
  }) {
    return ElectionResultSubmission(
      id: 'RES-001',
      pollingUnitScope: pollingUnit,
      submittedBy: 'AG-001',
      submittedAt: DateTime.utc(2026, 9, 27),
      status: RecordStatus.submitted,
      source: SubmissionSource.app,
      partyVotes: partyVotes,
      totalVotesRecorded: totalVotesRecorded,
      accreditedVoters: accreditedVoters,
      rejectedVotes: rejectedVotes,
      registeredVoters: registeredVoters,
    );
  }

  group('ResultIntegrityPolicy', () {
    test('accepts internally consistent figures', () {
      final result = ResultIntegrityPolicy.validate(submission());

      expect(result.arithmeticValid, isTrue);
      expect(result.requiresHumanReview, isFalse);
    });

    test('flags party vote sum mismatch', () {
      final result = ResultIntegrityPolicy.validate(
        submission(totalVotesRecorded: 210),
      );

      expect(result.arithmeticValid, isFalse);
      expect(result.requiresHumanReview, isTrue);
    });

    test('flags OCR disagreement without overwriting manual figures', () {
      final original = submission();
      final result = ResultIntegrityPolicy.validate(
        original,
        ocrPartyVotes: const {'P1': 120, 'P2': 60},
        ocrConfidence: .94,
      );

      expect(result.ocrMatchedManualEntry, isFalse);
      expect(result.requiresHumanReview, isTrue);
      expect(original.partyVotes['P2'], 80);
    });
  });
}
