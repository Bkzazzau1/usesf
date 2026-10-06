import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/session.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Persistent login sessions', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('authenticated session restores after controller reconstruction',
        () async {
      final first = TgcgSessionController();
      await first.signIn(
        role: TgcgRole.stateCoordinator,
        operatorName: 'State Coordinator',
        accessId: 'STATE-001',
        scope: GeographicScope.kaduna,
      );

      final restored = TgcgSessionController();
      await restored.restorePersistedSession();

      expect(restored.isAuthenticated, isTrue);
      expect(restored.role, TgcgRole.stateCoordinator);
      expect(restored.operatorName, 'State Coordinator');
      expect(restored.accessId, 'STATE-001');
      expect(restored.scope.stateId, 'KD');
    });

    test('security session token survives app-style reconstruction', () async {
      final first = TgcgSessionController();
      await first.signIn(
        role: TgcgRole.securityOfficer,
        operatorName: 'Insp. Musa Bello',
        accessId: 'AP/12345',
        agencyId: 'AGENCY-POLICE',
        scope: GeographicScope.kaduna,
        securitySessionToken: 'persistent-device-session',
      );

      final restored = TgcgSessionController();
      await restored.restorePersistedSession();

      expect(restored.isAuthenticated, isTrue);
      expect(restored.role, TgcgRole.securityOfficer);
      expect(restored.agencyId, 'AGENCY-POLICE');
      expect(
        restored.securitySessionToken,
        'persistent-device-session',
      );
    });

    test('explicit sign-out clears the persisted device session', () async {
      final first = TgcgSessionController();
      await first.signIn(
        role: TgcgRole.member,
        operatorName: 'Member',
        accessId: 'MEM-001',
        scope: GeographicScope.kaduna,
      );
      await first.signOut();

      final restored = TgcgSessionController();
      await restored.restorePersistedSession();

      expect(first.isAuthenticated, isFalse);
      expect(restored.isAuthenticated, isFalse);
      expect(
        first.lastTerminationReason,
        SessionTerminationReason.explicitSignOut,
      );
    });

    test('scope changes remain persisted without forcing re-login', () async {
      const zaria = GeographicScope(
        level: GeographyLevel.lga,
        country: 'Nigeria',
        zoneId: 'NW',
        stateId: 'KD',
        lgaId: 'KD-ZARIA',
        lgaName: 'Zaria',
      );
      final first = TgcgSessionController();
      await first.signIn(
        role: TgcgRole.lgaCoordinator,
        operatorName: 'LGA Coordinator',
        accessId: 'LGA-001',
        scope: GeographicScope.kaduna,
      );
      first.updateScope(zaria);
      await Future<void>.delayed(Duration.zero);

      final restored = TgcgSessionController();
      await restored.restorePersistedSession();

      expect(restored.isAuthenticated, isTrue);
      expect(restored.scope.lgaId, 'KD-ZARIA');
    });
  });

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
