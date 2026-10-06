import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/sync/sync_models.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('offline persistence can recover after an initial startup failure',
      () async {
    var attempts = 0;
    final database = InMemoryOfflineDatabase();
    final persistence = OfflinePersistenceController(
      openDatabase: () async {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('simulated database open failure');
        }
        return database;
      },
    );

    await persistence.initialize();

    expect(persistence.state, OfflinePersistenceState.failed);
    expect(persistence.isReady, isFalse);
    expect(attempts, 1);

    await persistence.initialize();

    expect(persistence.state, OfflinePersistenceState.ready);
    expect(persistence.isReady, isTrue);
    expect(attempts, 2);

    await persistence.persistMutation(
      entityType: 'startup_readiness_test',
      entityId: 'REAL-001',
      mutationType: SyncMutationType.create,
      payload: const {'id': 'REAL-001', 'ready': true},
    );

    final restored = await persistence.readEntity(
      entityType: 'startup_readiness_test',
      entityId: 'REAL-001',
    );
    expect(restored?['ready'], isTrue);
  });
}
