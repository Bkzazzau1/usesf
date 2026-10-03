import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/field/field_operations_store.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/security/emergency_response_store.dart';
import 'package:usesf/tgcg/security/security_agency_shell.dart';
import 'package:usesf/tgcg/security/security_portal_login_page.dart';
import 'package:usesf/tgcg/session.dart';

Widget _harness(TgcgSessionController session, Widget home) {
  final governance = GovernanceOperationsController.prototypeSeed();
  return TgcgSession(
    controller: session,
    child: GovernanceOperations(
      controller: governance,
      child: EmergencyResponse(
        controller: EmergencyResponseController.prototypeSeed(governance),
        child: MembershipOperations(
          controller: MembershipOperationsController.prototypeSeed(
            GeographyRegistry.prototypeSeed(),
          ),
          child: FieldOperations(
            controller: FieldOperationsController.prototypeSeed(),
            child: MaterialApp(home: home),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final size in const [Size(1440, 900), Size(400, 860)]) {
    testWidgets('portal sign-in renders and validates at ${size.width.toInt()}px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final session = TgcgSessionController();
      await tester.pumpWidget(_harness(session, const SecurityPortalLoginPage()));

      expect(find.text('Security Agency Sign-in'), findsOneWidget);
      expect(find.text('Police'), findsOneWidget);

      // Without an agency, sign-in is refused.
      await tester.ensureVisible(find.text('Enter Security Portal'));
      await tester.pump();
      await tester.tap(find.text('Enter Security Portal'));
      await tester.pump();
      expect(session.isAuthenticated, isFalse);
      expect(find.text('Select your agency to continue.'), findsOneWidget);
    });

    testWidgets('officer workspace renders dispatches at ${size.width.toInt()}px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final session = TgcgSessionController()
        ..signIn(
          role: TgcgRole.securityOfficer,
          operatorName: 'Insp. Musa Bello',
          accessId: 'AP/12345',
          agencyId: 'AGENCY-POLICE',
        );
      await tester.pumpWidget(_harness(session, const SecurityAgencyShell()));

      expect(find.text('SECURITY PORTAL'), findsOneWidget);
      expect(find.textContaining('Crowd disturbance'), findsOneWidget);

      await tester.ensureVisible(find.text('Acknowledge dispatch'));
      await tester.pump();
      await tester.tap(find.text('Acknowledge dispatch'));
      await tester.pump();
      expect(find.text('Acknowledge dispatch'), findsNothing);
    });
  }
}
