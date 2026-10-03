import '../domain/models.dart';
import 'kaduna_geography.dart';

class CanonicalZone {
  const CanonicalZone({required this.id, required this.name});

  final String id;
  final String name;

  GeographicScope get scope => GeographicScope(
        level: GeographyLevel.geopoliticalZone,
        country: 'Nigeria',
        zoneId: id,
        zoneName: name,
      );
}

class CanonicalState {
  const CanonicalState({
    required this.id,
    required this.name,
    required this.zoneId,
    required this.zoneName,
  });

  final String id;
  final String name;
  final String zoneId;
  final String zoneName;

  GeographicScope get scope => GeographicScope(
        level: GeographyLevel.state,
        country: 'Nigeria',
        zoneId: zoneId,
        zoneName: zoneName,
        stateId: id,
        stateName: name,
      );
}

class CanonicalSenatorialDistrict {
  const CanonicalSenatorialDistrict({
    required this.id,
    required this.name,
    required this.stateId,
    required this.stateName,
    required this.zoneId,
    required this.zoneName,
    required this.lgaSlugs,
  });

  final String id;
  final String name;
  final String stateId;
  final String stateName;
  final String zoneId;
  final String zoneName;
  final List<String> lgaSlugs;

  GeographicScope get scope => GeographicScope(
        level: GeographyLevel.senatorialDistrict,
        country: 'Nigeria',
        zoneId: zoneId,
        zoneName: zoneName,
        stateId: stateId,
        stateName: stateName,
        senatorialDistrictId: id,
        senatorialDistrictName: name,
      );
}

class CanonicalLga {
  const CanonicalLga({
    required this.id,
    required this.name,
    required this.stateId,
    required this.stateName,
    required this.zoneId,
    required this.zoneName,
    required this.senatorialDistrictId,
    required this.senatorialDistrictName,
  });

  final String id;
  final String name;
  final String stateId;
  final String stateName;
  final String zoneId;
  final String zoneName;
  final String senatorialDistrictId;
  final String senatorialDistrictName;

  GeographicScope get scope => GeographicScope(
        level: GeographyLevel.lga,
        country: 'Nigeria',
        zoneId: zoneId,
        zoneName: zoneName,
        stateId: stateId,
        stateName: stateName,
        senatorialDistrictId: senatorialDistrictId,
        senatorialDistrictName: senatorialDistrictName,
        lgaId: id,
        lgaName: name,
      );
}

class CanonicalPollingUnit {
  const CanonicalPollingUnit({
    required this.code,
    required this.scope,
    this.registeredVoters,
  });

  final String code;
  final GeographicScope scope;
  final int? registeredVoters;
}

class GeographyRegistry {
  const GeographyRegistry({
    this.zones = const [],
    this.states = const [],
    required this.pollingUnits,
  });

  final List<CanonicalZone> zones;
  final List<CanonicalState> states;
  final List<CanonicalPollingUnit> pollingUnits;

  /// Kaduna State is the operational root; zone and country are retained
  /// only as parent metadata on every record.
  static const kadunaZone = CanonicalZone(id: 'NW', name: 'North West');
  static const kaduna = CanonicalState(
    id: kadunaStateId,
    name: kadunaStateName,
    zoneId: 'NW',
    zoneName: 'North West',
  );

  factory GeographyRegistry.prototypeSeed() => const GeographyRegistry(
        zones: [kadunaZone],
        states: [kaduna],
        pollingUnits: [
          CanonicalPollingUnit(
            code: 'KD-KN-W01-PU001',
            registeredVoters: 481,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'NW',
              zoneName: 'North West',
              stateId: kadunaStateId,
              stateName: kadunaStateName,
              senatorialDistrictId: 'SD/053/KD',
              senatorialDistrictName: 'Kaduna Central',
              lgaId: 'KD-KADUNA-NORTH',
              lgaName: 'Kaduna North',
              wardId: 'KD-KN-W01',
              wardName: 'Ward 01',
              pollingUnitId: 'KD-KN-W01-PU001',
              pollingUnitName: 'PU 001',
            ),
          ),
          CanonicalPollingUnit(
            code: 'KD-KN-W01-PU002',
            registeredVoters: 436,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'NW',
              zoneName: 'North West',
              stateId: kadunaStateId,
              stateName: kadunaStateName,
              senatorialDistrictId: 'SD/053/KD',
              senatorialDistrictName: 'Kaduna Central',
              lgaId: 'KD-KADUNA-NORTH',
              lgaName: 'Kaduna North',
              wardId: 'KD-KN-W01',
              wardName: 'Ward 01',
              pollingUnitId: 'KD-KN-W01-PU002',
              pollingUnitName: 'PU 002',
            ),
          ),
          CanonicalPollingUnit(
            code: 'KD-ZA-W01-PU004',
            registeredVoters: 502,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'NW',
              zoneName: 'North West',
              stateId: kadunaStateId,
              stateName: kadunaStateName,
              senatorialDistrictId: 'SD/052/KD',
              senatorialDistrictName: 'Kaduna North',
              lgaId: 'KD-ZARIA',
              lgaName: 'Zaria',
              wardId: 'KD-ZA-W01',
              wardName: 'Ward 01',
              pollingUnitId: 'KD-ZA-W01-PU004',
              pollingUnitName: 'PU 004',
            ),
          ),
          CanonicalPollingUnit(
            code: 'KD-ZA-W01-PU005',
            registeredVoters: 391,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'NW',
              zoneName: 'North West',
              stateId: kadunaStateId,
              stateName: kadunaStateName,
              senatorialDistrictId: 'SD/052/KD',
              senatorialDistrictName: 'Kaduna North',
              lgaId: 'KD-ZARIA',
              lgaName: 'Zaria',
              wardId: 'KD-ZA-W01',
              wardName: 'Ward 01',
              pollingUnitId: 'KD-ZA-W01-PU005',
              pollingUnitName: 'PU 005',
            ),
          ),
          CanonicalPollingUnit(
            code: 'KD-JM-W03-PU012',
            registeredVoters: 612,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'NW',
              zoneName: 'North West',
              stateId: kadunaStateId,
              stateName: kadunaStateName,
              senatorialDistrictId: 'SD/054/KD',
              senatorialDistrictName: 'Kaduna South',
              lgaId: 'KD-JEMAA',
              lgaName: "Jema'a",
              wardId: 'KD-JM-W03',
              wardName: 'Ward 03',
              pollingUnitId: 'KD-JM-W03-PU012',
              pollingUnitName: 'PU 012',
            ),
          ),
          CanonicalPollingUnit(
            code: 'KD-JM-W03-PU013',
            registeredVoters: 577,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'NW',
              zoneName: 'North West',
              stateId: kadunaStateId,
              stateName: kadunaStateName,
              senatorialDistrictId: 'SD/054/KD',
              senatorialDistrictName: 'Kaduna South',
              lgaId: 'KD-JEMAA',
              lgaName: "Jema'a",
              wardId: 'KD-JM-W03',
              wardName: 'Ward 03',
              pollingUnitId: 'KD-JM-W03-PU013',
              pollingUnitName: 'PU 013',
            ),
          ),
        ],
      );

  CanonicalZone? zone(String id) {
    for (final item in zones) {
      if (item.id == id) return item;
    }
    return null;
  }

  CanonicalState? state(String id) {
    for (final item in states) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<CanonicalState> statesForZone(String zoneId) => states
      .where((item) => item.zoneId == zoneId)
      .toList(growable: false);

  List<CanonicalSenatorialDistrict> get senatorialDistricts => states
      .expand((item) => districtsForState(item.id))
      .toList(growable: false);

  int get senatorialDistrictCount => senatorialDistricts.length;

  List<CanonicalSenatorialDistrict> districtsForState(String stateId) {
    final stateItem = state(stateId);
    if (stateItem == null) return const [];
    if (stateId != kadunaStateId) return const [];
    return kadunaSenatorialDistricts
        .map(
          (seed) => CanonicalSenatorialDistrict(
            id: seed.code,
            name: seed.name,
            stateId: stateItem.id,
            stateName: stateItem.name,
            zoneId: stateItem.zoneId,
            zoneName: stateItem.zoneName,
            lgaSlugs: seed.lgaSlugs,
          ),
        )
        .toList(growable: false);
  }

  CanonicalSenatorialDistrict? senatorialDistrict(String id) {
    for (final item in senatorialDistricts) {
      if (item.id == id) return item;
    }
    return null;
  }

  CanonicalSenatorialDistrict? districtForLgaSlug(
    String stateId,
    String slug,
  ) {
    for (final district in districtsForState(stateId)) {
      if (district.lgaSlugs.contains(slug)) return district;
    }
    return null;
  }

  List<CanonicalLga> get lgas => states
      .expand((item) => lgasForState(item.id))
      .toList(growable: false);

  int get lgaCount => lgas.length;

  List<CanonicalLga> lgasForState(String stateId) {
    final stateItem = state(stateId);
    if (stateItem == null) return const [];
    if (stateId != kadunaStateId) return const [];
    return kadunaLgaSlugs
        .map((slug) {
          final district = districtForLgaSlug(stateId, slug);
          if (district == null) return null;
          return _lgaFromSlug(stateItem, district, slug);
        })
        .whereType<CanonicalLga>()
        .toList(growable: false);
  }

  List<CanonicalLga> lgasForDistrict(String districtId) {
    final district = senatorialDistrict(districtId);
    if (district == null) return const [];
    final stateItem = state(district.stateId);
    if (stateItem == null) return const [];
    return district.lgaSlugs
        .map((slug) => _lgaFromSlug(stateItem, district, slug))
        .toList(growable: false);
  }

  CanonicalLga _lgaFromSlug(
    CanonicalState stateItem,
    CanonicalSenatorialDistrict district,
    String slug,
  ) =>
      CanonicalLga(
        id: '${stateItem.id}-${slug.toUpperCase().replaceAll("'", '')}',
        name: kadunaLgaDisplayName(slug),
        stateId: stateItem.id,
        stateName: stateItem.name,
        zoneId: stateItem.zoneId,
        zoneName: stateItem.zoneName,
        senatorialDistrictId: district.id,
        senatorialDistrictName: district.name,
      );

  CanonicalLga? lga(String id) {
    for (final item in lgas) {
      if (item.id == id) return item;
    }
    return null;
  }

  CanonicalPollingUnit? pollingUnit(String id) {
    for (final unit in pollingUnits) {
      if (unit.code == id || unit.scope.pollingUnitId == id) return unit;
    }
    return null;
  }

  List<CanonicalPollingUnit> pollingUnitsWithin(GeographicScope scope) =>
      pollingUnits
          .where((unit) => scopeContains(scope, unit.scope))
          .toList(growable: false);

  List<GeographicScope> childScopes(GeographicScope parent) {
    if (parent.level == GeographyLevel.country && zones.isNotEmpty) {
      return zones.map((item) => item.scope).toList(growable: false);
    }
    if (parent.level == GeographyLevel.geopoliticalZone && states.isNotEmpty) {
      return statesForZone(parent.zoneId ?? '')
          .map((item) => item.scope)
          .toList(growable: false);
    }
    if (parent.level == GeographyLevel.state) {
      return districtsForState(parent.stateId ?? '')
          .map((item) => item.scope)
          .toList(growable: false);
    }
    if (parent.level == GeographyLevel.senatorialDistrict) {
      return lgasForDistrict(parent.senatorialDistrictId ?? '')
          .map((item) => item.scope)
          .toList(growable: false);
    }

    final values = <String, GeographicScope>{};
    for (final unit in pollingUnitsWithin(parent)) {
      final child = directChild(parent.level, unit.scope);
      if (child != null) values[_key(child)] = child;
    }
    final result = values.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return result;
  }

  GeographicScope? directChild(
    GeographyLevel parentLevel,
    GeographicScope unit,
  ) => switch (parentLevel) {
        GeographyLevel.country => GeographicScope(
            level: GeographyLevel.geopoliticalZone,
            country: unit.country,
            zoneId: unit.zoneId,
            zoneName: unit.zoneName,
          ),
        GeographyLevel.geopoliticalZone => GeographicScope(
            level: GeographyLevel.state,
            country: unit.country,
            zoneId: unit.zoneId,
            zoneName: unit.zoneName,
            stateId: unit.stateId,
            stateName: unit.stateName,
          ),
        GeographyLevel.state => GeographicScope(
            level: GeographyLevel.senatorialDistrict,
            country: unit.country,
            zoneId: unit.zoneId,
            zoneName: unit.zoneName,
            stateId: unit.stateId,
            stateName: unit.stateName,
            senatorialDistrictId: unit.senatorialDistrictId,
            senatorialDistrictName: unit.senatorialDistrictName,
          ),
        GeographyLevel.senatorialDistrict => GeographicScope(
            level: GeographyLevel.lga,
            country: unit.country,
            zoneId: unit.zoneId,
            zoneName: unit.zoneName,
            stateId: unit.stateId,
            stateName: unit.stateName,
            senatorialDistrictId: unit.senatorialDistrictId,
            senatorialDistrictName: unit.senatorialDistrictName,
            lgaId: unit.lgaId,
            lgaName: unit.lgaName,
          ),
        GeographyLevel.lga => GeographicScope(
            level: GeographyLevel.ward,
            country: unit.country,
            zoneId: unit.zoneId,
            zoneName: unit.zoneName,
            stateId: unit.stateId,
            stateName: unit.stateName,
            senatorialDistrictId: unit.senatorialDistrictId,
            senatorialDistrictName: unit.senatorialDistrictName,
            lgaId: unit.lgaId,
            lgaName: unit.lgaName,
            wardId: unit.wardId,
            wardName: unit.wardName,
          ),
        GeographyLevel.ward => unit,
        GeographyLevel.pollingUnit => null,
      };

  static bool scopeContains(GeographicScope parent, GeographicScope child) {
    if (parent.country != child.country) return false;
    if (parent.level == GeographyLevel.country) return true;
    if (parent.zoneId != null && parent.zoneId != child.zoneId) return false;
    if (parent.level == GeographyLevel.geopoliticalZone) return true;
    if (parent.stateId != null && parent.stateId != child.stateId) return false;
    if (parent.level == GeographyLevel.state) return true;
    if (parent.senatorialDistrictId != null &&
        parent.senatorialDistrictId != child.senatorialDistrictId) {
      return false;
    }
    if (parent.level == GeographyLevel.senatorialDistrict) return true;
    if (parent.lgaId != null && parent.lgaId != child.lgaId) return false;
    if (parent.level == GeographyLevel.lga) return true;
    if (parent.wardId != null && parent.wardId != child.wardId) return false;
    if (parent.level == GeographyLevel.ward) return true;
    return parent.pollingUnitId == child.pollingUnitId;
  }

  static String _key(GeographicScope scope) => switch (scope.level) {
        GeographyLevel.country => scope.country,
        GeographyLevel.geopoliticalZone => scope.zoneId ?? scope.label,
        GeographyLevel.state => scope.stateId ?? scope.label,
        GeographyLevel.senatorialDistrict =>
          scope.senatorialDistrictId ?? scope.label,
        GeographyLevel.lga => scope.lgaId ?? scope.label,
        GeographyLevel.ward => scope.wardId ?? scope.label,
        GeographyLevel.pollingUnit => scope.pollingUnitId ?? scope.label,
      };
}
