import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

class DirectEvidenceRecord {
  const DirectEvidenceRecord({
    required this.evidence,
    required this.scope,
    required this.reference,
  });

  final EvidenceAttachment evidence;
  final GeographicScope scope;
  final String? reference;
}

class EvidenceOperationsController extends ChangeNotifier {
  EvidenceOperationsController({
    required OfflinePersistenceController persistence,
    List<DirectEvidenceRecord> records = const [],
  })  : _persistence = persistence,
        _records = List<DirectEvidenceRecord>.of(records);

  final OfflinePersistenceController _persistence;
  final List<DirectEvidenceRecord> _records;

  List<DirectEvidenceRecord> get records => List.unmodifiable(_records);

  List<DirectEvidenceRecord> recordsForScope(GeographicScope scope) =>
      _records
          .where(
            (item) =>
                _scopeAllows(scope, item.scope),
          )
          .toList(growable: false)
        ..sort(
          (a, b) => b.evidence.createdAt.compareTo(a.evidence.createdAt),
        );

  Future<void> hydrateFromOffline() async {
    final rows = await _persistence.readEntities(entityType: 'evidence');
    var changed = false;
    for (final row in rows) {
      final id = row['id']?.toString();
      final type = _evidenceType(row['type']);
      final fileName = row['fileName']?.toString();
      final uploaderId = row['uploaderId']?.toString();
      final createdAt =
          DateTime.tryParse(row['createdAt']?.toString() ?? '')?.toUtc();
      if (id == null ||
          type == null ||
          fileName == null ||
          uploaderId == null ||
          createdAt == null) {
        continue;
      }

      final scope =
          geographicScopeFromJson(row['scope']) ?? GeographicScope.kaduna;
      final attachment = EvidenceAttachment(
        id: id,
        type: type,
        fileName: fileName,
        createdAt: createdAt,
        uploaderId: uploaderId,
        contentHash: _clean(row['contentHash']?.toString()),
        mimeType: _clean(row['mimeType']?.toString()),
        caption: _clean(row['caption']?.toString()),
        sourceReference: _clean(row['sourceReference']?.toString()),
        latitude: _double(row['latitude']),
        longitude: _double(row['longitude']),
        origin: RecordOrigin.localEntry,
      );
      final restored = DirectEvidenceRecord(
        evidence: attachment,
        scope: scope,
        reference: _clean(row['reference']?.toString()),
      );
      final index =
          _records.indexWhere((item) => item.evidence.id == attachment.id);
      if (index < 0) {
        _records.add(restored);
      } else {
        _records[index] = restored;
      }
      changed = true;
    }

    if (changed) {
      _records.sort(
        (a, b) => b.evidence.createdAt.compareTo(a.evidence.createdAt),
      );
      notifyListeners();
    }
  }

  Future<DirectEvidenceRecord> addCapture({
    required EvidenceAttachment evidence,
    required GeographicScope scope,
    String? reference,
  }) async {
    final record = DirectEvidenceRecord(
      evidence: evidence,
      scope: scope,
      reference: _clean(reference),
    );
    await _persistence.persistMutation(
      entityType: 'evidence',
      entityId: evidence.id,
      mutationType: SyncMutationType.create,
      ownerId: evidence.uploaderId,
      scopeKey: scopeStorageKey(scope),
      payload: {
        'id': evidence.id,
        'type': evidence.type.name,
        'fileName': evidence.fileName,
        'mimeType': evidence.mimeType,
        'contentHash': evidence.contentHash,
        'caption': evidence.caption,
        'sourceReference': evidence.sourceReference,
        'latitude': evidence.latitude,
        'longitude': evidence.longitude,
        'reference': record.reference,
        'uploaderId': evidence.uploaderId,
        'createdAt': evidence.createdAt.toUtc().toIso8601String(),
        'scope': geographicScopeToJson(scope),
        'scopeLabel': scope.label,
        'origin': evidence.origin.name,
      },
    );
    _records.insert(0, record);
    notifyListeners();
    return record;
  }

  static EvidenceType? _evidenceType(Object? value) {
    final name = value?.toString();
    for (final item in EvidenceType.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static bool _scopeAllows(
    GeographicScope parent,
    GeographicScope child,
  ) {
    if (parent.country != child.country) return false;
    if (parent.level == GeographyLevel.country) return true;
    if (parent.zoneId != null && parent.zoneId != child.zoneId) return false;
    if (parent.level == GeographyLevel.geopoliticalZone) return true;
    if (parent.stateId != null && parent.stateId != child.stateId) return false;
    if (parent.level == GeographyLevel.state) return true;
    if (parent.senatorialDistrictId != null &&
        parent.senatorialDistrictId != child.senatorialDistrictId) {
      return false;
    }
    if (parent.level == GeographyLevel.senatorialDistrict) return true;
    if (parent.lgaId != null && parent.lgaId != child.lgaId) return false;
    if (parent.level == GeographyLevel.lga) return true;
    if (parent.wardId != null && parent.wardId != child.wardId) return false;
    if (parent.level == GeographyLevel.ward) return true;
    return parent.pollingUnitId == child.pollingUnitId;
  }
}

class EvidenceOperations
    extends InheritedNotifier<EvidenceOperationsController> {
  const EvidenceOperations({
    super.key,
    required EvidenceOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static EvidenceOperationsController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<EvidenceOperations>();
      assert(value != null, 'EvidenceOperations is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<EvidenceOperations>();
    final value = element?.widget as EvidenceOperations?;
    assert(value != null, 'EvidenceOperations is missing above this context.');
    return value!.notifier!;
  }
}
