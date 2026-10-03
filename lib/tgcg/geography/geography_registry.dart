import 'dart:math' as math;

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

enum PollingUnitCoordinateStatus {
  missing,
  referenceOnly,
  fieldVerified,
  needsReview,
}

class CanonicalPollingUnit {
  const CanonicalPollingUnit({
    required this.code,
    required this.scope,
    this.officialCode,
    this.registeredVoters,
    this.referenceLatitude,
    this.referenceLongitude,
    this.referenceSource,
    this.verifiedLatitude,
    this.verifiedLongitude,
    this.verificationAccuracyMeters,
    this.verifiedBy,
    this.verifiedAt,
    this.coordinateStatus = PollingUnitCoordinateStatus.missing,
    this.geofenceRadiusMeters = 120,
  });

  /// Internal stable USESF polling-unit identifier.
  final String code;

  /// External/reference polling-unit code, when imported from an authoritative
  /// source. This remains separate from [code] so imports can be reconciled
  /// without changing internal relationships.
  final String? officialCode;
  final GeographicScope scope;
  final int? registeredVoters;

  /// Reference coordinates are imported and never silently overwritten by
  /// field verification.
  final double? referenceLatitude;
  final double? referenceLongitude;
  final String? referenceSource;

  /// Field-verified coordinates are captured on location by an authorized
  /// USESF device. They are kept separately for audit and reconciliation.
  final double? verifiedLatitude;
  final double? verifiedLongitude;
  final double? verificationAccuracyMeters;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final PollingUnitCoordinateStatus coordinateStatus;
  final double geofenceRadiusMeters;

  String get displayCode => officialCode?.trim().isNotEmpty == true
      ? officialCode!.trim()
      : code;

  bool get hasReferenceCoordinate =>
      referenceLatitude != null && referenceLongitude != null;

  bool get hasVerifiedCoordinate =>
      verifiedLatitude != null && verifiedLongitude != null;

  double? get operationalLatitude =>
      hasVerifiedCoordinate ? verifiedLatitude : referenceLatitude;

  double? get operationalLongitude =>
      hasVerifiedCoordinate ? verifiedLongitude : referenceLongitude;

  double? get referenceToVerifiedDistanceMeters {
    if (!hasReferenceCoordinate || !hasVerifiedCoordinate) return null;
    return _distanceMeters(
      referenceLatitude!,
      referenceLongitude!,
      verifiedLatitude!,
      verifiedLongitude!,
    );
  }

  CanonicalPollingUnit withReferenceCoordinate({
    required double latitude,
    required double longitude,
    required String source,
    String? externalCode,
  }) =>
      CanonicalPollingUnit(
        code: code,
        officialCode: externalCode ?? officialCode,
        scope: scope,
        registeredVoters: registeredVoters,
        referenceLatitude: latitude,
        referenceLongitude: longitude,
        referenceSource: source,
        verifiedLatitude: verifiedLatitude,
        verifiedLongitude: verifiedLongitude,
        verificationAccuracyMeters: verificationAccuracyMeters,
        verifiedBy: verifiedBy,
        verifiedAt: verifiedAt,
        coordinateStatus: hasVerifiedCoordinate
            ? coordinateStatus
            : PollingUnitCoordinateStatus.referenceOnly,
        geofenceRadiusMeters: geofenceRadiusMeters,
      );

  CanonicalPollingUnit withFieldVerification({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required String verifiedBy,
    required DateTime verifiedAt,
    double reviewThresholdMeters = 150,
  }) {
    final difference = hasReferenceCoordinate
        ? _distanceMeters(
            referenceLatitude!,
            referenceLongitude!,
            latitude,
            longitude,
          )
        : null;
    final status = difference != null && difference > reviewThresholdMeters
        ? PollingUnitCoordinateStatus.needsReview
        : PollingUnitCoordinateStatus.fieldVerified;

    return CanonicalPollingUnit(
      code: code,
      officialCode: officialCode,
      scope: scope,
      registeredVoters: registeredVoters,
      referenceLatitude: referenceLatitude,
      referenceLongitude: referenceLongitude,
      referenceSource: referenceSource,
      verifiedLatitude: latitude,
      verifiedLongitude: longitude,
      verificationAccuracyMeters: accuracyMeters,
      verifiedBy: verifiedBy,
      verifiedAt: verifiedAt.toUtc(),
      coordinateStatus: status,
      geofenceRadiusMeters: geofenceRadiusMeters,
    );
  }

  CanonicalPollingUnit withGeofenceRadius(double radiusMeters) =>
      CanonicalPollingUnit(
        code: code,
        officialCode: officialCode,
        scope: scope,
        registeredVoters: registeredVoters,
        referenceLatitude: referenceLatitude,
        referenceLongitude: referenceLongitude,
        referenceSource: referenceSource,
        verifiedLatitude: verifiedLatitude,
        verifiedLongitude: verifiedLongitude,
        verificationAccuracyMeters: verificationAccuracyMeters,
        verifiedBy: verifiedBy,
        verifiedAt: verifiedAt,
        coordinateStatus: coordinateStatus,
        geofenceRadiusMeters: radiusMeters,
      );

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    double radians(double degrees) => degrees * math.pi / 180;
    final dLat = radians(lat2 - lat1);
    final dLon = radians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(radians(lat1)) *
            math.cos(radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }
}

class GeographyRegistry {
  GeographyRegistry({
    this.zones = const [],
    this.states = const [],
    required List<CanonicalPollingUnit> pollingUnits,
  }) : pollingUnits = List<CanonicalPollingUnit>.of(pollingUnits);

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

  factory GeographyRegistry.prototypeSeed() => GeographyRegistry(
        zones: const [kadunaZone],
        states: const [kaduna],
        pollingUnits: const [
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
    final target = _normalizePollingUnitCode(id);
    for (final unit in pollingUnits) {
      if (_normalizePollingUnitCode(unit.code) == target ||
          _normalizePollingUnitCode(unit.scope.pollingUnitId ?? '') == target ||
          _normalizePollingUnitCode(unit.officialCode ?? '') == target) {
        return unit;
      }
    }
    return null;
  }

  CanonicalPollingUnit? pollingUnitByOfficialCode(String code) {
    final target = _normalizePollingUnitCode(code);
    if (target.isEmpty) return null;
    for (final unit in pollingUnits) {
      if (_normalizePollingUnitCode(unit.officialCode ?? '') == target) {
        return unit;
      }
    }
    return null;
  }

  int get coordinateReadyCount => pollingUnits
      .where((unit) => unit.operationalLatitude != null && unit.operationalLongitude != null)
      .length;

  int get fieldVerifiedCoordinateCount => pollingUnits
      .where(
        (unit) =>
            unit.coordinateStatus == PollingUnitCoordinateStatus.fieldVerified,
      )
      .length;

  int get coordinateReviewCount => pollingUnits
      .where(
        (unit) =>
            unit.coordinateStatus == PollingUnitCoordinateStatus.needsReview,
      )
      .length;

  CanonicalPollingUnit verifyPollingUnitCoordinate({
    required String pollingUnitId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required String verifiedBy,
    DateTime? verifiedAt,
    double reviewThresholdMeters = 150,
  }) {
    final index = pollingUnits.indexWhere(
      (unit) =>
          _normalizePollingUnitCode(unit.code) ==
              _normalizePollingUnitCode(pollingUnitId) ||
          _normalizePollingUnitCode(unit.scope.pollingUnitId ?? '') ==
              _normalizePollingUnitCode(pollingUnitId) ||
          _normalizePollingUnitCode(unit.officialCode ?? '') ==
              _normalizePollingUnitCode(pollingUnitId),
    );
    if (index < 0) {
      throw ArgumentError('Unknown polling unit: $pollingUnitId');
    }
    final updated = pollingUnits[index].withFieldVerification(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      verifiedBy: verifiedBy,
      verifiedAt: verifiedAt ?? DateTime.now().toUtc(),
      reviewThresholdMeters: reviewThresholdMeters,
    );
    pollingUnits[index] = updated;
    return updated;
  }

  CanonicalPollingUnit setPollingUnitReferenceCoordinate({
    required String pollingUnitId,
    required double latitude,
    required double longitude,
    required String source,
    String? officialCode,
  }) {
    final index = pollingUnits.indexWhere(
      (unit) =>
          _normalizePollingUnitCode(unit.code) ==
              _normalizePollingUnitCode(pollingUnitId) ||
          _normalizePollingUnitCode(unit.scope.pollingUnitId ?? '') ==
              _normalizePollingUnitCode(pollingUnitId) ||
          _normalizePollingUnitCode(unit.officialCode ?? '') ==
              _normalizePollingUnitCode(pollingUnitId),
    );
    if (index < 0) {
      throw ArgumentError('Unknown polling unit: $pollingUnitId');
    }
    final updated = pollingUnits[index].withReferenceCoordinate(
      latitude: latitude,
      longitude: longitude,
      source: source,
      externalCode: officialCode,
    );
    pollingUnits[index] = updated;
    return updated;
  }

  void replacePollingUnits(Iterable<CanonicalPollingUnit> units) {
    final replacement = units.toList(growable: false);
    final keys = <String>{};
    for (final unit in replacement) {
      final key = _normalizePollingUnitCode(unit.code);
      if (key.isEmpty || !keys.add(key)) {
        throw ArgumentError('Polling-unit registry contains a duplicate/empty code.');
      }
      if (unit.scope.stateId != kadunaStateId ||
          unit.scope.level != GeographyLevel.pollingUnit) {
        throw ArgumentError(
          'Polling-unit registry may only contain Kaduna polling-unit scopes.',
        );
      }
    }
    pollingUnits
      ..clear()
      ..addAll(replacement);
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

  static String _normalizePollingUnitCode(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

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
