import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/results/result_operations_store.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('production foundation starts empty and hydrates only persisted results',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final persistence = OfflinePersistenceController(
      openDatabase: () async => InMemoryOfflineDatabase(),
    );
    await persistence.initialize();

    final store = ResultOperationsController.productionFoundation(
      persistence: persistence,
    );
    expect(store.submissions, isEmpty);
    expect(store.pendingReviewCount, 0);
    expect(store.verifiedCount, 0);

    const scope = GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/053/KD',
      senatorialDistrictName: 'Kaduna Central',
      lgaId: 'KD-KADUNA-NORTH',
      lgaName: 'Kaduna North',
      wardId: 'KD-KN-W01',
      wardName: 'Ward 01',
      pollingUnitId: 'KD-KN-W01-PU001',
      pollingUnitName: 'PU 001',
    );

    final saved = await store.submit(
      pollingUnitScope: scope,
      submittedBy: 'MEM-TEST',
      source: SubmissionSource.sms,
      partyVotes: const {'P1': 12, 'P2': 8},
      totalVotesRecorded: 20,
      accreditedVoters: 22,
      rejectedVotes: 2,
    );

    final restored = ResultOperationsController.productionFoundation(
      persistence: persistence,
    );
    expect(restored.submissions, isEmpty);

    await restored.hydrateFromOffline();

    expect(restored.submissions, hasLength(1));
    expect(restored.submissions.single.id, saved.id);
    expect(restored.submissions.single.submittedBy, 'MEM-TEST');
    expect(
      restored.submissions.any(
        (item) => const {'RES-0001', 'RES-0002', 'RES-0003', 'RES-0004'}
            .contains(item.id) &&
            item.id != saved.id,
      ),
      isFalse,
    );
  });

  test('prototype review queue contains flagged submissions only', () {
    final store = ResultOperationsController.prototypeSeed();

    final review = store.reviewQueueForScope(GeographicScope.kaduna);

    expect(review.map((item) => item.id), containsAll(<String>['RES-0002', 'RES-0004']));
    expect(review.any((item) => item.id == 'RES-0001'), isFalse);
  });

  test('human verification removes a flagged record from review queue', () async {
    final store = ResultOperationsController.prototypeSeed();

    final verified = await store.verify(
      submissionId: 'RES-0002',
      verifierId: 'STATE-REVIEWER',
      role: TgcgRole.stateCollationOfficer,
      userScope: GeographicScope.kaduna,
    );

    expect(verified, isTrue);
    expect(
      store.reviewQueueForScope(GeographicScope.kaduna).any((item) => item.id == 'RES-0002'),
      isFalse,
    );
  });

  test('clean new polling-unit submission is not routed to human review', () async {
    final store = ResultOperationsController.prototypeSeed();
    const scope = GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      lgaId: 'BA-DEMO',
      lgaName: 'Demo LGA',
      wardId: 'BA-DEMO-W01',
      wardName: 'Ward 01',
      pollingUnitId: 'BA-DEMO-W01-PU001',
      pollingUnitName: 'PU 001',
    );

    final submission = await store.submit(
      pollingUnitScope: scope,
      submittedBy: 'AG-BA-001',
      source: SubmissionSource.app,
      partyVotes: const {'P1': 100, 'P2': 80, 'P3': 20},
      totalVotesRecorded: 200,
      accreditedVoters: 210,
      rejectedVotes: 10,
      registeredVoters: 500,
      ocrPartyVotes: const {'P1': 100, 'P2': 80, 'P3': 20},
      ocrConfidence: .96,
      // App submissions must carry the result-form photo to skip review.
      resultForm: EvidenceAttachment(
        id: 'FORM-TEST-001',
        type: EvidenceType.resultForm,
        fileName: 'pu001_ec8a.jpg',
        createdAt: DateTime.utc(2026, 9, 27, 17),
        uploaderId: 'AG-BA-001',
      ),
    );

    expect(submission.validation?.requiresHumanReview, isFalse);
    expect(submission.status, RecordStatus.submitted);
  });

  test('second active submission for same polling unit is flagged duplicate', () async {
    final store = ResultOperationsController.prototypeSeed();
    const scope = GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      lgaId: 'EN-DEMO',
      lgaName: 'Demo LGA',
      wardId: 'EN-DEMO-W01',
      wardName: 'Ward 01',
      pollingUnitId: 'EN-DEMO-W01-PU001',
      pollingUnitName: 'PU 001',
    );

    await store.submit(
      pollingUnitScope: scope,
      submittedBy: 'AG-EN-001',
      source: SubmissionSource.sms,
      partyVotes: const {'P1': 70, 'P2': 60},
      totalVotesRecorded: 130,
      accreditedVoters: 135,
      rejectedVotes: 5,
    );
    final duplicate = await store.submit(
      pollingUnitScope: scope,
      submittedBy: 'AG-EN-002',
      source: SubmissionSource.ussd,
      partyVotes: const {'P1': 70, 'P2': 60},
      totalVotesRecorded: 130,
      accreditedVoters: 135,
      rejectedVotes: 5,
    );

    expect(duplicate.validation?.duplicateSuspected, isTrue);
    expect(duplicate.status, RecordStatus.underReview);
  });
}
