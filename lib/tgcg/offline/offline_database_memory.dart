import '../sync/sync_models.dart';
import 'offline_database_contract.dart';

/// Non-durable offline store kept in memory. Used where no on-device
/// database is available (web) and by tests.
class InMemoryOfflineDatabase implements OfflineDatabaseBackend {
  final Map<String, StoredEntityRecord> _entities = {};
  final Map<String, StoredOutboxMutation> _outbox = {};
  final Map<String, SyncReceipt> _receipts = {};

  @override
  bool get isDurable => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<int> currentEntityVersion({
    required String entityType,
    required String entityId,
  }) async =>
      _entities['$entityType::$entityId']?.version ?? 0;

  @override
  Future<StoredEntityRecord?> readEntity({
    required String entityType,
    required String entityId,
  }) async =>
      _entities['$entityType::$entityId'];

  @override
  Future<List<StoredEntityRecord>> listEntities({
    required String entityType,
  }) async =>
      _entities.values
          .where((item) => item.entityType == entityType)
          .toList(growable: false)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> writeMutation({
    required StoredEntityRecord entity,
    required SyncOutboxItem outbox,
    required EncryptedPayload outboxPayload,
  }) async {
    _entities['${entity.entityType}::${entity.entityId}'] = entity;
    _outbox[outbox.id] = StoredOutboxMutation(
      item: outbox,
      payload: outboxPayload,
    );
  }

  @override
  Future<List<StoredOutboxMutation>> loadOutbox() async {
    final values = _outbox.values.toList(growable: false)
      ..sort((a, b) => b.item.createdAt.compareTo(a.item.createdAt));
    return values;
  }

  @override
  Future<void> updateOutbox(SyncOutboxItem item) async {
    final current = _outbox[item.id];
    if (current == null) return;
    _outbox[item.id] = StoredOutboxMutation(
      item: item,
      payload: current.payload,
    );
  }

  @override
  Future<void> saveReceipt(SyncReceipt receipt) async {
    _receipts[receipt.outboxId] = receipt;
  }

  @override
  Future<SyncReceipt?> receiptFor(String outboxId) async =>
      _receipts[outboxId];

  @override
  Future<void> clearAll() async {
    _entities.clear();
    _outbox.clear();
    _receipts.clear();
  }

  @override
  Future<void> close() async {
    await clearAll();
  }
}
