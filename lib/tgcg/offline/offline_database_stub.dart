import 'offline_database_contract.dart';
import 'offline_database_memory.dart';

Future<OfflineDatabaseBackend> openOfflineDatabaseBackend() async =>
    InMemoryOfflineDatabase();
