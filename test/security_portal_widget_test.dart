import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/app.dart';
import 'package:usesf/tgcg/field/field_operations_store.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/security/emergency_response_store.dart';
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
  }

  testWidgets('demo officer profile signs in to the Security Portal', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = TgcgSessionController();
    await tester.pumpWidget(
      _harness(
        session,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SecurityPortalLoginPage()),
              ),
              child: const Text('open portal'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open portal'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Police • Kaduna State Command'));
    await tester.pump();
    await tester.tap(find.text('Police • Kaduna State Command'));
    await tester.pump();
    await tester.ensureVisible(find.text('Enter Security Portal'));
    await tester.pump();
    await tester.tap(find.text('Enter Security Portal'));
    await tester.pumpAndSettle();

    expect(session.isAuthenticated, isTrue);
    expect(session.role, TgcgRole.securityOfficer);
    expect(session.agencyId, 'AGENCY-POLICE');
    expect(session.accessId, 'AP/12345');
    expect(session.scope.level, GeographyLevel.state);
  });

  testWidgets('Security Portal demo sign-in opens the agency response workspace', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TgcgApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Security Portal'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Police • Kaduna State Command'));
    await tester.pump();
    await tester.tap(find.text('Police • Kaduna State Command'));
    await tester.pump();
    await tester.ensureVisible(find.text('Enter Security Portal'));
    await tester.pump();
    await tester.tap(find.text('Enter Security Portal'));
    await tester.pumpAndSettle();

    expect(find.text('AUTHORIZED AGENCY RESPONSE'), findsOneWidget);
    expect(find.text('AGENCY-ONLY ACCESS'), findsOneWidget);
  });
}
