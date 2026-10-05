import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/session.dart';

void main() {
  group('USESF role-aware modules', () {
    test('polling unit agent sees operational submission modules only', () {
      final modules = allowedModules(TgcgRole.pollingUnitAgent);

      expect(modules, contains(TgcgModule.overview));
      expect(modules, contains(TgcgModule.geography));
      expect(modules, contains(TgcgModule.fieldMonitoring));
      expect(modules, contains(TgcgModule.resultCapture));
      expect(modules, contains(TgcgModule.communications));

      expect(modules, isNot(contains(TgcgModule.memberEnrollment)));
      expect(modules, isNot(contains(TgcgModule.collation)));
      expect(modules, isNot(contains(TgcgModule.governance)));
    });

    test('state administrator sees every application module', () {
      final modules = allowedModules(TgcgRole.stateAdministrator);
      expect(modules, containsAll(TgcgModule.values));
    });

    test('read only executive has no submission or member-enrolment routes', () {
      final modules = allowedModules(TgcgRole.readOnlyExecutive);

      expect(modules, contains(TgcgModule.overview));
      expect(modules, contains(TgcgModule.situationRoom));
      expect(modules, contains(TgcgModule.collation));
      expect(modules, contains(TgcgModule.reports));
      expect(modules, contains(TgcgModule.governance));

      expect(modules, isNot(contains(TgcgModule.memberEnrollment)));
      expect(modules, isNot(contains(TgcgModule.resultCapture)));
    });
  });
}
