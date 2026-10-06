import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/app.dart';
import 'package:usesf/tgcg/field/field_operations_store.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/security/emergency_response_store.dart';
import 'package:usesf/tgcg/security/security_portal_login_page.dart';
import 'package:usesf/tgcg/session.dart';

Widget _harness(
  TgcgSessionController session,
  Widget home, {
  GovernanceOperationsController? governance,
  EmergencyResponseController? emergency,
}) {
  final resolvedGovernance =
      governance ?? GovernanceOperationsController.prototypeSeed();
  final resolvedEmergency =
      emergency ?? EmergencyResponseController.prototypeSeed(resolvedGovernance);
  return TgcgSession(
    controller: session,
    child: GovernanceOperations(
      controller: resolvedGovernance,
      child: EmergencyResponse(
        controller: resolvedEmergency,
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
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final size in const [Size(1440, 900), Size(400, 860)]) {
    testWidgets(
      'portal sign-in renders and validates at ${size.width.toInt()}px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final session = TgcgSessionController();
        await tester.pumpWidget(
          _harness(session, const SecurityPortalLoginPage()),
        );

        expect(find.text('Security Agency Sign-in'), findsOneWidget);
        expect(find.text('Police'), findsOneWidget);
        expect(find.text('Demo access'), findsNothing);

        await tester.ensureVisible(find.text('Enter Security Portal'));
        await tester.pump();
        await tester.tap(find.text('Enter Security Portal'));
        await tester.pump();
        expect(session.isAuthenticated, isFalse);
        expect(find.text('Select your agency to continue.'), findsOneWidget);
      },
    );
  }

  testWidgets('configured agency officer can sign in manually', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({});

    final governance = GovernanceOperationsController.prototypeSeed();
    final emergency = EmergencyResponseController.prototypeSeed(governance);
    await emergency.provisionResponder(
      agencyId: 'AGENCY-POLICE',
      serviceNumber: 'AP/12345',
      displayName: 'Insp. Musa Bello',
      accessCode: 'secure-access',
      responderScope: GeographicScope.kaduna,
      actorId: 'SYSTEM-ADMIN',
      actorRole: TgcgRole.stateAdministrator,
      authorizedScope: GeographicScope.kaduna,
    );

    final session = TgcgSessionController();
    await tester.pumpWidget(
      _harness(
        session,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SecurityPortalLoginPage(),
                ),
              ),
              child: const Text('open portal'),
            ),
          ),
        ),
        governance: governance,
        emergency: emergency,
      ),
    );
    await tester.tap(find.text('open portal'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Police'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Service / force number'),
      'AP/12345',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Portal access code'),
      'secure-access',
    );
    await tester.ensureVisible(find.text('Enter Security Portal'));
    await tester.tap(find.text('Enter Security Portal'));
    await tester.pumpAndSettle();

    expect(session.isAuthenticated, isTrue);
    expect(session.role, TgcgRole.securityOfficer);
    expect(session.operatorName, 'Insp. Musa Bello');
    expect(session.agencyId, 'AGENCY-POLICE');
    expect(session.accessId, 'AP/12345');
    expect(session.scope.level, GeographyLevel.state);
  });

  testWidgets('wrong responder access code is rejected', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({});

    final governance = GovernanceOperationsController.prototypeSeed();
    final emergency = EmergencyResponseController.prototypeSeed(governance);
    await emergency.provisionResponder(
      agencyId: 'AGENCY-POLICE',
      serviceNumber: 'AP/12345',
      displayName: 'Insp. Musa Bello',
      accessCode: 'secure-access',
      responderScope: GeographicScope.kaduna,
      actorId: 'SYSTEM-ADMIN',
      actorRole: TgcgRole.stateAdministrator,
      authorizedScope: GeographicScope.kaduna,
    );

    final session = TgcgSessionController();
    await tester.pumpWidget(
      _harness(
        session,
        const SecurityPortalLoginPage(),
        governance: governance,
        emergency: emergency,
      ),
    );

    await tester.tap(find.text('Police'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Service / force number'),
      'AP/12345',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Portal access code'),
      'wrong-access',
    );
    await tester.ensureVisible(find.text('Enter Security Portal'));
    await tester.tap(find.text('Enter Security Portal'));
    await tester.pumpAndSettle();

    expect(session.isAuthenticated, isFalse);
    expect(
      find.text('Invalid responder credential or unauthorized command area.'),
      findsOneWidget,
    );
  });

  testWidgets('production Security Portal has no synthetic agency access',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TgcgApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Security Portal'));
    await tester.pumpAndSettle();

    expect(find.text('Security Agency Sign-in'), findsOneWidget);
    expect(find.text('Demo access'), findsNothing);
    expect(find.text('Police • Kaduna State Command'), findsNothing);
  });
}
