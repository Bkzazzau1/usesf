import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/assignments/live_deployment_map.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/geography/kaduna_map.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('clicking an LGA opens its details and clicking again clears', (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final geography = GeographyRegistry.prototypeSeed();
    final persistence = OfflinePersistenceController(
      openDatabase: () async => InMemoryOfflineDatabase(),
    );
    final membership = MembershipOperationsController.prototypeSeed(
      geography,
      persistence: persistence,
    );
    final assignments = AssignmentController(
      membership: membership,
      devices: ManagedDeviceController.prototypeSeed(
        membership: membership,
        persistence: persistence,
      ),
      persistence: persistence,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LiveDeploymentMap(
              assignments: const [],
              controller: assignments,
              membership: membership,
              snapshots: const [],
              authorizedUnits: geography.pollingUnits,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Select an LGA'), findsOneWidget);

    final map = find.byType(KadunaMap);
    final topLeft = tester.getTopLeft(map);
    final jemaa = kadunaLgaLabelPosition('KD-JEMAA', tester.getSize(map))!;
    await tester.tapAt(topLeft + jemaa);
    await tester.pump();

    expect(find.text("Jema'a LGA"), findsOneWidget);
    expect(find.text('Kaduna South Senatorial Zone'), findsOneWidget);

    await tester.tapAt(topLeft + jemaa);
    await tester.pump();
    expect(find.text('Select an LGA'), findsOneWidget);
  });
}
