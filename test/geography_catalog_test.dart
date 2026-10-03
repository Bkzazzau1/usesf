import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/geography/geography_catalog.dart';

void main() {
  group('GeographyCatalogValidator', () {
    test('accepts a valid Kaduna hierarchy', () {
      final catalog = GeographyCatalog(
        version: '2026.09',
        importedAt: DateTime.utc(2026, 9, 27),
        sourceName: 'test source',
        nodes: const [
          GeographyNode(
            id: 'NG',
            name: 'Nigeria',
            level: GeographyLevel.country,
            code: 'NG',
          ),
          GeographyNode(
            id: 'NG-NW',
            name: 'North West',
            level: GeographyLevel.geopoliticalZone,
            parentId: 'NG',
            code: 'NC',
          ),
          GeographyNode(
            id: 'NG-KD',
            name: 'Kaduna',
            level: GeographyLevel.state,
            parentId: 'NG-NW',
            code: 'BN',
          ),
          GeographyNode(
            id: 'NG-KD-ZAR',
            name: 'Zaria',
            level: GeographyLevel.lga,
            parentId: 'NG-KD',
            code: 'MKD',
          ),
          GeographyNode(
            id: 'NG-KD-ZAR-W01',
            name: 'Ward 01',
            level: GeographyLevel.ward,
            parentId: 'NG-KD-ZAR',
            code: 'W01',
          ),
          GeographyNode(
            id: 'NG-KD-ZAR-W01-PU001',
            name: 'Polling Unit 001',
            level: GeographyLevel.pollingUnit,
            parentId: 'NG-KD-ZAR-W01',
            code: 'PU001',
            latitude: 7.73,
            longitude: 8.54,
          ),
        ],
      );

      final result = GeographyCatalogValidator.validate(catalog);

      expect(result.errorCount, 0);
      expect(result.isValid, isTrue);
    });

    test('rejects a polling unit attached directly to a state', () {
      final catalog = GeographyCatalog(
        version: '2026.09',
        importedAt: DateTime.utc(2026, 9, 27),
        sourceName: 'test source',
        nodes: const [
          GeographyNode(
            id: 'NG',
            name: 'Nigeria',
            level: GeographyLevel.country,
          ),
          GeographyNode(
            id: 'NG-NW',
            name: 'North West',
            level: GeographyLevel.geopoliticalZone,
            parentId: 'NG',
          ),
          GeographyNode(
            id: 'NG-KD',
            name: 'Kaduna',
            level: GeographyLevel.state,
            parentId: 'NG-NW',
          ),
          GeographyNode(
            id: 'BAD-PU',
            name: 'Bad Polling Unit',
            level: GeographyLevel.pollingUnit,
            parentId: 'NG-KD',
            latitude: 7.73,
            longitude: 8.54,
          ),
        ],
      );

      final result = GeographyCatalogValidator.validate(catalog);

      expect(result.isValid, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'INVALID_PARENT_LEVEL'),
        isTrue,
      );
    });
  });
}
