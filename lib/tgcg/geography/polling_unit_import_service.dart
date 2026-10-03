import 'dart:convert';

import '../domain/models.dart';
import 'geography_registry.dart';
import 'kaduna_geography.dart';

class PollingUnitImportIssue {
  const PollingUnitImportIssue({
    required this.row,
    required this.message,
  });

  final int row;
  final String message;
}

class PollingUnitImportResult {
  const PollingUnitImportResult({
    required this.units,
    required this.issues,
  });

  final List<CanonicalPollingUnit> units;
  final List<PollingUnitImportIssue> issues;

  bool get hasErrors => issues.isNotEmpty;
}

class PollingUnitImportService {
  const PollingUnitImportService._();

  /// Parses a canonical JSON polling-unit payload.
  ///
  /// Supported top-level forms:
  /// - a JSON array of polling-unit objects;
  /// - an object containing `polling_units`, `pollingUnits`, or `data`.
  ///
  /// External datasets should be normalized into these fields before import:
  /// `officialCode`, `lgaId`/ `lgaName`, `wardId`/ `wardName`,
  /// `pollingUnitName`, optional `latitude`, `longitude`,
  /// `registeredVoters`, and `referenceSource`.
  static PollingUnitImportResult parseJson(
    String payload, {
    required GeographyRegistry geography,
  }) {
    final decoded = jsonDecode(payload);
    final rows = _rows(decoded);
    final issues = <PollingUnitImportIssue>[];
    final units = <CanonicalPollingUnit>[];
    final internalCodes = <String>{};
    final officialCodes = <String>{};

    for (var index = 0; index < rows.length; index++) {
      final rowNumber = index + 1;
      final row = rows[index];
      try {
        final unit = _parseRow(
          row,
          geography: geography,
          rowNumber: rowNumber,
        );
        final internalKey = _normalizeCode(unit.code);
        final officialKey = _normalizeCode(unit.officialCode ?? '');

        if (!internalCodes.add(internalKey)) {
          issues.add(
            PollingUnitImportIssue(
              row: rowNumber,
              message: 'Duplicate internal polling-unit code: ${unit.code}',
            ),
          );
          continue;
        }
        if (officialKey.isNotEmpty && !officialCodes.add(officialKey)) {
          issues.add(
            PollingUnitImportIssue(
              row: rowNumber,
              message:
                  'Duplicate external polling-unit code: ${unit.officialCode}',
            ),
          );
          continue;
        }

        units.add(unit);
      } on FormatException catch (error) {
        issues.add(
          PollingUnitImportIssue(
            row: rowNumber,
            message: error.message,
          ),
        );
      }
    }

    return PollingUnitImportResult(
      units: List.unmodifiable(units),
      issues: List.unmodifiable(issues),
    );
  }

  static List<Map<String, Object?>> _rows(Object? decoded) {
    Object? value = decoded;
    if (decoded is Map) {
      value = decoded['polling_units'] ??
          decoded['pollingUnits'] ??
          decoded['data'];
    }
    if (value is! List) {
      throw const FormatException(
        'Polling-unit import must contain a JSON array.',
      );
    }

    return value.map((item) {
      if (item is! Map) {
        throw const FormatException(
          'Every polling-unit import row must be a JSON object.',
        );
      }
      return item.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }).toList(growable: false);
  }

  static CanonicalPollingUnit _parseRow(
    Map<String, Object?> row, {
    required GeographyRegistry geography,
    required int rowNumber,
  }) {
    final officialCode = _string(
      row,
      const ['officialCode', 'official_code', 'puCode', 'pu_code'],
    );
    if (officialCode == null) {
      throw FormatException(
        'Row $rowNumber is missing officialCode/puCode.',
      );
    }

    final lga = _resolveLga(row, geography);
    if (lga == null) {
      throw FormatException(
        'Row $rowNumber could not be matched to a Kaduna LGA.',
      );
    }

    final wardName = _string(
      row,
      const ['wardName', 'ward_name', 'ward'],
    );
    if (wardName == null) {
      throw FormatException(
        'Row $rowNumber is missing wardName.',
      );
    }

    final pollingUnitName = _string(
          row,
          const [
            'pollingUnitName',
            'polling_unit_name',
            'puName',
            'pu_name',
            'name',
          ],
        ) ??
        'Polling Unit $officialCode';

    final wardId = _string(
          row,
          const ['wardId', 'ward_id', 'wardCode', 'ward_code'],
        ) ??
        '${lga.id}-W-${_slug(wardName)}';

    final explicitCode = _string(
      row,
      const ['code', 'id', 'pollingUnitId', 'polling_unit_id'],
    );
    final internalCode =
        explicitCode ?? '$kadunaStateId-PU-${_normalizeCode(officialCode)}';

    final latitude = _double(
      row,
      const ['latitude', 'lat', 'referenceLatitude', 'reference_latitude'],
    );
    final longitude = _double(
      row,
      const ['longitude', 'lng', 'lon', 'referenceLongitude', 'reference_longitude'],
    );
    if ((latitude == null) != (longitude == null)) {
      throw FormatException(
        'Row $rowNumber must provide both latitude and longitude.',
      );
    }
    if (latitude != null && (latitude < -90 || latitude > 90)) {
      throw FormatException('Row $rowNumber has an invalid latitude.');
    }
    if (longitude != null && (longitude < -180 || longitude > 180)) {
      throw FormatException('Row $rowNumber has an invalid longitude.');
    }

    final registeredVoters = _int(
      row,
      const ['registeredVoters', 'registered_voters'],
    );
    final source = _string(
          row,
          const ['referenceSource', 'reference_source', 'source'],
        ) ??
        'Imported reference';

    return CanonicalPollingUnit(
      code: internalCode,
      officialCode: officialCode,
      registeredVoters: registeredVoters,
      referenceLatitude: latitude,
      referenceLongitude: longitude,
      referenceSource: latitude == null ? null : source,
      coordinateStatus: latitude == null
          ? PollingUnitCoordinateStatus.missing
          : PollingUnitCoordinateStatus.referenceOnly,
      scope: GeographicScope(
        level: GeographyLevel.pollingUnit,
        country: 'Nigeria',
        zoneId: lga.zoneId,
        zoneName: lga.zoneName,
        stateId: lga.stateId,
        stateName: lga.stateName,
        senatorialDistrictId: lga.senatorialDistrictId,
        senatorialDistrictName: lga.senatorialDistrictName,
        lgaId: lga.id,
        lgaName: lga.name,
        wardId: wardId,
        wardName: wardName,
        pollingUnitId: internalCode,
        pollingUnitName: pollingUnitName,
      ),
    );
  }

  static CanonicalLga? _resolveLga(
    Map<String, Object?> row,
    GeographyRegistry geography,
  ) {
    final id = _string(row, const ['lgaId', 'lga_id']);
    if (id != null) {
      final direct = geography.lga(id);
      if (direct != null) return direct;
    }

    final name = _string(row, const ['lgaName', 'lga_name', 'lga']);
    if (name == null) return null;
    final target = _normalizeName(name);
    for (final lga in geography.lgas) {
      if (_normalizeName(lga.name) == target) return lga;
    }
    return null;
  }

  static String? _string(
    Map<String, Object?> row,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static double? _double(
    Map<String, Object?> row,
    List<String> keys,
  ) {
    final value = _string(row, keys);
    return value == null ? null : double.tryParse(value);
  }

  static int? _int(
    Map<String, Object?> row,
    List<String> keys,
  ) {
    final value = _string(row, keys);
    return value == null ? null : int.tryParse(value.replaceAll(',', ''));
  }

  static String _normalizeCode(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String _normalizeName(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _slug(String value) {
    final slug = value
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'WARD' : slug;
  }
}
