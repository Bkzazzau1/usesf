import 'package:flutter/widgets.dart';

import '../domain/local_id.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../governance/governance_store.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

enum ReportKind {
  executiveBrief,
  incidentSummary,
  fieldActivity,
  membershipDeployment,
  verifiedCollation,
  evidencePackage,
  auditTrail,
  syncOutbox,
}

enum ExportFormat { pdf, csv, json, zip }

enum ExportJobStatus { queued, generating, completed, failed }

class ReportExportJob {
  const ReportExportJob({
    required this.id,
    required this.kind,
    required this.format,
    required this.scope,
    required this.requestedBy,
    required this.requestedAt,
    required this.status,
    this.recordCount,
    this.completedAt,
    this.fileName,
    this.contentHash,
    this.error,
  });

  final String id;
  final ReportKind kind;
  final ExportFormat format;
  final GeographicScope scope;
  final String requestedBy;
  final DateTime requestedAt;
  final ExportJobStatus status;
  final int? recordCount;
  final DateTime? completedAt;
  final String? fileName;
  final String? contentHash;
  final String? error;
}

class ReportOperationsController extends ChangeNotifier {
  ReportOperationsController._({
    required GovernanceOperationsController governance,
    required List<ReportExportJob> jobs,
    OfflinePersistenceController? persistence,
  })  : _governance = governance,
        _jobs = jobs,
        _persistence = persistence;

  factory ReportOperationsController.productionFoundation({
    required GovernanceOperationsController governance,
    required OfflinePersistenceController persistence,
  }) =>
      ReportOperationsController._(
        governance: governance,
        jobs: <ReportExportJob>[],
        persistence: persistence,
      );

  factory ReportOperationsController.prototypeSeed(
    GovernanceOperationsController governance,
  ) {
    final now = DateTime.utc(2026, 9, 27, 8, 35);
    return ReportOperationsController._(
      governance: governance,
      jobs: [
        ReportExportJob(
          id: 'EXP-0001',
          kind: ReportKind.incidentSummary,
          format: ExportFormat.pdf,
          scope: GeographicScope.kaduna,
          requestedBy: 'SITUATION-ROOM',
          requestedAt: now.subtract(const Duration(hours: 2)),
          status: ExportJobStatus.completed,
          recordCount: 4,
          completedAt: now.subtract(const Duration(hours: 1, minutes: 58)),
          fileName: 'incident-summary-prototype.pdf',
          contentHash: 'sha256:prototype-export-exp-0001',
        ),
        ReportExportJob(
          id: 'EXP-0002',
          kind: ReportKind.auditTrail,
          format: ExportFormat.csv,
          scope: GeographicScope.kaduna,
          requestedBy: 'SYSTEM-ADMIN',
          requestedAt: now.subtract(const Duration(minutes: 54)),
          status: ExportJobStatus.completed,
          recordCount: governance.auditEvents.length,
          completedAt: now.subtract(const Duration(minutes: 53)),
          fileName: 'audit-trail-prototype.csv',
          contentHash: 'sha256:prototype-export-exp-0002',
        ),
        ReportExportJob(
          id: 'EXP-0003',
          kind: ReportKind.evidencePackage,
          format: ExportFormat.zip,
          scope: GeographicScope.kaduna,
          requestedBy: 'LEGAL-DESK',
          requestedAt: now.subtract(const Duration(minutes: 19)),
          status: ExportJobStatus.queued,
          recordCount: 3,
        ),
      ],
    );
  }

  final GovernanceOperationsController _governance;
  final List<ReportExportJob> _jobs;
  final OfflinePersistenceController? _persistence;

  List<ReportExportJob> get jobs => List.unmodifiable(_jobs);

  Future<void> hydrateFromOffline() async {
    final persistence = _persistence;
    if (persistence == null) return;

    final rows = await persistence.readEntities(entityType: 'report_export');
    var changed = false;
    for (final row in rows) {
      final restored = _jobFromJson(row);
      if (restored == null) continue;
      final index = _jobs.indexWhere((job) => job.id == restored.id);
      if (index < 0) {
        _jobs.add(restored);
      } else {
        _jobs[index] = restored;
      }
      changed = true;
    }
    if (changed) {
      _jobs.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
      notifyListeners();
    }
  }

  List<ReportExportJob> jobsForScope(
    GeographicScope scope, {
    TgcgRole? role,
  }) {
    final jobs = _jobs.where((job) {
      if (!GeographyRegistry.scopeContains(scope, job.scope)) return false;
      if (role == null) return true;
      return canExportKind(
        kind: job.kind,
        role: role,
        userScope: scope,
        targetScope: job.scope,
      );
    }).toList(growable: false)
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return jobs;
  }

  bool canExportKind({
    required ReportKind kind,
    required TgcgRole role,
    required GeographicScope userScope,
    required GeographicScope targetScope,
    Set<TgcgCapability>? effectiveCapabilities,
  }) {
    final scopedCapabilities = effectiveCapabilities;
    if (scopedCapabilities == null) {
      if (!TgcgPermissionPolicy.may(
        role,
        userScope,
        TgcgCapability.exportReports,
        targetScope: targetScope,
      )) {
        return false;
      }
    } else if (!scopedCapabilities.contains(TgcgCapability.exportReports)) {
      return false;
    }
    if (!GeographyRegistry.scopeContains(userScope, targetScope)) return false;

    bool allows(TgcgCapability capability) => scopedCapabilities != null
        ? scopedCapabilities.contains(capability)
        : TgcgPermissionPolicy.allows(role, capability);

    return switch (kind) {
      ReportKind.executiveBrief =>
        targetScope.level == GeographyLevel.state &&
            (role == TgcgRole.stateCoordinator ||
                role == TgcgRole.stateAdministrator ||
                role == TgcgRole.situationRoomDirector),
      ReportKind.incidentSummary => allows(TgcgCapability.viewIncidents),
      ReportKind.fieldActivity => allows(TgcgCapability.viewIncidents),
      ReportKind.membershipDeployment =>
        allows(TgcgCapability.manageMembership) ||
            allows(TgcgCapability.manageAssignments) ||
            allows(TgcgCapability.manageRoleAssignments),
      ReportKind.verifiedCollation => allows(TgcgCapability.viewCollation),
      ReportKind.evidencePackage => allows(TgcgCapability.viewEvidence),
      ReportKind.auditTrail => allows(TgcgCapability.viewAudit),
      ReportKind.syncOutbox =>
        targetScope.level == GeographyLevel.state &&
            allows(TgcgCapability.viewAudit),
    };
  }

  Future<ReportExportJob?> requestExport({
    required ReportKind kind,
    required ExportFormat format,
    required GeographicScope targetScope,
    required String actorId,
    required TgcgRole role,
    required GeographicScope userScope,
    Set<TgcgCapability>? effectiveCapabilities,
    int? recordCount,
  }) async {
    if (!canExportKind(
      kind: kind,
      role: role,
      userScope: userScope,
      targetScope: targetScope,
      effectiveCapabilities: effectiveCapabilities,
    )) {
      return null;
    }

    final requestedAt = DateTime.now().toUtc();
    final job = ReportExportJob(
      id: newLocalId('EXP', requestedAt),
      kind: kind,
      format: format,
      scope: targetScope,
      requestedBy: actorId,
      requestedAt: requestedAt,
      status: ExportJobStatus.queued,
      recordCount: recordCount,
    );
    await _persistence?.persistMutation(
      entityType: 'report_export',
      entityId: job.id,
      mutationType: SyncMutationType.create,
      payload: _jobToJson(job),
      scopeKey: scopeStorageKey(targetScope),
      ownerId: actorId,
    );
    _jobs.insert(0, job);
    _governance.recordAudit(
      actorId: actorId,
      action: 'report_export_requested',
      entityType: 'report_export',
      entityId: job.id,
      detail:
          '${kind.name} requested as ${format.name.toUpperCase()} for ${targetScope.label}.',
      scope: targetScope,
    );
    notifyListeners();
    return job;
  }

  Future<void> markGenerating(String id, {required String actorId}) async {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return;
    final updated = _copyJob(
      _jobs[index],
      status: ExportJobStatus.generating,
      clearError: true,
    );
    await _persistUpdate(updated, actorId: actorId);
    _jobs[index] = updated;
    _governance.recordAudit(
      actorId: actorId,
      action: 'report_export_generating',
      entityType: 'report_export',
      entityId: id,
      detail: 'Export worker accepted the queued report job.',
      scope: _jobs[index].scope,
    );
    notifyListeners();
  }

  Future<void> markCompleted(
    String id, {
    required String actorId,
    required String fileName,
    required String contentHash,
  }) async {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return;
    final updated = _copyJob(
      _jobs[index],
      status: ExportJobStatus.completed,
      completedAt: DateTime.now().toUtc(),
      fileName: fileName,
      contentHash: contentHash,
      clearError: true,
    );
    await _persistUpdate(updated, actorId: actorId);
    _jobs[index] = updated;
    _governance.recordAudit(
      actorId: actorId,
      action: 'report_export_completed',
      entityType: 'report_export',
      entityId: id,
      detail: 'Export artifact completed with content hash $contentHash.',
      scope: _jobs[index].scope,
    );
    notifyListeners();
  }

  Future<void> markFailed(
    String id, {
    required String actorId,
    required String error,
  }) async {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return;
    final updated = _copyJob(
      _jobs[index],
      status: ExportJobStatus.failed,
      error: error,
    );
    await _persistUpdate(updated, actorId: actorId);
    _jobs[index] = updated;
    _governance.recordAudit(
      actorId: actorId,
      action: 'report_export_failed',
      entityType: 'report_export',
      entityId: id,
      detail: error,
      scope: _jobs[index].scope,
    );
    notifyListeners();
  }

  Future<void> _persistUpdate(
    ReportExportJob job, {
    required String actorId,
  }) async {
    await _persistence?.persistMutation(
      entityType: 'report_export',
      entityId: job.id,
      mutationType: SyncMutationType.update,
      payload: _jobToJson(job),
      scopeKey: scopeStorageKey(job.scope),
      ownerId: actorId,
    );
  }

  static Map<String, Object?> _jobToJson(ReportExportJob job) => {
        'id': job.id,
        'kind': job.kind.name,
        'format': job.format.name,
        'scope': geographicScopeToJson(job.scope),
        'requestedBy': job.requestedBy,
        'requestedAt': job.requestedAt.toUtc().toIso8601String(),
        'status': job.status.name,
        'recordCount': job.recordCount,
        'completedAt': job.completedAt?.toUtc().toIso8601String(),
        'fileName': job.fileName,
        'contentHash': job.contentHash,
        'error': job.error,
      };

  static ReportExportJob? _jobFromJson(Map<String, Object?> row) {
    final id = row['id']?.toString();
    final kind = _enumValue(ReportKind.values, row['kind']);
    final format = _enumValue(ExportFormat.values, row['format']);
    final scope = geographicScopeFromJson(row['scope']);
    final requestedBy = row['requestedBy']?.toString();
    final requestedAt =
        DateTime.tryParse(row['requestedAt']?.toString() ?? '')?.toUtc();
    final status = _enumValue(ExportJobStatus.values, row['status']);
    final completedRaw = row['completedAt']?.toString();
    final completedAt = completedRaw == null || completedRaw.isEmpty
        ? null
        : DateTime.tryParse(completedRaw)?.toUtc();
    if (id == null ||
        kind == null ||
        format == null ||
        scope == null ||
        requestedBy == null ||
        requestedAt == null ||
        status == null) {
      return null;
    }
    return ReportExportJob(
      id: id,
      kind: kind,
      format: format,
      scope: scope,
      requestedBy: requestedBy,
      requestedAt: requestedAt,
      status: status,
      recordCount: _intValue(row['recordCount']),
      completedAt: completedAt,
      fileName: row['fileName']?.toString(),
      contentHash: row['contentHash']?.toString(),
      error: row['error']?.toString(),
    );
  }

  static T? _enumValue<T extends Enum>(List<T> values, Object? raw) {
    final name = raw?.toString();
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static int? _intValue(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static ReportExportJob _copyJob(
    ReportExportJob current, {
    ExportJobStatus? status,
    DateTime? completedAt,
    String? fileName,
    String? contentHash,
    String? error,
    bool clearError = false,
  }) =>
      ReportExportJob(
        id: current.id,
        kind: current.kind,
        format: current.format,
        scope: current.scope,
        requestedBy: current.requestedBy,
        requestedAt: current.requestedAt,
        status: status ?? current.status,
        recordCount: current.recordCount,
        completedAt: completedAt ?? current.completedAt,
        fileName: fileName ?? current.fileName,
        contentHash: contentHash ?? current.contentHash,
        error: clearError ? null : error ?? current.error,
      );
}

class ReportOperations extends InheritedNotifier<ReportOperationsController> {
  const ReportOperations({
    super.key,
    required ReportOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static ReportOperationsController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<ReportOperations>();
      assert(value != null, 'ReportOperations is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<ReportOperations>();
    final value = element?.widget as ReportOperations?;
    assert(value != null, 'ReportOperations is missing above this context.');
    return value!.notifier!;
  }
}
