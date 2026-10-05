import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/local_id.dart';

void main() {
  test('local IDs stay unique and ordered when created in the same instant', () {
    final at = DateTime.utc(2026, 10, 5, 12);
    final ids = List.generate(10000, (_) => newLocalId('ASN', at));

    expect(ids.toSet(), hasLength(ids.length));
    final micros = ids.map((id) => int.parse(id.split('-').last)).toList();
    for (var i = 1; i < micros.length; i++) {
      expect(micros[i], greaterThan(micros[i - 1]));
    }
    expect(ids.first, startsWith('ASN-'));
  });
}
