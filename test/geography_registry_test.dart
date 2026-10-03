import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';

void main() {
  group('GeographyRegistry', () {
    final registry = GeographyRegistry.prototypeSeed();

    test('resolves a canonical polling unit by code', () {
      final unit = registry.pollingUnit('KD-KN-W01-PU001');

      expect(unit, isNotNull);
      expect(unit!.scope.level, GeographyLevel.pollingUnit);
      expect(unit.scope.stateName, 'Kaduna');
      expect(unit.scope.senatorialDistrictName, 'Kaduna Central');
      expect(unit.scope.lgaName, 'Kaduna North');
    });

    test('Kaduna State is the root and its children are the three senatorial zones', () {
      final children = registry.childScopes(GeographicScope.kaduna);

      expect(GeographicScope.kaduna.level, GeographyLevel.state);
      expect(GeographicScope.kaduna.label, 'Kaduna State');
      expect(
        children.map((scope) => scope.senatorialDistrictName).toList(),
        ['Kaduna North', 'Kaduna Central', 'Kaduna South'],
      );
      expect(
        children.every(
          (scope) => scope.level == GeographyLevel.senatorialDistrict,
        ),
        isTrue,
      );
    });

    test('Kaduna has 23 LGAs, each in exactly one senatorial zone', () {
      expect(registry.senatorialDistrictCount, 3);
      expect(registry.lgaCount, 23);
      expect(
        registry.senatorialDistricts
            .map((district) => registry.lgasForDistrict(district.id).length)
            .toList(),
        [8, 7, 8],
      );

      final lgaIds = registry.senatorialDistricts
          .expand((district) => registry.lgasForDistrict(district.id))
          .map((lga) => lga.id)
          .toList();
      expect(lgaIds.toSet().length, 23);
      expect(lgaIds.toSet(), registry.lgas.map((lga) => lga.id).toSet());
    });

    test('only Kaduna geography is registered', () {
      expect(registry.states.map((state) => state.id), ['KD']);
      expect(
        registry.pollingUnits.every((unit) => unit.scope.stateId == 'KD'),
        isTrue,
      );
      expect(registry.lgasForState('LA'), isEmpty);
      expect(registry.districtsForState('BN'), isEmpty);
    });

    test('state drill-down follows senatorial zone, LGA, ward and polling unit', () {
      final kadunaDistricts = registry.childScopes(GeographicScope.kaduna);
      final kadunaCentral = kadunaDistricts.firstWhere(
        (scope) => scope.senatorialDistrictId == 'SD/053/KD',
      );
      final centralLgas = registry.childScopes(kadunaCentral);
      final kadunaNorth = centralLgas.firstWhere(
        (scope) => scope.lgaId == 'KD-KADUNA-NORTH',
      );
      final wards = registry.childScopes(kadunaNorth);
      final ward = wards.single;
      final pollingUnits = registry.childScopes(ward);

      expect(kadunaCentral.senatorialDistrictName, 'Kaduna Central');
      expect(centralLgas.length, 7);
      expect(
        centralLgas.every((scope) => scope.level == GeographyLevel.lga),
        isTrue,
      );
      expect(kadunaNorth.lgaName, 'Kaduna North');
      expect(ward.level, GeographyLevel.ward);
      expect(pollingUnits.length, 2);
      expect(
        pollingUnits.every(
          (scope) => scope.level == GeographyLevel.pollingUnit,
        ),
        isTrue,
      );
    });

    test('senatorial zone containment rejects another zone', () {
      final central = registry.pollingUnit('KD-KN-W01-PU001')!.scope;
      final south = registry.pollingUnit('KD-JM-W03-PU012')!.scope;
      final kadunaCentral = registry.senatorialDistrict('SD/053/KD')!.scope;

      expect(GeographyRegistry.scopeContains(GeographicScope.kaduna, central), isTrue);
      expect(GeographyRegistry.scopeContains(GeographicScope.kaduna, south), isTrue);
      expect(GeographyRegistry.scopeContains(kadunaCentral, central), isTrue);
      expect(GeographyRegistry.scopeContains(kadunaCentral, south), isFalse);
    });
  });
}
