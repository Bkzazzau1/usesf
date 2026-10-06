import 'package:flutter/widgets.dart';

import '../domain/local_id.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

class IncidentStatusTransitionEvent {
  const IncidentStatusTransitionEvent({
    required this.id,
    required this.incidentId,
    required this.fromStatus,
    required this.toStatus,
    required this.actorId,
    required this.actorRole,
    required this.changedAt,
    required this.scope,
  });

  final String id;
  final String incidentId;
  final IncidentStatus fromStatus;
  final IncidentStatus toStatus;
  final String actorId;
  final TgcgRole actorRole;
  final DateTime changedAt;
  final GeographicScope scope;
}

TgcgCapability incidentStatusMutationCapability(IncidentStatus status) =>
    switch (status) {
      IncidentStatus.acknowledged => TgcgCapability.acknowledgeIncident,
      IncidentStatus.assigned ||
      IncidentStatus.investigating ||
      IncidentStatus.escalated =>
        TgcgCapability.assignIncident,
      IncidentStatus.resolved || IncidentStatus.closed =>
        TgcgCapability.closeIncident,
      IncidentStatus.reported => TgcgCapability.createIncident,
    };

class FieldOperationsController extends ChangeNotifier {
  FieldOperationsController._({
    required List<FieldIncident> incidents,
    required List<FieldReport> reports,
    OfflinePersistenceController? persistence,
  })  : _incidents = incidents,
        _reports = reports,
        _persistence = persistence;

  factory FieldOperationsController.prototypeSeed({
    OfflinePersistenceController? persistence,
  }) {
    final now = DateTime.utc(2026, 9, 27, 6, 30);

    GeographicScope lga({
      required String zoneId,
      required String zoneName,
      required String stateId,
      required String stateName,
      required String senatorialDistrictId,
      required String senatorialDistrictName,
      required String lgaId,
      required String lgaName,
    }) => GeographicScope(
          level: GeographyLevel.lga,
          country: 'Nigeria',
          zoneId: zoneId,
          zoneName: zoneName,
          stateId: stateId,
          stateName: stateName,
          senatorialDistrictId: senatorialDistrictId,
          senatorialDistrictName: senatorialDistrictName,
          lgaId: lgaId,
          lgaName: lgaName,
        );

    final kadunaNorth = lga(
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/053/KD',
      senatorialDistrictName: 'Kaduna Central',
      lgaId: 'KD-KADUNA-NORTH',
      lgaName: 'Kaduna North',
    );
    final zaria = lga(
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/052/KD',
      senatorialDistrictName: 'Kaduna North',
      lgaId: 'KD-ZARIA',
      lgaName: 'Zaria',
    );
    final jemaa = lga(
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/054/KD',
      senatorialDistrictName: 'Kaduna South',
      lgaId: 'KD-JEMAA',
      lgaName: "Jema'a",
    );
    final kadunaSouth = lga(
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/053/KD',
      senatorialDistrictName: 'Kaduna Central',
      lgaId: 'KD-KADUNA-SOUTH',
      lgaName: 'Kaduna South',
    );

    EvidenceAttachment photo(String id, String uploader, DateTime at) =>
        EvidenceAttachment(
          id: id,
          type: EvidenceType.photo,
          fileName: '$id.jpg',
          createdAt: at,
          uploaderId: uploader,
          contentHash: 'sha256:prototype-$id',
          mimeType: 'image/jpeg',
          caption: 'Prototype evidence record. Replace with verified field media.',
          origin: RecordOrigin.systemDerived,
        );

    EvidenceAttachment video(
      String id,
      String uploader,
      DateTime at, {
      double? latitude,
      double? longitude,
    }) =>
        EvidenceAttachment(
          id: id,
          type: EvidenceType.video,
          fileName: '$id.mp4',
          createdAt: at,
          uploaderId: uploader,
          contentHash: 'sha256:prototype-$id',
          mimeType: 'video/mp4',
          caption:
              'Prototype security video evidence. Replace with verified field media.',
          sourceReference: 'prototype://$id.mp4',
          latitude: latitude,
          longitude: longitude,
          origin: RecordOrigin.systemDerived,
        );

    return FieldOperationsController._(
      persistence: persistence,
      incidents: [
        FieldIncident(
          id: 'INC-0001',
          title: 'Polling-unit access obstruction reported',
          category: 'Access',
          severity: IncidentSeverity.high,
          status: IncidentStatus.investigating,
          scope: kadunaNorth,
          reportedAt: now.subtract(const Duration(minutes: 16)),
          reporterId: 'AG-KD-001',
          summary: 'Field team reported delayed access and requested coordinator review.',
          assignedTeam: 'Kaduna Central Response Desk',
          evidence: [photo('EVD-0001', 'AG-KD-001', now.subtract(const Duration(minutes: 15)))],
          origin: RecordOrigin.systemDerived,
        ),
        FieldIncident(
          id: 'INC-0002',
          title: 'Result-form image quality below review threshold',
          category: 'Evidence quality',
          severity: IncidentSeverity.medium,
          status: IncidentStatus.assigned,
          scope: zaria,
          reportedAt: now.subtract(const Duration(minutes: 31)),
          reporterId: 'AG-ZA-014',
          summary: 'Uploaded form is readable only in part; recapture requested.',
          assignedTeam: 'Evidence Verification Desk',
          evidence: [photo('EVD-0002', 'AG-ZA-014', now.subtract(const Duration(minutes: 30)))],
          origin: RecordOrigin.systemDerived,
        ),
        FieldIncident(
          id: 'INC-0003',
          title: 'Agent check-in requires location verification',
          category: 'Geolocation',
          severity: IncidentSeverity.low,
          status: IncidentStatus.acknowledged,
          scope: jemaa,
          reportedAt: now.subtract(const Duration(minutes: 48)),
          reporterId: 'AG-JM-032',
          summary: 'Reported GPS position is outside the configured operational radius.',
          assignedTeam: "Jema'a LGA Coordination Desk",
          origin: RecordOrigin.systemDerived,
        ),
        FieldIncident(
          id: 'INC-0005',
          title: 'Crowd disturbance near Jema\'a collation centre',
          category: 'Security',
          severity: IncidentSeverity.high,
          status: IncidentStatus.escalated,
          scope: jemaa,
          reportedAt: now.subtract(const Duration(minutes: 9)),
          reporterId: 'AG-JM-032',
          summary:
              'A large crowd has gathered at the collation centre gate; officials request security presence before collation resumes.',
          latitude: 9.580000,
          longitude: 8.290000,
          evidence: [
            video(
              'EVD-0005-VIDEO',
              'AG-JM-032',
              now.subtract(const Duration(minutes: 8)),
              latitude: 9.580000,
              longitude: 8.290000,
            ),
            photo(
              'EVD-0005-PHOTO',
              'AG-JM-032',
              now.subtract(const Duration(minutes: 8)),
            ),
          ],
          origin: RecordOrigin.systemDerived,
        ),
        FieldIncident(
          id: 'INC-0004',
          title: 'Field device unable to synchronize queued report',
          category: 'Technical',
          severity: IncidentSeverity.medium,
          status: IncidentStatus.reported,
          scope: kadunaSouth,
          reportedAt: now.subtract(const Duration(hours: 1, minutes: 8)),
          reporterId: 'AG-KN-009',
          summary: 'Report remains safely queued locally; technical support escalation required.',
          origin: RecordOrigin.systemDerived,
        ),
      ],
      reports: [
        FieldReport(
          id: 'RPT-0001',
          category: 'Opening status',
          summary: 'Team present; operational checklist completed and communications confirmed.',
          scope: kadunaNorth,
          reporterId: 'AG-KD-002',
          reportedAt: now.subtract(const Duration(minutes: 22)),
          status: RecordStatus.verified,
          origin: RecordOrigin.systemDerived,
        ),
        FieldReport(
          id: 'RPT-0002',
          category: 'Operational update',
          summary: 'Monitoring activity proceeding; one evidence-quality issue referred for review.',
          scope: zaria,
          reporterId: 'AG-ZA-014',
          reportedAt: now.subtract(const Duration(minutes: 37)),
          status: RecordStatus.underReview,
          incidentId: 'INC-0002',
          origin: RecordOrigin.systemDerived,
        ),
        FieldReport(
          id: 'RPT-0003',
          category: 'Connectivity update',
          summary: 'Intermittent connectivity detected. Offline queue operating normally.',
          scope: kadunaSouth,
          reporterId: 'AG-KN-009',
          reportedAt: now.subtract(const Duration(hours: 1)),
          status: RecordStatus.submitted,
          incidentId: 'INC-0004',
          origin: RecordOrigin.systemDerived,
        ),
      ],
    );
  }

  final List<FieldIncident> _incidents;
  final List<FieldReport> _reports;
  final OfflinePersistenceController? _persistence;
  final Map<String, List<IncidentStatusTransitionEvent>> _statusHistory = {};

  List<FieldIncident> get incidents => List.unmodifiable(_incidents);
  List<FieldReport> get reports => List.unmodifiable(_reports);

  List<IncidentStatusTransitionEvent> statusHistoryForIncident(
    String incidentId,
  ) =>
      List.unmodifiable(
        _statusHistory[incidentId] ??
            const <IncidentStatusTransitionEvent>[],
      );

  Future<void> hydrateFromOffline() async {
    final persistence = _persistence;
    if (persistence == null) return;

    final incidentRows = await persistence.readEntities(
      entityType: 'field_incident',
    );
    final reportRows = await persistence.readEntities(
      entityType: 'field_report',
    );
    var changed = false;

    for (final row in incidentRows) {
      final id = row['id']?.toString();
      final title = row['title']?.toString();
      final category = row['category']?.toString();
      final severity = _incidentSeverity(row['severity']);
      final status = _incidentStatus(row['status']);
      final scope = geographicScopeFromJson(row['scope']);
      final reportedAt =
          DateTime.tryParse(row['reportedAt']?.toString() ?? '')?.toUtc();
      final reporterId = row['reporterId']?.toString();
      if (id == null ||
          title == null ||
          category == null ||
          severity == null ||
          status == null ||
          scope == null ||
          reportedAt == null ||
          reporterId == null) {
        continue;
      }
      final evidence = <EvidenceAttachment>[];
      final rawEvidence = row['evidence'];
      if (rawEvidence is List) {
        for (final value in rawEvidence) {
          final item = evidenceFromJson(value);
          if (item != null) evidence.add(item);
        }
      }
      final rawStatusHistory = row['statusHistory'];
      if (rawStatusHistory is List) {
        final restoredEvents = <IncidentStatusTransitionEvent>[];
        for (final value in rawStatusHistory) {
          final event = _statusEventFromJson(value);
          if (event != null && event.incidentId == id) {
            restoredEvents.add(event);
          }
        }
        restoredEvents.sort((a, b) => a.changedAt.compareTo(b.changedAt));
        if (restoredEvents.isNotEmpty) {
          _statusHistory[id] = restoredEvents;
        }
      }

      final restored = FieldIncident(
        id: id,
        title: title,
        category: category,
        severity: severity,
        status: status,
        scope: scope,
        reportedAt: reportedAt,
        reporterId: reporterId,
        summary: row['summary']?.toString(),
        assignedTeam: row['assignedTeam']?.toString(),
        assignmentId: row['assignmentId']?.toString(),
        deviceId: row['deviceId']?.toString(),
        latitude: _double(row['latitude']),
        longitude: _double(row['longitude']),
        evidence: List.unmodifiable(evidence),
        origin: _recordOrigin(row['origin']) ?? RecordOrigin.localEntry,
      );
      final index = _incidents.indexWhere((item) => item.id == id);
      if (index < 0) {
        _incidents.add(restored);
      } else {
        _incidents[index] = restored;
      }
      changed = true;
    }

    for (final row in reportRows) {
      final id = row['id']?.toString();
      final category = row['category']?.toString();
      final summary = row['summary']?.toString();
      final scope = geographicScopeFromJson(row['scope']);
      final reporterId = row['reporterId']?.toString();
      final reportedAt =
          DateTime.tryParse(row['reportedAt']?.toString() ?? '')?.toUtc();
      final status = _recordStatus(row['status']);
      if (id == null ||
          category == null ||
          summary == null ||
          scope == null ||
          reporterId == null ||
          reportedAt == null ||
          status == null) {
        continue;
      }
      final evidence = <EvidenceAttachment>[];
      final rawEvidence = row['evidence'];
      if (rawEvidence is List) {
        for (final value in rawEvidence) {
          final item = evidenceFromJson(value);
          if (item != null) evidence.add(item);
        }
      }
      final restored = FieldReport(
        id: id,
        category: category,
        summary: summary,
        scope: scope,
        reporterId: reporterId,
        reportedAt: reportedAt,
        status: status,
        incidentId: row['incidentId']?.toString(),
        evidence: List.unmodifiable(evidence),
        origin: _recordOrigin(row['origin']) ?? RecordOrigin.localEntry,
      );
      final index = _reports.indexWhere((item) => item.id == id);
      if (index < 0) {
        _reports.add(restored);
      } else {
        _reports[index] = restored;
      }
      changed = true;
    }

    if (changed) {
      _incidents.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
      _reports.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
      notifyListeners();
    }
  }

  List<FieldIncident> incidentsForScope(GeographicScope scope) =>
      _incidents.where((item) => _within(scope, item.scope)).toList(growable: false);

  List<FieldReport> reportsForScope(GeographicScope scope) =>
      _reports.where((item) => _within(scope, item.scope)).toList(growable: false);

  int get unresolvedIncidentCount => _incidents
      .where((item) => item.status != IncidentStatus.resolved && item.status != IncidentStatus.closed)
      .length;

  int get highPriorityIncidentCount => _incidents
      .where((item) =>
          item.severity == IncidentSeverity.high || item.severity == IncidentSeverity.critical)
      .length;

  int get evidenceCount => _incidents.fold<int>(
        0,
        (total, incident) => total + incident.evidence.length,
      );

  Future<FieldIncident> createIncident({
    required String title,
    required String category,
    required IncidentSeverity severity,
    required GeographicScope scope,
    required String reporterId,
    String? summary,
    String? assignmentId,
    String? deviceId,
    double? latitude,
    double? longitude,
    List<EvidenceAttachment> evidence = const [],
  }) async {
    final incident = FieldIncident(
      id: 'INC-${(_incidents.length + 1).toString().padLeft(4, '0')}',
      title: title.trim(),
      category: category.trim(),
      severity: severity,
      status: IncidentStatus.reported,
      scope: scope,
      reportedAt: DateTime.now().toUtc(),
      reporterId: reporterId,
      summary: summary?.trim().isEmpty == true ? null : summary?.trim(),
      assignmentId:
          assignmentId?.trim().isEmpty == true ? null : assignmentId?.trim(),
      deviceId: deviceId?.trim().isEmpty == true ? null : deviceId?.trim(),
      latitude: latitude,
      longitude: longitude,
      evidence: List.unmodifiable(evidence),
      origin: RecordOrigin.localEntry,
    );
    await _persistence?.persistMutation(
      entityType: 'field_incident',
      entityId: incident.id,
      mutationType: SyncMutationType.create,
      payload: fieldIncidentToJson(incident),
      scopeKey: scopeStorageKey(scope),
      ownerId: reporterId,
    );
    _incidents.insert(0, incident);
    notifyListeners();
    return incident;
  }

  Future<FieldReport> submitFieldReport({
    required String category,
    required String summary,
    required GeographicScope scope,
    required String reporterId,
    String? incidentId,
    List<EvidenceAttachment> evidence = const [],
  }) async {
    final report = FieldReport(
      id: 'RPT-${(_reports.length + 1).toString().padLeft(4, '0')}',
      category: category.trim(),
      summary: summary.trim(),
      scope: scope,
      reporterId: reporterId,
      reportedAt: DateTime.now().toUtc(),
      status: RecordStatus.submitted,
      incidentId: incidentId,
      evidence: List.unmodifiable(evidence),
      origin: RecordOrigin.localEntry,
    );
    await _persistence?.persistMutation(
      entityType: 'field_report',
      entityId: report.id,
      mutationType: SyncMutationType.create,
      payload: fieldReportToJson(report),
      scopeKey: scopeStorageKey(scope),
      ownerId: reporterId,
    );
    _reports.insert(0, report);
    notifyListeners();
    return report;
  }

  Future<bool> updateIncidentStatus(
    String incidentId,
    IncidentStatus status, {
    required String actorId,
    required TgcgRole actorRole,
    required GeographicScope authorizedScope,
  }) async {
    final index = _incidents.indexWhere((item) => item.id == incidentId);
    if (index < 0) return false;
    final incident = _incidents[index];
    if (incident.status == status) return true;
    if (status == IncidentStatus.reported) {
      throw StateError('An incident cannot be returned to the reported state.');
    }

    final capability = incidentStatusMutationCapability(status);
    if (!TgcgPermissionPolicy.may(
      actorRole,
      authorizedScope,
      capability,
      targetScope: incident.scope,
    )) {
      throw StateError(
        'This account cannot change the incident to ${status.name} in this scope.',
      );
    }

    final changedAt = DateTime.now().toUtc();
    final updated = FieldIncident(
      id: incident.id,
      title: incident.title,
      category: incident.category,
      severity: incident.severity,
      status: status,
      scope: incident.scope,
      reportedAt: incident.reportedAt,
      reporterId: incident.reporterId,
      summary: incident.summary,
      assignedTeam: incident.assignedTeam,
      assignmentId: incident.assignmentId,
      deviceId: incident.deviceId,
      latitude: incident.latitude,
      longitude: incident.longitude,
      evidence: incident.evidence,
      origin: incident.origin,
    );
    final event = IncidentStatusTransitionEvent(
      id: newLocalId('INC-EVT', changedAt),
      incidentId: incident.id,
      fromStatus: incident.status,
      toStatus: status,
      actorId: actorId,
      actorRole: actorRole,
      changedAt: changedAt,
      scope: incident.scope,
    );
    final history = <IncidentStatusTransitionEvent>[
      ...?_statusHistory[incident.id],
      event,
    ];

    await _persistence?.persistMutation(
      entityType: 'field_incident',
      entityId: updated.id,
      mutationType: SyncMutationType.update,
      payload: {
        ...fieldIncidentToJson(updated),
        'statusHistory': history.map(_statusEventToJson).toList(growable: false),
      },
      scopeKey: scopeStorageKey(updated.scope),
      ownerId: actorId,
    );

    _incidents[index] = updated;
    _statusHistory[incident.id] = history;
    notifyListeners();
    return true;
  }

  static Map<String, Object?> _statusEventToJson(
    IncidentStatusTransitionEvent event,
  ) =>
      {
        'id': event.id,
        'incidentId': event.incidentId,
        'fromStatus': event.fromStatus.name,
        'toStatus': event.toStatus.name,
        'actorId': event.actorId,
        'actorRole': event.actorRole.name,
        'changedAt': event.changedAt.toUtc().toIso8601String(),
        'scope': geographicScopeToJson(event.scope),
      };

  static IncidentStatusTransitionEvent? _statusEventFromJson(Object? value) {
    if (value is! Map) return null;
    final map = value.map(
      (key, item) => MapEntry(key.toString(), item),
    );
    final id = map['id']?.toString();
    final incidentId = map['incidentId']?.toString();
    final fromStatus = _incidentStatus(map['fromStatus']);
    final toStatus = _incidentStatus(map['toStatus']);
    final actorId = map['actorId']?.toString();
    final actorRoleName = map['actorRole']?.toString();
    final actorRole = TgcgRole.values
        .where((item) => item.name == actorRoleName)
        .firstOrNull;
    final changedAt =
        DateTime.tryParse(map['changedAt']?.toString() ?? '')?.toUtc();
    final scope = geographicScopeFromJson(map['scope']);
    if (id == null ||
        incidentId == null ||
        fromStatus == null ||
        toStatus == null ||
        actorId == null ||
        actorRole == null ||
        changedAt == null ||
        scope == null) {
      return null;
    }
    return IncidentStatusTransitionEvent(
      id: id,
      incidentId: incidentId,
      fromStatus: fromStatus,
      toStatus: toStatus,
      actorId: actorId,
      actorRole: actorRole,
      changedAt: changedAt,
      scope: scope,
    );
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static IncidentSeverity? _incidentSeverity(Object? value) {
    final name = value?.toString();
    for (final item in IncidentSeverity.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static IncidentStatus? _incidentStatus(Object? value) {
    final name = value?.toString();
    for (final item in IncidentStatus.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static RecordStatus? _recordStatus(Object? value) {
    final name = value?.toString();
    for (final item in RecordStatus.values) {
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

  bool _within(GeographicScope parent, GeographicScope child) {
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class FieldOperations extends InheritedNotifier<FieldOperationsController> {
  const FieldOperations({
    super.key,
    required FieldOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static FieldOperationsController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<FieldOperations>();
      assert(value != null, 'FieldOperations is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<FieldOperations>();
    final value = element?.widget as FieldOperations?;
    assert(value != null, 'FieldOperations is missing above this context.');
    return value!.notifier!;
  }
}
