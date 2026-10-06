import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/session.dart';

void main() {
  group('Security responder session lifetime', () {
    test('inactivity expires a security session', () {
      var now = DateTime.utc(2026, 10, 6, 17);
      final session = TgcgSessionController(clock: () => now)
        ..signIn(
          role: TgcgRole.securityOfficer,
          operatorName: 'Responder',
          accessId: 'AP/100',
          agencyId: 'AGENCY-POLICE',
        );

      now = now.add(const Duration(minutes: 15));
      expect(session.enforceSecurityExpiry(), isTrue);
      expect(session.isAuthenticated, isFalse);
      expect(
        session.lastTerminationReason,
        SessionTerminationReason.inactivityTimeout,
      );
    });

    test('late activity cannot revive an already idle session', () {
      var now = DateTime.utc(2026, 10, 6, 17);
      final session = TgcgSessionController(clock: () => now)
        ..signIn(
          role: TgcgRole.securityOfficer,
          operatorName: 'Responder',
          accessId: 'AP/100B',
          agencyId: 'AGENCY-POLICE',
        );

      now = now.add(const Duration(minutes: 16));
      session.recordActivity();

      expect(session.isAuthenticated, isFalse);
      expect(
        session.lastTerminationReason,
        SessionTerminationReason.inactivityTimeout,
      );
    });

    test('activity cannot extend a security session beyond eight hours', () {
      var now = DateTime.utc(2026, 10, 6, 8);
      final session = TgcgSessionController(clock: () => now)
        ..signIn(
          role: TgcgRole.securityOfficer,
          operatorName: 'Responder',
          accessId: 'AP/101',
          agencyId: 'AGENCY-POLICE',
        );

      for (var hour = 1; hour < 8; hour++) {
        now = DateTime.utc(2026, 10, 6, 8 + hour);
        session.recordActivity();
        expect(session.enforceSecurityExpiry(), isFalse);
      }
      now = DateTime.utc(2026, 10, 6, 16);
      expect(session.enforceSecurityExpiry(), isTrue);
      expect(
        session.lastTerminationReason,
        SessionTerminationReason.absoluteLifetime,
      );
    });

    test('backgrounding immediately locks a security session', () {
      final session = TgcgSessionController()
        ..signIn(
          role: TgcgRole.securityOfficer,
          operatorName: 'Responder',
          accessId: 'AP/102',
          agencyId: 'AGENCY-POLICE',
          securitySessionToken: 'ephemeral-token',
        );

      expect(session.lockForBackground(), isTrue);
      expect(session.isAuthenticated, isFalse);
      expect(session.securitySessionToken, isNull);
      expect(
        session.lastTerminationReason,
        SessionTerminationReason.backgroundLock,
      );
    });

    test('server token expiry terminates the local session', () {
      var now = DateTime.utc(2026, 10, 6, 17);
      final session = TgcgSessionController(clock: () => now)
        ..signIn(
          role: TgcgRole.securityOfficer,
          operatorName: 'Responder',
          accessId: 'AP/103',
          agencyId: 'AGENCY-POLICE',
          securitySessionToken: 'ephemeral-token',
          securitySessionExpiresAt:
              now.add(const Duration(minutes: 10)),
        );

      now = now.add(const Duration(minutes: 10));
      expect(session.enforceSecurityExpiry(), isTrue);
      expect(
        session.lastTerminationReason,
        SessionTerminationReason.remoteSessionExpired,
      );
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
