import 'dart:async';

import 'package:flutter/widgets.dart';

import '../domain/local_id.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

enum SystemSettingCategory { security, sync, evidence, communications }

class SystemSettingRecord {
  const SystemSettingRecord({
    required this.id,
    required this.label,
    required this.category,
    required this.value,
    required this.updatedAt,
    required this.updatedBy,
    this.description,
  });

  final String id;
  final String label;
  final SystemSettingCategory category;
  final bool value;
  final DateTime updatedAt;
  final String updatedBy;
  final String? description;
}

class RoleAssignmentRecord {
  const RoleAssignmentRecord({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.role,
    required this.scope,
    required this.assignedBy,
    required this.assignedAt,
    required this.active,
    this.revokedBy,
    this.revokedAt,
  });

  final String id;
  final String subjectId;
  final String subjectName;
  final TgcgRole role;
  final GeographicScope scope;
  final String assignedBy;
  final DateTime assignedAt;
  final bool active;
  final String? revokedBy;
  final DateTime? revokedAt;
}

class GovernanceOperationsController extends ChangeNotifier {
  GovernanceOperationsController._({
    required OfflinePersistenceController? persistence,
    required List<AuditEvent> auditEvents,
    required List<SystemSettingRecord> settings,
    required List<RoleAssignmentRecord> roleAssignments,
  })  : _persistence = persistence,
        _auditEvents = auditEvents,
        _settings = settings,
        _roleAssignments = roleAssignments {
    _persistence?.addListener(_onPersistenceChanged);
  }

  factory GovernanceOperationsController.productionFoundation({
    required OfflinePersistenceController persistence,
  }) {
    final now = DateTime.now().toUtc();
    return GovernanceOperationsController._(
      persistence: persistence,
      auditEvents: <AuditEvent>[],
      settings: _defaultSettings(now),
      roleAssignments: <RoleAssignmentRecord>[],
    );
  }

  factory GovernanceOperationsController.prototypeSeed({
    OfflinePersistenceController? persistence,
  }) {
    final now = DateTime.utc(2026, 9, 27, 8, 10);
    return GovernanceOperationsController._(
      persistence: persistence,
      auditEvents: [
        AuditEvent(
          id: 'AUD-0001',
          actorId: 'SYSTEM',
          action: 'prototype_seed_loaded',
          entityType: 'system',
          entityId: 'USESF',
          timestamp: now.subtract(const Duration(minutes: 45)),
          detail: 'Operational stores initialized.',
          scope: GeographicScope.kaduna,
        ),
        AuditEvent(
          id: 'AUD-0002',
          actorId: 'COLLATION-DESK',
          action: 'result_verified',
          entityType: 'election_result',
          entityId: 'RES-0001',
          timestamp: now.subtract(const Duration(minutes: 32)),
          detail: 'Result accepted into verified-only collation.',
          scope: GeographicScope.kaduna,
        ),
      ],
      settings: [
        SystemSettingRecord(
          id: 'SET-MFA',
          label: 'Administrator MFA required',
          category: SystemSettingCategory.security,
          value: true,
          updatedAt: now.subtract(const Duration(days: 1)),
          updatedBy: 'SYSTEM',
          description: 'Privileged administrator access requires MFA.',
        ),
        SystemSettingRecord(
          id: 'SET-EVIDENCE-HASH',
          label: 'Evidence hash required',
          category: SystemSettingCategory.evidence,
          value: true,
          updatedAt: now.subtract(const Duration(days: 1)),
          updatedBy: 'SYSTEM',
          description: 'Evidence records require a cryptographic content hash before acceptance.',
        ),
        SystemSettingRecord(
          id: 'SET-OFFLINE-QUEUE',
          label: 'Offline durable queue enabled',
          category: SystemSettingCategory.sync,
          value: true,
          updatedAt: now.subtract(const Duration(days: 1)),
          updatedBy: 'SYSTEM',
          description: 'Operational writes remain usable locally while awaiting connectivity.',
        ),
      ],
      roleAssignments: [
        RoleAssignmentRecord(
          id: 'ROLE-0001',
          subjectId: 'MEM-0005',
          subjectName: 'Hauwa Bello',
          role: TgcgRole.senatorialCoordinator,
          scope: GeographicScope(
            level: GeographyLevel.senatorialDistrict,
            country: 'Nigeria',
            zoneId: 'NW',
            zoneName: 'North West',
            stateId: 'KD',
            stateName: 'Kaduna',
            senatorialDistrictId: 'SD/052/KD',
            senatorialDistrictName: 'Kaduna North',
          ),
          assignedBy: 'STATE-ADMIN',
          assignedAt: now.subtract(const Duration(days: 8)),
          active: true,
        ),
        RoleAssignmentRecord(
          id: 'ROLE-0002',
          subjectId: 'MEM-0006',
          subjectName: 'Ibrahim Musa',
          role: TgcgRole.senatorialCoordinator,
          scope: GeographicScope(
            level: GeographyLevel.senatorialDistrict,
            country: 'Nigeria',
            zoneId: 'NW',
            zoneName: 'North West',
            stateId: 'KD',
            stateName: 'Kaduna',
            senatorialDistrictId: 'SD/053/KD',
            senatorialDistrictName: 'Kaduna Central',
          ),
          assignedBy: 'STATE-ADMIN',
          assignedAt: now.subtract(const Duration(days: 8)),
          active: true,
        ),
        RoleAssignmentRecord(
          id: 'ROLE-0003',
          subjectId: 'MEM-0010',
          subjectName: 'Grace Yakubu',
          role: TgcgRole.senatorialCoordinator,
          scope: GeographicScope(
            level: GeographyLevel.senatorialDistrict,
            country: 'Nigeria',
            zoneId: 'NW',
            zoneName: 'North West',
            stateId: 'KD',
            stateName: 'Kaduna',
            senatorialDistrictId: 'SD/054/KD',
            senatorialDistrictName: 'Kaduna South',
          ),
          assignedBy: 'STATE-ADMIN',
          assignedAt: now.subtract(const Duration(days: 4)),
          active: true,
        ),
      ],
    );
  }

  final OfflinePersistenceController? _persistence;
  final List<AuditEvent> _auditEvents;
  final List<SystemSettingRecord> _settings;
  final List<RoleAssignmentRecord> _roleAssignments;

  List<AuditEvent> get auditEvents => List.unmodifiable(_auditEvents);
  List<SyncOutboxItem> get outbox =>
      _persistence == null ? const [] : _persistence.outbox;
  List<SystemSettingRecord> get settings => List.unmodifiable(_settings);
  List<RoleAssignmentRecord> get roleAssignments =>
      List.unmodifiable(_roleAssignments);

  Future<void> hydrateFromOffline() async {
    final persistence = _persistence;
    if (persistence == null) return;

    final auditRows =
        await persistence.readEntities(entityType: 'governance_audit_event');
    final settingRows =
        await persistence.readEntities(entityType: 'governance_system_setting');
    final roleRows =
        await persistence.readEntities(entityType: 'governance_role_assignment');

    var changed = false;
    for (final row in auditRows) {
      final restored = _auditEventFromJson(row);
      if (restored == null) continue;
      final index = _auditEvents.indexWhere((item) => item.id == restored.id);
      if (index < 0) {
        _auditEvents.add(restored);
      } else {
        _auditEvents[index] = restored;
      }
      changed = true;
    }

    for (final row in settingRows) {
      final restored = _settingFromJson(row);
      if (restored == null) continue;
      final index = _settings.indexWhere((item) => item.id == restored.id);
      if (index < 0) {
        _settings.add(restored);
      } else {
        _settings[index] = restored;
      }
      changed = true;
    }

    for (final row in roleRows) {
      final restored = _roleAssignmentFromJson(row);
      if (restored == null) continue;
      final index =
          _roleAssignments.indexWhere((item) => item.id == restored.id);
      if (index < 0) {
        _roleAssignments.add(restored);
      } else {
        _roleAssignments[index] = restored;
      }
      changed = true;
    }

    if (changed) {
      _auditEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _roleAssignments.sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
      notifyListeners();
    }
  }

  List<AuditEvent> auditForScope(GeographicScope scope) => _auditEvents
      .where((event) => event.scope == null || _overlaps(scope, event.scope!))
      .toList(growable: false)
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  List<RoleAssignmentRecord> roleAssignmentsForScope(GeographicScope scope) =>
      _roleAssignments
          .where((item) => _overlaps(scope, item.scope))
          .toList(growable: false)
        ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

  List<SyncOutboxItem> get pendingOutbox =>
      outbox.where((item) => item.isPending).toList(growable: false);

  List<RoleAssignmentRecord> activeRolesForMember(String memberId) =>
      _roleAssignments
          .where((item) => item.subjectId == memberId && item.active)
          .toList(growable: false);

  Future<RoleAssignmentRecord> assignRole({
    required String subjectId,
    required String subjectName,
    required TgcgRole role,
    required GeographicScope scope,
    required String assignedBy,
    required TgcgRole actorRole,
    required GeographicScope authorizedScope,
  }) async {
    _requireRoleManagementAuthority(
      actorRole: actorRole,
      authorizedScope: authorizedScope,
      targetRole: role,
      targetScope: scope,
    );

    for (final current in _roleAssignments) {
      if (current.subjectId == subjectId &&
          current.role == role &&
          current.active &&
          _sameScope(current.scope, scope)) {
        return current;
      }
    }

    final now = DateTime.now().toUtc();
    final record = RoleAssignmentRecord(
      id: newLocalId('ROLE', now),
      subjectId: subjectId,
      subjectName: subjectName,
      role: role,
      scope: scope,
      assignedBy: assignedBy,
      assignedAt: now,
      active: true,
    );
    await _persistRoleAssignment(record);
    _roleAssignments.insert(0, record);
    final audit = _appendAudit(
      actorId: assignedBy,
      action: 'role_assigned',
      entityType: 'access_role',
      entityId: record.id,
      detail: '${role.name} assigned to $subjectName for ${scope.label}.',
      scope: scope,
    );
    await _persistAudit(audit);
    return record;
  }

  Future<void> revokeRole(
    String assignmentId, {
    required String actorId,
    required TgcgRole actorRole,
    required GeographicScope authorizedScope,
  }) async {
    final index = _roleAssignments.indexWhere((item) => item.id == assignmentId);
    if (index < 0) return;
    final current = _roleAssignments[index];
    if (!current.active) return;

    _requireRoleManagementAuthority(
      actorRole: actorRole,
      authorizedScope: authorizedScope,
      targetRole: current.role,
      targetScope: current.scope,
    );
    if (current.assignedBy != actorId &&
        actorRole != TgcgRole.stateCoordinator &&
        actorRole != TgcgRole.stateAdministrator) {
      throw StateError(
        'Only the person who assigned this role, or State-level authority, can remove it.',
      );
    }

    final now = DateTime.now().toUtc();
    final updated = RoleAssignmentRecord(
      id: current.id,
      subjectId: current.subjectId,
      subjectName: current.subjectName,
      role: current.role,
      scope: current.scope,
      assignedBy: current.assignedBy,
      assignedAt: current.assignedAt,
      active: false,
      revokedBy: actorId,
      revokedAt: now,
    );
    await _persistRoleAssignment(updated);
    _roleAssignments[index] = updated;
    final audit = _appendAudit(
      actorId: actorId,
      action: 'role_revoked',
      entityType: 'access_role',
      entityId: current.id,
      detail: '${current.role.name} revoked from ${current.subjectName}.',
      scope: current.scope,
    );
    await _persistAudit(audit);
  }

  void recordAudit({
    required String actorId,
    required String action,
    required String entityType,
    required String entityId,
    String? detail,
    String? deviceId,
    GeographicScope? scope,
  }) {
    final event = _appendAudit(
      actorId: actorId,
      action: action,
      entityType: entityType,
      entityId: entityId,
      detail: detail,
      deviceId: deviceId,
      scope: scope,
    );
    if (_persistence != null) {
      unawaited(_persistAudit(event));
    }
  }

  Future<void> queueForRetry(
    String outboxId, {
    required String actorId,
    required TgcgRole actorRole,
    required GeographicScope authorizedScope,
  }) async {
    final persistence = _persistence;
    if (persistence == null) return;
    if (!TgcgPermissionPolicy.may(
      actorRole,
      authorizedScope,
      TgcgCapability.manageSystemSettings,
      targetScope: GeographicScope.kaduna,
    )) {
      throw StateError('This account cannot manage the durable sync queue.');
    }

    final current = outbox.where((item) => item.id == outboxId).firstOrNull;
    if (current == null) return;
    await persistence.queueForRetry(outboxId);
    final audit = _appendAudit(
      actorId: actorId,
      action: 'sync_retry_queued',
      entityType: current.entityType,
      entityId: current.entityId,
      detail: 'Outbox ${current.id} returned to the retry queue.',
      scope: GeographicScope.kaduna,
    );
    await _persistAudit(audit);
  }

  Future<void> setSetting({
    required String settingId,
    required bool value,
    required String actorId,
    required TgcgRole actorRole,
    required GeographicScope authorizedScope,
  }) async {
    if (!TgcgPermissionPolicy.may(
      actorRole,
      authorizedScope,
      TgcgCapability.manageSystemSettings,
      targetScope: GeographicScope.kaduna,
    )) {
      throw StateError('This account cannot change protected system settings.');
    }

    final index = _settings.indexWhere((item) => item.id == settingId);
    if (index < 0) return;
    final current = _settings[index];
    final updated = SystemSettingRecord(
      id: current.id,
      label: current.label,
      category: current.category,
      value: value,
      updatedAt: DateTime.now().toUtc(),
      updatedBy: actorId,
      description: current.description,
    );
    await _persistSetting(updated);
    _settings[index] = updated;
    final audit = _appendAudit(
      actorId: actorId,
      action: 'system_setting_changed',
      entityType: 'system_setting',
      entityId: current.id,
      detail: '${current.label} set to $value.',
      scope: GeographicScope.kaduna,
    );
    await _persistAudit(audit);
  }

  AuditEvent _appendAudit({
    required String actorId,
    required String action,
    required String entityType,
    required String entityId,
    String? detail,
    String? deviceId,
    GeographicScope? scope,
  }) {
    final now = DateTime.now().toUtc();
    final event = AuditEvent(
      id: newLocalId('AUD', now),
      actorId: actorId,
      action: action,
      entityType: entityType,
      entityId: entityId,
      timestamp: now,
      detail: detail,
      deviceId: deviceId,
      scope: scope,
    );
    _auditEvents.insert(0, event);
    notifyListeners();
    return event;
  }

  Future<void> _persistRoleAssignment(RoleAssignmentRecord record) async {
    final persistence = _persistence;
    if (persistence == null) return;
    await persistence.persistMutation(
      entityType: 'governance_role_assignment',
      entityId: record.id,
      mutationType: SyncMutationType.upsert,
      scopeKey: scopeStorageKey(record.scope),
      ownerId: record.subjectId,
      payload: _roleAssignmentToJson(record),
    );
  }

  Future<void> _persistSetting(SystemSettingRecord setting) async {
    final persistence = _persistence;
    if (persistence == null) return;
    await persistence.persistMutation(
      entityType: 'governance_system_setting',
      entityId: setting.id,
      mutationType: SyncMutationType.upsert,
      scopeKey: scopeStorageKey(GeographicScope.kaduna),
      ownerId: setting.updatedBy,
      payload: _settingToJson(setting),
    );
  }

  Future<void> _persistAudit(AuditEvent event) async {
    final persistence = _persistence;
    if (persistence == null) return;
    await persistence.persistMutation(
      entityType: 'governance_audit_event',
      entityId: event.id,
      mutationType: SyncMutationType.create,
      scopeKey: event.scope == null ? null : scopeStorageKey(event.scope!),
      ownerId: event.actorId,
      payload: _auditEventToJson(event),
    );
  }

  void _onPersistenceChanged() => notifyListeners();

  void _requireRoleManagementAuthority({
    required TgcgRole actorRole,
    required GeographicScope authorizedScope,
    required TgcgRole targetRole,
    required GeographicScope targetScope,
  }) {
    if (!TgcgPermissionPolicy.may(
      actorRole,
      authorizedScope,
      TgcgCapability.manageRoleAssignments,
      targetScope: targetScope,
    )) {
      throw StateError('This account cannot manage roles in the selected scope.');
    }
    if (!_roleAssignableBy(actorRole, targetRole)) {
      throw StateError('This role cannot be assigned by the current authority.');
    }
  }

  static bool _roleAssignableBy(TgcgRole actor, TgcgRole target) {
    if (actor == TgcgRole.stateAdministrator) {
      return _assignableRoles.contains(target);
    }
    final actorRank = _coordinatorRank(actor);
    if (actorRank < 1) return false;
    if (_functionalRoles.contains(target)) return true;
    final targetRank = _coordinatorRank(target);
    return targetRank >= 0 && targetRank < actorRank;
  }

  static int _coordinatorRank(TgcgRole role) => switch (role) {
        TgcgRole.stateCoordinator => 5,
        TgcgRole.senatorialCoordinator => 4,
        TgcgRole.lgaCoordinator => 3,
        TgcgRole.wardCoordinator => 2,
        TgcgRole.pollingUnitCoordinator => 1,
        TgcgRole.pollingUnitAgent => 0,
        _ => -1,
      };

  static const Set<TgcgRole> _functionalRoles = {
    TgcgRole.mediaOfficer,
    TgcgRole.womenMobilizationCoordinator,
    TgcgRole.youthMobilizationCoordinator,
    TgcgRole.communicationsOfficer,
    TgcgRole.logisticsOfficer,
    TgcgRole.monitoringEvaluationOfficer,
    TgcgRole.dataEvidenceOfficer,
    TgcgRole.transportCoordinator,
    TgcgRole.trainingOfficer,
    TgcgRole.ictOfficer,
    TgcgRole.observer,
    TgcgRole.legalOfficer,
    TgcgRole.technicalSupport,
    TgcgRole.readOnlyExecutive,
  };

  static const Set<TgcgRole> _assignableRoles = {
    TgcgRole.senatorialCoordinator,
    TgcgRole.lgaCoordinator,
    TgcgRole.wardCoordinator,
    TgcgRole.pollingUnitCoordinator,
    TgcgRole.pollingUnitAgent,
    ..._functionalRoles,
  };

  static List<SystemSettingRecord> _defaultSettings(DateTime now) => [
        SystemSettingRecord(
          id: 'SET-MFA',
          label: 'Administrator MFA required',
          category: SystemSettingCategory.security,
          value: true,
          updatedAt: now,
          updatedBy: 'SYSTEM',
          description: 'Privileged administrator access requires MFA.',
        ),
        SystemSettingRecord(
          id: 'SET-EVIDENCE-HASH',
          label: 'Evidence hash required',
          category: SystemSettingCategory.evidence,
          value: true,
          updatedAt: now,
          updatedBy: 'SYSTEM',
          description:
              'Evidence records require a cryptographic content hash before acceptance.',
        ),
        SystemSettingRecord(
          id: 'SET-OFFLINE-QUEUE',
          label: 'Offline durable queue enabled',
          category: SystemSettingCategory.sync,
          value: true,
          updatedAt: now,
          updatedBy: 'SYSTEM',
          description:
              'Operational writes remain usable locally while awaiting connectivity.',
        ),
      ];

  static Map<String, Object?> _roleAssignmentToJson(
    RoleAssignmentRecord record,
  ) =>
      {
        'id': record.id,
        'subjectId': record.subjectId,
        'subjectName': record.subjectName,
        'role': record.role.name,
        'scope': geographicScopeToJson(record.scope),
        'assignedBy': record.assignedBy,
        'assignedAt': record.assignedAt.toUtc().toIso8601String(),
        'active': record.active,
        'revokedBy': record.revokedBy,
        'revokedAt': record.revokedAt?.toUtc().toIso8601String(),
      };

  static RoleAssignmentRecord? _roleAssignmentFromJson(
    Map<String, Object?> row,
  ) {
    final id = row['id']?.toString();
    final subjectId = row['subjectId']?.toString();
    final subjectName = row['subjectName']?.toString();
    final assignedBy = row['assignedBy']?.toString();
    final assignedAt = _date(row['assignedAt']);
    final scope = geographicScopeFromJson(row['scope']);
    final roleName = row['role']?.toString();
    final role = TgcgRole.values.where((item) => item.name == roleName).firstOrNull;
    if (id == null ||
        subjectId == null ||
        subjectName == null ||
        assignedBy == null ||
        assignedAt == null ||
        scope == null ||
        role == null) {
      return null;
    }
    return RoleAssignmentRecord(
      id: id,
      subjectId: subjectId,
      subjectName: subjectName,
      role: role,
      scope: scope,
      assignedBy: assignedBy,
      assignedAt: assignedAt,
      active: row['active'] != false,
      revokedBy: row['revokedBy']?.toString(),
      revokedAt: _date(row['revokedAt']),
    );
  }

  static Map<String, Object?> _settingToJson(SystemSettingRecord setting) => {
        'id': setting.id,
        'label': setting.label,
        'category': setting.category.name,
        'value': setting.value,
        'updatedAt': setting.updatedAt.toUtc().toIso8601String(),
        'updatedBy': setting.updatedBy,
        'description': setting.description,
      };

  static SystemSettingRecord? _settingFromJson(Map<String, Object?> row) {
    final id = row['id']?.toString();
    final label = row['label']?.toString();
    final updatedAt = _date(row['updatedAt']);
    final updatedBy = row['updatedBy']?.toString();
    final categoryName = row['category']?.toString();
    final category = SystemSettingCategory.values
        .where((item) => item.name == categoryName)
        .firstOrNull;
    if (id == null ||
        label == null ||
        updatedAt == null ||
        updatedBy == null ||
        category == null) {
      return null;
    }
    return SystemSettingRecord(
      id: id,
      label: label,
      category: category,
      value: row['value'] == true,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
      description: row['description']?.toString(),
    );
  }

  static Map<String, Object?> _auditEventToJson(AuditEvent event) => {
        'id': event.id,
        'actorId': event.actorId,
        'action': event.action,
        'entityType': event.entityType,
        'entityId': event.entityId,
        'timestamp': event.timestamp.toUtc().toIso8601String(),
        'detail': event.detail,
        'deviceId': event.deviceId,
        'scope': event.scope == null ? null : geographicScopeToJson(event.scope!),
      };

  static AuditEvent? _auditEventFromJson(Map<String, Object?> row) {
    final id = row['id']?.toString();
    final actorId = row['actorId']?.toString();
    final action = row['action']?.toString();
    final entityType = row['entityType']?.toString();
    final entityId = row['entityId']?.toString();
    final timestamp = _date(row['timestamp']);
    if (id == null ||
        actorId == null ||
        action == null ||
        entityType == null ||
        entityId == null ||
        timestamp == null) {
      return null;
    }
    return AuditEvent(
      id: id,
      actorId: actorId,
      action: action,
      entityType: entityType,
      entityId: entityId,
      timestamp: timestamp,
      detail: row['detail']?.toString(),
      deviceId: row['deviceId']?.toString(),
      scope: geographicScopeFromJson(row['scope']),
    );
  }

  static DateTime? _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toUtc();

  @override
  void dispose() {
    _persistence?.removeListener(_onPersistenceChanged);
    super.dispose();
  }

  static bool _sameScope(GeographicScope a, GeographicScope b) =>
      a.level == b.level &&
      a.country == b.country &&
      a.zoneId == b.zoneId &&
      a.stateId == b.stateId &&
      a.senatorialDistrictId == b.senatorialDistrictId &&
      a.lgaId == b.lgaId &&
      a.wardId == b.wardId &&
      a.pollingUnitId == b.pollingUnitId;

  static bool _overlaps(GeographicScope a, GeographicScope b) =>
      _within(a, b) || _within(b, a);

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

class GovernanceOperations extends InheritedNotifier<GovernanceOperationsController> {
  const GovernanceOperations({
    super.key,
    required GovernanceOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static GovernanceOperationsController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<GovernanceOperations>();
      assert(value != null, 'GovernanceOperations is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<GovernanceOperations>();
    final value = element?.widget as GovernanceOperations?;
    assert(value != null, 'GovernanceOperations is missing above this context.');
    return value!.notifier!;
  }
}
