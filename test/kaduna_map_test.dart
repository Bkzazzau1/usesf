import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/geography/kaduna_lga_shapes.dart';
import 'package:usesf/tgcg/geography/kaduna_map.dart';

void main() {
  test('map has one shape per Kaduna LGA, each in a senatorial zone', () {
    final registryIds = GeographyRegistry.prototypeSeed().lgas.map((lga) => lga.id).toSet();
    final shapeIds = kadunaLgaShapes.map((shape) => shape.lgaId).toSet();

    expect(kadunaLgaShapes.length, 23);
    expect(shapeIds, registryIds);
    expect(shapeIds.every(kadunaLgaDistrict.containsKey), isTrue);
    expect(
      kadunaLgaShapes.every((shape) => shape.rings.every((ring) => ring.length >= 6 && ring.length.isEven)),
      isTrue,
    );
  });

  test('zone colouring follows INEC senatorial districts', () {
    int count(String code) => kadunaLgaDistrict.values.where((value) => value == code).length;
    expect([count('SD/052/KD'), count('SD/053/KD'), count('SD/054/KD')], [8, 7, 8]);
    expect(kadunaLgaDistrict['KD-KAURU'], 'SD/054/KD');
    expect(kadunaLgaDistrict['KD-KUBAU'], 'SD/052/KD');
  });
}
