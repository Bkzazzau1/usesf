import '../domain/models.dart';

String scopeStorageKey(GeographicScope scope) => [
      scope.country,
      scope.zoneId,
      scope.stateId,
      scope.senatorialDistrictId,
      scope.lgaId,
      scope.wardId,
      scope.pollingUnitId,
    ].whereType<String>().join('/');

Map<String, Object?> geographicScopeToJson(GeographicScope scope) => {
      'level': scope.level.name,
      'country': scope.country,
      'zoneId': scope.zoneId,
      'zoneName': scope.zoneName,
      'stateId': scope.stateId,
      'stateName': scope.stateName,
      'senatorialDistrictId': scope.senatorialDistrictId,
      'senatorialDistrictName': scope.senatorialDistrictName,
      'lgaId': scope.lgaId,
      'lgaName': scope.lgaName,
      'wardId': scope.wardId,
      'wardName': scope.wardName,
      'pollingUnitId': scope.pollingUnitId,
      'pollingUnitName': scope.pollingUnitName,
    };

GeographicScope? geographicScopeFromJson(Object? value) {
  if (value is! Map) return null;
  final map = value.map(
    (key, item) => MapEntry(key.toString(), item),
  );
  final levelName = map['level']?.toString();
  final country = map['country']?.toString();
  if (levelName == null || country == null) return null;
  final level = GeographyLevel.values
      .where((item) => item.name == levelName)
      .firstOrNull;
  if (level == null) return null;

  return GeographicScope(
    level: level,
    country: country,
    zoneId: map['zoneId']?.toString(),
    zoneName: map['zoneName']?.toString(),
    stateId: map['stateId']?.toString(),
    stateName: map['stateName']?.toString(),
    senatorialDistrictId: map['senatorialDistrictId']?.toString(),
    senatorialDistrictName: map['senatorialDistrictName']?.toString(),
    lgaId: map['lgaId']?.toString(),
    lgaName: map['lgaName']?.toString(),
    wardId: map['wardId']?.toString(),
    wardName: map['wardName']?.toString(),
    pollingUnitId: map['pollingUnitId']?.toString(),
    pollingUnitName: map['pollingUnitName']?.toString(),
  );
}

EvidenceAttachment? evidenceFromJson(Object? value) {
  if (value is! Map) return null;
  final map = value.map(
    (key, item) => MapEntry(key.toString(), item),
  );
  final id = map['id']?.toString();
  final typeName = map['type']?.toString();
  final fileName = map['fileName']?.toString();
  final createdAt = DateTime.tryParse(map['createdAt']?.toString() ?? '');
  final uploaderId = map['uploaderId']?.toString();
  if (id == null ||
      typeName == null ||
      fileName == null ||
      createdAt == null ||
      uploaderId == null) {
    return null;
  }
  final type =
      EvidenceType.values.where((item) => item.name == typeName).firstOrNull;
  if (type == null) return null;
  final originName = map['origin']?.toString();
  final origin = RecordOrigin.values
          .where((item) => item.name == originName)
          .firstOrNull ??
      RecordOrigin.localEntry;

  return EvidenceAttachment(
    id: id,
    type: type,
    fileName: fileName,
    createdAt: createdAt.toUtc(),
    uploaderId: uploaderId,
    contentHash: map['contentHash']?.toString(),
    mimeType: map['mimeType']?.toString(),
    caption: map['caption']?.toString(),
    sourceReference: map['sourceReference']?.toString(),
    latitude: _jsonDouble(map['latitude']),
    longitude: _jsonDouble(map['longitude']),
    origin: origin,
  );
}

double? _jsonDouble(Object? value) {
  if (value is num) return value.toDouble();
  return value == null ? null : double.tryParse(value.toString());
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

Map<String, Object?> evidenceToJson(EvidenceAttachment evidence) => {
      'id': evidence.id,
      'type': evidence.type.name,
      'fileName': evidence.fileName,
      'createdAt': evidence.createdAt.toUtc().toIso8601String(),
      'uploaderId': evidence.uploaderId,
      'contentHash': evidence.contentHash,
      'mimeType': evidence.mimeType,
      'caption': evidence.caption,
      'sourceReference': evidence.sourceReference,
      'latitude': evidence.latitude,
      'longitude': evidence.longitude,
      'origin': evidence.origin.name,
    };

Map<String, Object?> fieldIncidentToJson(FieldIncident incident) => {
      'id': incident.id,
      'title': incident.title,
      'category': incident.category,
      'severity': incident.severity.name,
      'status': incident.status.name,
      'scope': geographicScopeToJson(incident.scope),
      'reportedAt': incident.reportedAt.toUtc().toIso8601String(),
      'reporterId': incident.reporterId,
      'summary': incident.summary,
      'assignedTeam': incident.assignedTeam,
      'assignmentId': incident.assignmentId,
      'deviceId': incident.deviceId,
      'latitude': incident.latitude,
      'longitude': incident.longitude,
      'evidence': incident.evidence.map(evidenceToJson).toList(growable: false),
      'origin': incident.origin.name,
    };

Map<String, Object?> fieldReportToJson(FieldReport report) => {
      'id': report.id,
      'category': report.category,
      'summary': report.summary,
      'scope': geographicScopeToJson(report.scope),
      'reporterId': report.reporterId,
      'reportedAt': report.reportedAt.toUtc().toIso8601String(),
      'status': report.status.name,
      'incidentId': report.incidentId,
      'evidence': report.evidence.map(evidenceToJson).toList(growable: false),
      'origin': report.origin.name,
    };

Map<String, Object?> resultSubmissionToJson(
  ElectionResultSubmission submission,
) => {
      'id': submission.id,
      'pollingUnitScope': geographicScopeToJson(submission.pollingUnitScope),
      'submittedBy': submission.submittedBy,
      'submittedAt': submission.submittedAt.toUtc().toIso8601String(),
      'status': submission.status.name,
      'source': submission.source.name,
      'partyVotes': submission.partyVotes,
      'totalVotesRecorded': submission.totalVotesRecorded,
      'accreditedVoters': submission.accreditedVoters,
      'rejectedVotes': submission.rejectedVotes,
      'registeredVoters': submission.registeredVoters,
      'resultForm': submission.resultForm == null
          ? null
          : evidenceToJson(submission.resultForm!),
      'ocrPartyVotes': submission.ocrPartyVotes,
      'validation': submission.validation == null
          ? null
          : {
              'arithmeticValid': submission.validation!.arithmeticValid,
              'duplicateSuspected': submission.validation!.duplicateSuspected,
              'pollingUnitMatched': submission.validation!.pollingUnitMatched,
              'agentScopeMatched': submission.validation!.agentScopeMatched,
              'formEvidencePresent':
                  submission.validation!.formEvidencePresent,
              'ocrProcessed': submission.validation!.ocrProcessed,
              'ocrConfidence': submission.validation!.ocrConfidence,
              'ocrMatchedManualEntry':
                  submission.validation!.ocrMatchedManualEntry,
              'notes': submission.validation!.notes,
              'requiresHumanReview':
                  submission.validation!.requiresHumanReview,
            },
      'verifiedBy': submission.verifiedBy,
      'verifiedAt': submission.verifiedAt?.toUtc().toIso8601String(),
      'disputeReason': submission.disputeReason,
      'sourceReference': submission.sourceReference,
      'origin': submission.origin.name,
      'isOfficial': false,
    };
