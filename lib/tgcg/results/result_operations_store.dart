import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../domain/permissions.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';
import 'result_integrity.dart';

class ResultOperationsController extends ChangeNotifier {
  ResultOperationsController._({
    required List<ElectionResultSubmission> submissions,
    OfflinePersistenceController? persistence,
  })  : _submissions = submissions,
        _persistence = persistence;

  factory ResultOperationsController.prototypeSeed({
    OfflinePersistenceController? persistence,
  }) {
    final now = DateTime.utc(2026, 9, 27, 6, 45);

    GeographicScope pollingUnit({
      required String zoneId,
      required String zoneName,
      required String stateId,
      required String stateName,
      required String senatorialDistrictId,
      required String senatorialDistrictName,
      required String lgaId,
      required String lgaName,
      required String wardId,
      required String wardName,
      required String pollingUnitId,
      required String pollingUnitName,
    }) => GeographicScope(
          level: GeographyLevel.pollingUnit,
          country: 'Nigeria',
          zoneId: zoneId,
          zoneName: zoneName,
          stateId: stateId,
          stateName: stateName,
          senatorialDistrictId: senatorialDistrictId,
          senatorialDistrictName: senatorialDistrictName,
          lgaId: lgaId,
          lgaName: lgaName,
          wardId: wardId,
          wardName: wardName,
          pollingUnitId: pollingUnitId,
          pollingUnitName: pollingUnitName,
        );

    final puKaduna = pollingUnit(
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/053/KD',
      senatorialDistrictName: 'Kaduna Central',
      lgaId: 'KD-KADUNA-NORTH',
      lgaName: 'Kaduna North',
      wardId: 'KD-KN-W01',
      wardName: 'Ward 01',
      pollingUnitId: 'KD-KN-W01-PU001',
      pollingUnitName: 'PU 001',
    );
    final puZaria = pollingUnit(
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/052/KD',
      senatorialDistrictName: 'Kaduna North',
      lgaId: 'KD-ZARIA',
      lgaName: 'Zaria',
      wardId: 'KD-ZA-W01',
      wardName: 'Ward 01',
      pollingUnitId: 'KD-ZA-W01-PU004',
      pollingUnitName: 'PU 004',
    );
    final puJemaa = pollingUnit(
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/054/KD',
      senatorialDistrictName: 'Kaduna South',
      lgaId: 'KD-JEMAA',
      lgaName: "Jema'a",
      wardId: 'KD-JM-W03',
      wardName: 'Ward 03',
      pollingUnitId: 'KD-JM-W03-PU012',
      pollingUnitName: 'PU 012',
    );

    EvidenceAttachment form(String id, String uploader, DateTime at) =>
        EvidenceAttachment(
          id: id,
          type: EvidenceType.resultForm,
          fileName: '$id.jpg',
          createdAt: at,
          uploaderId: uploader,
          contentHash: 'sha256:prototype-$id',
          mimeType: 'image/jpeg',
          caption: 'Prototype result-form evidence. Replace with captured original.',
          origin: RecordOrigin.systemDerived,
        );

    ElectionResultSubmission validated({
      required String id,
      required GeographicScope scope,
      required String agent,
      required SubmissionSource source,
      required Map<String, int> votes,
      required int total,
      required int accredited,
      required int rejected,
      required RecordStatus status,
      required DateTime at,
      bool duplicate = false,
      Map<String, int>? ocrVotes,
      double? ocrConfidence,
      EvidenceAttachment? evidence,
    }) {
      final base = ElectionResultSubmission(
        id: id,
        pollingUnitScope: scope,
        submittedBy: agent,
        submittedAt: at,
        status: status,
        source: source,
        partyVotes: Map.unmodifiable(votes),
        totalVotesRecorded: total,
        accreditedVoters: accredited,
        rejectedVotes: rejected,
        resultForm: evidence,
        ocrPartyVotes: ocrVotes == null ? null : Map.unmodifiable(ocrVotes),
        origin: RecordOrigin.systemDerived,
      );
      final validation = ResultIntegrityPolicy.validate(
        base,
        duplicateSuspected: duplicate,
        ocrPartyVotes: ocrVotes,
        ocrConfidence: ocrConfidence,
      );
      return _with(base, validation: validation);
    }

    return ResultOperationsController._(
      persistence: persistence,
      submissions: [
        validated(
          id: 'RES-0001',
          scope: puKaduna,
          agent: 'AG-KD-001',
          source: SubmissionSource.app,
          votes: const {'P1': 118, 'P2': 81, 'P3': 37, 'P4': 14},
          total: 250,
          accredited: 263,
          rejected: 13,
          status: RecordStatus.verified,
          at: now.subtract(const Duration(minutes: 18)),
          ocrVotes: const {'P1': 118, 'P2': 81, 'P3': 37, 'P4': 14},
          ocrConfidence: .97,
          evidence: form('FORM-0001', 'AG-KD-001', now.subtract(const Duration(minutes: 18))),
        ),
        validated(
          id: 'RES-0002',
          scope: puZaria,
          agent: 'AG-ZA-014',
          source: SubmissionSource.app,
          votes: const {'P1': 96, 'P2': 104, 'P3': 41, 'P4': 12},
          total: 253,
          accredited: 268,
          rejected: 15,
          status: RecordStatus.underReview,
          at: now.subtract(const Duration(minutes: 34)),
          ocrVotes: const {'P1': 96, 'P2': 101, 'P3': 41, 'P4': 12},
          ocrConfidence: .82,
          evidence: form('FORM-0002', 'AG-ZA-014', now.subtract(const Duration(minutes: 34))),
        ),
        validated(
          id: 'RES-0003',
          scope: puJemaa,
          agent: 'AG-JM-032',
          source: SubmissionSource.sms,
          votes: const {'P1': 140, 'P2': 74, 'P3': 52, 'P4': 19},
          total: 285,
          accredited: 297,
          rejected: 12,
          status: RecordStatus.submitted,
          at: now.subtract(const Duration(minutes: 49)),
        ),
        validated(
          id: 'RES-0004',
          scope: puKaduna,
          agent: 'AG-KD-009',
          source: SubmissionSource.ussd,
          votes: const {'P1': 118, 'P2': 81, 'P3': 37, 'P4': 14},
          total: 250,
          accredited: 263,
          rejected: 13,
          status: RecordStatus.underReview,
          at: now.subtract(const Duration(minutes: 12)),
          duplicate: true,
        ),
      ],
    );
  }

  final List<ElectionResultSubmission> _submissions;
  final OfflinePersistenceController? _persistence;

  List<ElectionResultSubmission> get submissions => List.unmodifiable(_submissions);

  Future<void> hydrateFromOffline() async {
    final persistence = _persistence;
    if (persistence == null) return;

    final rows = await persistence.readEntities(
      entityType: 'election_result',
    );
    var changed = false;

    for (final row in rows) {
      final id = row['id']?.toString();
      final scope = geographicScopeFromJson(row['pollingUnitScope']);
      final submittedBy = row['submittedBy']?.toString();
      final submittedAt =
          DateTime.tryParse(row['submittedAt']?.toString() ?? '')?.toUtc();
      final status = _recordStatus(row['status']);
      final source = _submissionSource(row['source']);
      final total = _int(row['totalVotesRecorded']);
      final accredited = _int(row['accreditedVoters']);
      if (id == null ||
          scope == null ||
          submittedBy == null ||
          submittedAt == null ||
          status == null ||
          source == null ||
          total == null ||
          accredited == null) {
        continue;
      }

      final votes = <String, int>{};
      final rawVotes = row['partyVotes'];
      if (rawVotes is Map) {
        for (final entry in rawVotes.entries) {
          final value = _int(entry.value);
          if (value != null) votes[entry.key.toString()] = value;
        }
      }

      Map<String, int>? ocrPartyVotes;
      final rawOcrVotes = row['ocrPartyVotes'];
      if (rawOcrVotes is Map) {
        final values = <String, int>{};
        for (final entry in rawOcrVotes.entries) {
          final value = _int(entry.value);
          if (value != null) values[entry.key.toString()] = value;
        }
        ocrPartyVotes = Map.unmodifiable(values);
      }

      ResultValidationSummary? validation;
      final rawValidation = row['validation'];
      if (rawValidation is Map) {
        final map = rawValidation.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        validation = ResultValidationSummary(
          arithmeticValid: map['arithmeticValid'] == true,
          duplicateSuspected: map['duplicateSuspected'] == true,
          pollingUnitMatched: map['pollingUnitMatched'] != false,
          agentScopeMatched: map['agentScopeMatched'] != false,
          formEvidencePresent: map['formEvidencePresent'] != false,
          ocrProcessed: map['ocrProcessed'] != false,
          ocrConfidence: _double(map['ocrConfidence']),
          ocrMatchedManualEntry: map['ocrMatchedManualEntry'] is bool
              ? map['ocrMatchedManualEntry'] as bool
              : null,
          notes: map['notes'] is List
              ? (map['notes'] as List)
                  .map((item) => item.toString())
                  .toList(growable: false)
              : const [],
        );
      }

      final restored = ElectionResultSubmission(
        id: id,
        pollingUnitScope: scope,
        submittedBy: submittedBy,
        submittedAt: submittedAt,
        status: status,
        source: source,
        partyVotes: Map.unmodifiable(votes),
        totalVotesRecorded: total,
        accreditedVoters: accredited,
        rejectedVotes: _int(row['rejectedVotes']),
        registeredVoters: _int(row['registeredVoters']),
        resultForm: evidenceFromJson(row['resultForm']),
        ocrPartyVotes: ocrPartyVotes,
        validation: validation,
        verifiedBy: row['verifiedBy']?.toString(),
        verifiedAt:
            DateTime.tryParse(row['verifiedAt']?.toString() ?? '')?.toUtc(),
        disputeReason: row['disputeReason']?.toString(),
        sourceReference: row['sourceReference']?.toString(),
        origin: _recordOrigin(row['origin']) ?? RecordOrigin.localEntry,
      );

      final index = _submissions.indexWhere((item) => item.id == id);
      if (index < 0) {
        _submissions.add(restored);
      } else {
        _submissions[index] = restored;
      }
      changed = true;
    }

    if (changed) {
      _submissions.sort(
        (a, b) => b.submittedAt.compareTo(a.submittedAt),
      );
      notifyListeners();
    }
  }

  List<ElectionResultSubmission> submissionsForScope(GeographicScope scope) =>
      _submissions.where((item) => _within(scope, item.pollingUnitScope)).toList(growable: false);

  List<ElectionResultSubmission> reviewQueueForScope(GeographicScope scope) =>
      submissionsForScope(scope).where(_needsReview).toList(growable: false);

  int get pendingReviewCount => _submissions.where(_needsReview).length;

  int get verifiedCount =>
      _submissions.where((item) => item.status == RecordStatus.verified).length;

  Future<ElectionResultSubmission> submit({
    required GeographicScope pollingUnitScope,
    required String submittedBy,
    required SubmissionSource source,
    required Map<String, int> partyVotes,
    required int totalVotesRecorded,
    required int accreditedVoters,
    int? rejectedVotes,
    int? registeredVoters,
    EvidenceAttachment? resultForm,
    Map<String, int>? ocrPartyVotes,
    double? ocrConfidence,
  }) async {
    final duplicate = _submissions.any((existing) =>
        existing.pollingUnitScope.pollingUnitId == pollingUnitScope.pollingUnitId &&
        existing.status != RecordStatus.rejected &&
        existing.status != RecordStatus.archived);

    final base = ElectionResultSubmission(
      id: 'RES-${(_submissions.length + 1).toString().padLeft(4, '0')}',
      pollingUnitScope: pollingUnitScope,
      submittedBy: submittedBy,
      submittedAt: DateTime.now().toUtc(),
      status: RecordStatus.submitted,
      source: source,
      partyVotes: Map.unmodifiable(partyVotes),
      totalVotesRecorded: totalVotesRecorded,
      accreditedVoters: accreditedVoters,
      rejectedVotes: rejectedVotes,
      registeredVoters: registeredVoters,
      resultForm: resultForm,
      ocrPartyVotes:
          ocrPartyVotes == null ? null : Map.unmodifiable(ocrPartyVotes),
      origin: RecordOrigin.localEntry,
    );

    final validation = ResultIntegrityPolicy.validate(
      base,
      duplicateSuspected: duplicate,
      ocrPartyVotes: ocrPartyVotes,
      ocrConfidence: ocrConfidence,
    );
    final status = validation.requiresHumanReview
        ? RecordStatus.underReview
        : RecordStatus.submitted;
    final saved = _with(base, validation: validation, status: status);
    await _persistence?.persistMutation(
      entityType: 'election_result',
      entityId: saved.id,
      mutationType: SyncMutationType.create,
      payload: resultSubmissionToJson(saved),
      scopeKey: scopeStorageKey(saved.pollingUnitScope),
      ownerId: submittedBy,
    );
    _submissions.insert(0, saved);
    notifyListeners();
    return saved;
  }

  Future<bool> verify({
    required String submissionId,
    required String verifierId,
    required TgcgRole role,
    required GeographicScope userScope,
  }) async {
    final index = _submissions.indexWhere((item) => item.id == submissionId);
    if (index < 0) return false;
    final current = _submissions[index];
    if (!TgcgPermissionPolicy.may(
      role,
      userScope,
      TgcgCapability.verifyElectionResult,
      targetScope: current.pollingUnitScope,
    )) {
      return false;
    }

    final updated = _with(
      current,
      status: RecordStatus.verified,
      verifiedBy: verifierId,
      verifiedAt: DateTime.now().toUtc(),
      disputeReason: null,
    );
    await _persistence?.persistMutation(
      entityType: 'election_result',
      entityId: updated.id,
      mutationType: SyncMutationType.update,
      payload: resultSubmissionToJson(updated),
      scopeKey: scopeStorageKey(updated.pollingUnitScope),
      ownerId: verifierId,
    );
    _submissions[index] = updated;
    notifyListeners();
    return true;
  }

  Future<bool> dispute({
    required String submissionId,
    required String reviewerId,
    required String reason,
    required TgcgRole role,
    required GeographicScope userScope,
  }) async {
    final index = _submissions.indexWhere((item) => item.id == submissionId);
    if (index < 0) return false;
    final current = _submissions[index];
    if (!TgcgPermissionPolicy.may(
      role,
      userScope,
      TgcgCapability.disputeElectionResult,
      targetScope: current.pollingUnitScope,
    )) {
      return false;
    }

    final updated = _with(
      current,
      status: RecordStatus.disputed,
      disputeReason: reason.trim().isEmpty ? 'Flagged for review.' : reason.trim(),
      verifiedBy: reviewerId,
      verifiedAt: DateTime.now().toUtc(),
    );
    await _persistence?.persistMutation(
      entityType: 'election_result',
      entityId: updated.id,
      mutationType: SyncMutationType.update,
      payload: resultSubmissionToJson(updated),
      scopeKey: scopeStorageKey(updated.pollingUnitScope),
      ownerId: reviewerId,
    );
    _submissions[index] = updated;
    notifyListeners();
    return true;
  }

  static int? _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static RecordStatus? _recordStatus(Object? value) {
    final name = value?.toString();
    for (final item in RecordStatus.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static SubmissionSource? _submissionSource(Object? value) {
    final name = value?.toString();
    for (final item in SubmissionSource.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static RecordOrigin? _recordOrigin(Object? value) {
    final name = value?.toString();
    for (final item in RecordOrigin.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static bool _needsReview(ElectionResultSubmission item) {
    if (item.status == RecordStatus.verified ||
        item.status == RecordStatus.rejected ||
        item.status == RecordStatus.archived) {
      return false;
    }
    return item.status == RecordStatus.underReview ||
        item.status == RecordStatus.disputed ||
        item.validation?.requiresHumanReview == true;
  }

  static ElectionResultSubmission _with(
    ElectionResultSubmission current, {
    RecordStatus? status,
    ResultValidationSummary? validation,
    String? verifiedBy,
    DateTime? verifiedAt,
    String? disputeReason,
  }) =>
      ElectionResultSubmission(
        id: current.id,
        pollingUnitScope: current.pollingUnitScope,
        submittedBy: current.submittedBy,
        submittedAt: current.submittedAt,
        status: status ?? current.status,
        source: current.source,
        partyVotes: current.partyVotes,
        totalVotesRecorded: current.totalVotesRecorded,
        accreditedVoters: current.accreditedVoters,
        rejectedVotes: current.rejectedVotes,
        registeredVoters: current.registeredVoters,
        resultForm: current.resultForm,
        ocrPartyVotes: current.ocrPartyVotes,
        validation: validation ?? current.validation,
        verifiedBy: verifiedBy ?? current.verifiedBy,
        verifiedAt: verifiedAt ?? current.verifiedAt,
        disputeReason: disputeReason,
        sourceReference: current.sourceReference,
        origin: current.origin,
      );

  static bool _within(GeographicScope parent, GeographicScope child) {
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

class ResultOperations extends InheritedNotifier<ResultOperationsController> {
  const ResultOperations({
    super.key,
    required ResultOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static ResultOperationsController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<ResultOperations>();
      assert(value != null, 'ResultOperations is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<ResultOperations>();
    final value = element?.widget as ResultOperations?;
    assert(value != null, 'ResultOperations is missing above this context.');
    return value!.notifier!;
  }
}
