import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/field/field_operations_store.dart';

void main() {
  group('FieldOperationsController', () {
    test('state scope sees all prototype incidents', () {
      final store = FieldOperationsController.prototypeSeed();

      expect(store.incidentsForScope(GeographicScope.kaduna).length, 5);
      expect(store.reportsForScope(GeographicScope.kaduna).length, 3);
    });

    test('senatorial zone scope only sees matching zone records', () {
      final store = FieldOperationsController.prototypeSeed();
      const kadunaSouth = GeographicScope(
        level: GeographyLevel.senatorialDistrict,
        country: 'Nigeria',
        zoneId: 'NW',
        zoneName: 'North West',
        stateId: 'KD',
        stateName: 'Kaduna',
        senatorialDistrictId: 'SD/054/KD',
        senatorialDistrictName: 'Kaduna South',
      );

      final all = store.incidentsForScope(GeographicScope.kaduna);
      final incidents = store.incidentsForScope(kadunaSouth);

      expect(incidents, isNotEmpty);
      expect(incidents.length, lessThan(all.length));
      expect(
        incidents.every((item) => item.scope.senatorialDistrictId == 'SD/054/KD'),
        isTrue,
      );
    });

    test('incident status update is shared operational state', () {
      final store = FieldOperationsController.prototypeSeed();
      final before = store.incidents.firstWhere((item) => item.id == 'INC-0004');
      expect(before.status, IncidentStatus.reported);

      store.updateIncidentStatus('INC-0004', IncidentStatus.acknowledged);

      final after = store.incidents.firstWhere((item) => item.id == 'INC-0004');
      expect(after.status, IncidentStatus.acknowledged);
    });
  });
}
