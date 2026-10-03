import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/domain/permissions.dart';

void main() {
  const kaduna = GeographicScope.kaduna;
  const kadunaNorth = GeographicScope(
    level: GeographyLevel.senatorialDistrict,
    country: 'Nigeria',
    zoneId: 'NW',
    zoneName: 'North West',
    stateId: 'KD',
    stateName: 'Kaduna',
    senatorialDistrictId: 'SD/052/KD',
    senatorialDistrictName: 'Kaduna North',
  );
  const zaria = GeographicScope(
    level: GeographyLevel.lga,
    country: 'Nigeria',
    zoneId: 'NW',
    zoneName: 'North West',
    stateId: 'KD',
    stateName: 'Kaduna',
    senatorialDistrictId: 'SD/052/KD',
    senatorialDistrictName: 'Kaduna North',
    lgaId: 'KD-ZARIA',
    lgaName: 'Zaria',
  );
  const sabonGari = GeographicScope(
    level: GeographyLevel.lga,
    country: 'Nigeria',
    zoneId: 'NW',
    zoneName: 'North West',
    stateId: 'KD',
    stateName: 'Kaduna',
    senatorialDistrictId: 'SD/052/KD',
    senatorialDistrictName: 'Kaduna North',
    lgaId: 'KD-SABON-GARI',
    lgaName: 'Sabon Gari',
  );
  const kachia = GeographicScope(
    level: GeographyLevel.lga,
    country: 'Nigeria',
    zoneId: 'NW',
    zoneName: 'North West',
    stateId: 'KD',
    stateName: 'Kaduna',
    senatorialDistrictId: 'SD/054/KD',
    senatorialDistrictName: 'Kaduna South',
    lgaId: 'KD-KACHIA',
    lgaName: 'Kachia',
  );

  group('TgcgPermissionPolicy', () {
    test('state scope can access senatorial zone and LGA records', () {
      expect(TgcgPermissionPolicy.scopeAllows(kaduna, kadunaNorth), isTrue);
      expect(TgcgPermissionPolicy.scopeAllows(kaduna, zaria), isTrue);
      expect(TgcgPermissionPolicy.scopeAllows(kaduna, kachia), isTrue);
    });

    test('senatorial zone coordinator is confined to LGAs in the zone', () {
      expect(TgcgPermissionPolicy.scopeAllows(kadunaNorth, zaria), isTrue);
      expect(TgcgPermissionPolicy.scopeAllows(kadunaNorth, sabonGari), isTrue);
      expect(TgcgPermissionPolicy.scopeAllows(kadunaNorth, kachia), isFalse);
      expect(TgcgPermissionPolicy.scopeAllows(kadunaNorth, kaduna), isFalse);
    });

    test('LGA coordinator is confined to assigned LGA', () {
      expect(TgcgPermissionPolicy.scopeAllows(zaria, zaria), isTrue);
      expect(TgcgPermissionPolicy.scopeAllows(zaria, sabonGari), isFalse);
    });

    test('polling-unit agent can submit results but cannot verify them', () {
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.pollingUnitAgent,
          TgcgCapability.submitElectionResult,
        ),
        isTrue,
      );
      expect(
        TgcgPermissionPolicy.allows(
          TgcgRole.pollingUnitAgent,
          TgcgCapability.verifyElectionResult,
        ),
        isFalse,
      );
    });
  });
}
