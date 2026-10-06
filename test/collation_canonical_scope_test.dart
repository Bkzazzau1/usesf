import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/collation/collation_engine.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';

void main() {
  const state = GeographicScope(
    level: GeographyLevel.state,
    country: 'Nigeria',
    zoneId: 'NW',
    zoneName: 'North West',
    stateId: 'KD',
    stateName: 'Kaduna',
  );

  test('canonical PU registry supplies missing parent geography during drill-down',
      () {
    final geography = GeographyRegistry.prototypeSeed();
    final engine = CollationEngine.fromGeography(geography);
    final district = engine
        .childScopes(state)
        .singleWhere((scope) => scope.senatorialDistrictId == 'SD/053/KD');

    const legacySubmissionScope = GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      lgaId: 'KD-KADUNA-NORTH',
      lgaName: 'Kaduna North',
      wardId: 'KD-KN-W01',
      wardName: 'Ward 01',
      pollingUnitId: 'KD-KN-W01-PU001',
      pollingUnitName: 'PU 001',
    );

    final submission = ElectionResultSubmission(
      id: 'R-LEGACY',
      pollingUnitScope: legacySubmissionScope,
      submittedBy: 'AGENT-1',
      submittedAt: DateTime.utc(2026, 9, 27),
      status: RecordStatus.verified,
      source: SubmissionSource.app,
      partyVotes: const {'P1': 12, 'P2': 8},
      totalVotesRecorded: 20,
      accreditedVoters: 22,
    );

    final summary = engine.summarize(district, [submission]);

    expect(summary.verifiedPollingUnitCount, 1);
    expect(summary.includedSubmissionIds, ['R-LEGACY']);
    expect(summary.partyVotes, {'P1': 12, 'P2': 8});
  });

  test('collation expectations follow the live canonical polling-unit registry',
      () {
    final geography = GeographyRegistry.prototypeSeed();
    final engine = CollationEngine.fromGeography(geography);

    expect(
      engine.summarize(state, const []).expectedPollingUnitCount,
      geography.pollingUnits.length,
    );

    final source = geography.pollingUnits.first;
    final extraScope = GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: source.scope.country,
      zoneId: source.scope.zoneId,
      zoneName: source.scope.zoneName,
      stateId: source.scope.stateId,
      stateName: source.scope.stateName,
      senatorialDistrictId: source.scope.senatorialDistrictId,
      senatorialDistrictName: source.scope.senatorialDistrictName,
      lgaId: source.scope.lgaId,
      lgaName: source.scope.lgaName,
      wardId: source.scope.wardId,
      wardName: source.scope.wardName,
      pollingUnitId: 'KD-KN-W01-PU999',
      pollingUnitName: 'PU 999',
    );
    geography.replacePollingUnits([
      ...geography.pollingUnits,
      CanonicalPollingUnit(
        code: 'KD-KN-W01-PU999',
        scope: extraScope,
      ),
    ]);

    final updated = engine.summarize(state, const []);

    expect(updated.expectedPollingUnitCount, geography.pollingUnits.length);
    expect(updated.missingPollingUnitIds, contains('KD-KN-W01-PU999'));
  });
}
