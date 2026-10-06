import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/local_id.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../governance/governance_store.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

enum EmergencyAgencyType {
  police,
  civilDefence,
  roadSafety,
  fireRescue,
  medical,
  other,
}

enum EmergencyDispatchPriority { routine, urgent, critical }

enum EmergencyDispatchStatus {
  assigned,
  acknowledged,
  responding,
  onScene,
  resolved,
  closed,
}

class EmergencyAgency {
  const EmergencyAgency({
    required this.id,
    required this.name,
    required this.shortName,
    required this.type,
    required this.coverage,
    required this.commandDesk,
    required this.contactPhone,
    this.active = true,
  });

  final String id;
  final String name;
  final String shortName;
  final EmergencyAgencyType type;
  final GeographicScope coverage;
  final String commandDesk;
  final String contactPhone;
  final bool active;
}

class EmergencyResponderProfile {
  const EmergencyResponderProfile({
    required this.id,
    required this.agencyId,
    required this.serviceNumber,
    required this.displayName,
    required this.authorizedScope,
    required this.createdAt,
    required this.createdBy,
    this.active = true,
  });

  final String id;
  final String agencyId;
  final String serviceNumber;
  final String displayName;
  final GeographicScope authorizedScope;
  final DateTime createdAt;
  final String createdBy;
  final bool active;
}

class _ResponderCredential {
  const _ResponderCredential({
    required this.salt,
    required this.hash,
  });

  final String salt;
  final String hash;
}

enum ResponderAuthenticationStatus {
  authenticated,
  rejected,
  locked,
}

class ResponderAuthenticationResult {
  const ResponderAuthenticationResult._({
    required this.status,
    this.responder,
    this.lockedUntil,
  });

  const ResponderAuthenticationResult.authenticated(
    EmergencyResponderProfile responder,
  ) : this._(
          status: ResponderAuthenticationStatus.authenticated,
          responder: responder,
        );

  const ResponderAuthenticationResult.rejected()
      : this._(status: ResponderAuthenticationStatus.rejected);

  const ResponderAuthenticationResult.locked(DateTime lockedUntil)
      : this._(
          status: ResponderAuthenticationStatus.locked,
          lockedUntil: lockedUntil,
        );

  final ResponderAuthenticationStatus status;
  final EmergencyResponderProfile? responder;
  final DateTime? lockedUntil;
}

class _ResponderLoginAttemptState {
  const _ResponderLoginAttemptState({
    required this.failedAttempts,
    required this.windowStartedAt,
    this.lockedUntil,
  });

  final int failedAttempts;
  final DateTime windowStartedAt;
  final DateTime? lockedUntil;
}

class EmergencyDispatch {
  const EmergencyDispatch({
    required this.id,
    required this.incidentId,
    required this.agencyId,
    required this.scope,
    required this.priority,
    required this.status,
    required this.assignedAt,
    required this.assignedBy,
    this.instructions,
    this.acknowledgedAt,
    this.respondingAt,
    this.onSceneAt,
    this.resolvedAt,
    this.closedAt,
    this.lastUpdatedBy,
  });

  final String id;
  final String incidentId;
  final String agencyId;
  final GeographicScope scope;
  final EmergencyDispatchPriority priority;
  final EmergencyDispatchStatus status;
  final DateTime assignedAt;
  final String assignedBy;
  final String? instructions;
  final DateTime? acknowledgedAt;
  final DateTime? respondingAt;
  final DateTime? onSceneAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final String? lastUpdatedBy;
}

class EmergencyResponseController extends ChangeNotifier {
  EmergencyResponseController._({
    required GovernanceOperationsController governance,
    required List<EmergencyAgency> agencies,
    required List<EmergencyDispatch> dispatches,
    List<EmergencyResponderProfile> responders = const [],
    OfflinePersistenceController? persistence,
  })  : _governance = governance,
        _agencies = agencies,
        _dispatches = dispatches,
        _responders = List<EmergencyResponderProfile>.of(responders),
        _persistence = persistence;

  factory EmergencyResponseController.productionFoundation({
    required GovernanceOperationsController governance,
    required OfflinePersistenceController persistence,
  }) =>
      EmergencyResponseController._(
        governance: governance,
        agencies: <EmergencyAgency>[],
        dispatches: <EmergencyDispatch>[],
        responders: <EmergencyResponderProfile>[],
        persistence: persistence,
      );

  factory EmergencyResponseController.prototypeSeed(
    GovernanceOperationsController governance,
  ) {
    final now = DateTime.utc(2026, 9, 28, 2, 0);
    const kaduna = GeographicScope.kaduna;
    return EmergencyResponseController._(
      governance: governance,
      agencies: const [
        EmergencyAgency(
          id: 'AGENCY-POLICE',
          name: 'Police Response Desk',
          shortName: 'Police',
          type: EmergencyAgencyType.police,
          coverage: kaduna,
          commandDesk: 'State Operations Desk',
          contactPhone: '+234 000 000 0101',
        ),
        EmergencyAgency(
          id: 'AGENCY-NSCDC',
          name: 'Civil Defence Response Desk',
          shortName: 'Civil Defence',
          type: EmergencyAgencyType.civilDefence,
          coverage: kaduna,
          commandDesk: 'State Operations Desk',
          contactPhone: '+234 000 000 0102',
        ),
        EmergencyAgency(
          id: 'AGENCY-FRSC',
          name: 'Road Safety Response Desk',
          shortName: 'Road Safety',
          type: EmergencyAgencyType.roadSafety,
          coverage: kaduna,
          commandDesk: 'State Operations Desk',
          contactPhone: '+234 000 000 0103',
        ),
        EmergencyAgency(
          id: 'AGENCY-FIRE',
          name: 'Fire & Rescue Desk',
          shortName: 'Fire & Rescue',
          type: EmergencyAgencyType.fireRescue,
          coverage: kaduna,
          commandDesk: 'Emergency Coordination Desk',
          contactPhone: '+234 000 000 0104',
        ),
        EmergencyAgency(
          id: 'AGENCY-MEDICAL',
          name: 'Medical Emergency Desk',
          shortName: 'Medical',
          type: EmergencyAgencyType.medical,
          coverage: kaduna,
          commandDesk: 'Emergency Coordination Desk',
          contactPhone: '+234 000 000 0105',
        ),
      ],
      dispatches: [
        EmergencyDispatch(
          id: 'DSP-0001',
          incidentId: 'INC-0001',
          agencyId: 'AGENCY-POLICE',
          scope: GeographicScope(
            level: GeographyLevel.lga,
            country: 'Nigeria',
            zoneId: 'NW',
            zoneName: 'North West',
            stateId: 'KD',
            stateName: 'Kaduna',
            senatorialDistrictId: 'SD/053/KD',
            senatorialDistrictName: 'Kaduna Central',
            lgaId: 'KD-KADUNA-NORTH',
            lgaName: 'Kaduna North',
          ),
          priority: EmergencyDispatchPriority.urgent,
          status: EmergencyDispatchStatus.acknowledged,
          assignedAt: now.subtract(const Duration(minutes: 14)),
          acknowledgedAt: now.subtract(const Duration(minutes: 10)),
          assignedBy: 'SITUATION-ROOM',
          lastUpdatedBy: 'POLICE-DESK',
          instructions: 'Confirm access conditions and update the Situation Room.',
        ),
        EmergencyDispatch(
          id: 'DSP-0002',
          incidentId: 'INC-0005',
          agencyId: 'AGENCY-POLICE',
          scope: GeographicScope(
            level: GeographyLevel.lga,
            country: 'Nigeria',
            zoneId: 'NW',
            zoneName: 'North West',
            stateId: 'KD',
            stateName: 'Kaduna',
            senatorialDistrictId: 'SD/054/KD',
            senatorialDistrictName: 'Kaduna South',
            lgaId: 'KD-JEMAA',
            lgaName: "Jema'a",
          ),
          priority: EmergencyDispatchPriority.critical,
          status: EmergencyDispatchStatus.assigned,
          assignedAt: now.subtract(const Duration(minutes: 6)),
          assignedBy: 'SITUATION-ROOM',
          lastUpdatedBy: 'SITUATION-ROOM',
          instructions: 'Secure the collation centre gate and keep the access route open for officials.',
        ),
        EmergencyDispatch(
          id: 'DSP-0003',
          incidentId: 'INC-0005',
          agencyId: 'AGENCY-NSCDC',
          scope: GeographicScope(
            level: GeographyLevel.lga,
            country: 'Nigeria',
            zoneId: 'NW',
            zoneName: 'North West',
            stateId: 'KD',
            stateName: 'Kaduna',
            senatorialDistrictId: 'SD/054/KD',
            senatorialDistrictName: 'Kaduna South',
            lgaId: 'KD-JEMAA',
            lgaName: "Jema'a",
          ),
          priority: EmergencyDispatchPriority.urgent,
          status: EmergencyDispatchStatus.assigned,
          assignedAt: now.subtract(const Duration(minutes: 5)),
          assignedBy: 'SITUATION-ROOM',
          lastUpdatedBy: 'SITUATION-ROOM',
          instructions: 'Support crowd control and protect election materials on site.',
        ),
      ],
    );
  }

  final GovernanceOperationsController _governance;
  final List<EmergencyAgency> _agencies;
  final List<EmergencyDispatch> _dispatches;
  final List<EmergencyResponderProfile> _responders;
  final OfflinePersistenceController? _persistence;
  final FlutterSecureStorage _credentialStorage =
      const FlutterSecureStorage();

  List<EmergencyAgency> get agencies => List.unmodifiable(_agencies);
  List<EmergencyDispatch> get dispatches => List.unmodifiable(_dispatches);
  List<EmergencyResponderProfile> get responders =>
      List.unmodifiable(_responders);

  Future<void> hydrateFromOffline() async {
    final persistence = _persistence;
    if (persistence == null) return;

    final agencyRows =
        await persistence.readEntities(entityType: 'emergency_agency');
    final dispatchRows =
        await persistence.readEntities(entityType: 'emergency_dispatch');
    final responderRows =
        await persistence.readEntities(entityType: 'emergency_responder');
    var changed = false;

    for (final row in agencyRows) {
      final agency = _agencyFromJson(row);
      if (agency == null) continue;
      final index = _agencies.indexWhere((item) => item.id == agency.id);
      if (index < 0) {
        _agencies.add(agency);
      } else {
        _agencies[index] = agency;
      }
      changed = true;
    }

    for (final row in dispatchRows) {
      final dispatch = _dispatchFromJson(row);
      if (dispatch == null ||
          !_agencies.any((agency) => agency.id == dispatch.agencyId)) {
        continue;
      }
      final index = _dispatches.indexWhere((item) => item.id == dispatch.id);
      if (index < 0) {
        _dispatches.add(dispatch);
      } else {
        _dispatches[index] = dispatch;
      }
      changed = true;
    }

    for (final row in responderRows) {
      final responder = _responderFromJson(row);
      if (responder == null ||
          !_agencies.any((agency) => agency.id == responder.agencyId)) {
        continue;
      }
      final index =
          _responders.indexWhere((item) => item.id == responder.id);
      if (index < 0) {
        _responders.add(responder);
      } else {
        _responders[index] = responder;
      }
      changed = true;
    }

    if (changed) {
      _agencies.sort((a, b) => a.shortName.compareTo(b.shortName));
      _dispatches.sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
      _responders.sort((a, b) => a.displayName.compareTo(b.displayName));
      notifyListeners();
    }
  }

  Future<EmergencyAgency> upsertAgency({
    required String id,
    required String name,
    required String shortName,
    required EmergencyAgencyType type,
    required GeographicScope coverage,
    required String commandDesk,
    required String contactPhone,
    required String actorId,
    required TgcgRole actorRole,
    required GeographicScope authorizedScope,
    bool active = true,
  }) async {
    if (!TgcgPermissionPolicy.may(
      actorRole,
      authorizedScope,
      TgcgCapability.manageSystemSettings,
      targetScope: coverage,
    )) {
      throw StateError(
        'This account cannot configure emergency agencies in the selected scope.',
      );
    }
    final agency = EmergencyAgency(
      id: id.trim(),
      name: name.trim(),
      shortName: shortName.trim(),
      type: type,
      coverage: coverage,
      commandDesk: commandDesk.trim(),
      contactPhone: contactPhone.trim(),
      active: active,
    );
    if (agency.id.isEmpty ||
        agency.name.isEmpty ||
        agency.shortName.isEmpty ||
        agency.commandDesk.isEmpty ||
        agency.contactPhone.isEmpty) {
      throw ArgumentError('Emergency agency details are incomplete.');
    }

    await _persistence?.persistMutation(
      entityType: 'emergency_agency',
      entityId: agency.id,
      mutationType: SyncMutationType.upsert,
      payload: _agencyToJson(agency),
      scopeKey: scopeStorageKey(coverage),
      ownerId: actorId,
    );

    final index = _agencies.indexWhere((item) => item.id == agency.id);
    if (index < 0) {
      _agencies.add(agency);
    } else {
      _agencies[index] = agency;
    }
    _agencies.sort((a, b) => a.shortName.compareTo(b.shortName));
    _governance.recordAudit(
      actorId: actorId,
      action: 'emergency_agency_configured',
      entityType: 'emergency_agency',
      entityId: agency.id,
      detail: '${agency.shortName} response agency configuration updated.',
      scope: coverage,
    );
    notifyListeners();
    return agency;
  }

  Future<EmergencyResponderProfile> provisionResponder({
    required String agencyId,
    required String serviceNumber,
    required String displayName,
    required String accessCode,
    required GeographicScope responderScope,
    required String actorId,
    required TgcgRole actorRole,
    required GeographicScope authorizedScope,
    bool active = true,
  }) async {
    final agency = agencyById(agencyId);
    if (agency == null || !agency.active) {
      throw StateError('Configure an active response agency first.');
    }
    if (!TgcgPermissionPolicy.may(
      actorRole,
      authorizedScope,
      TgcgCapability.manageSystemSettings,
      targetScope: responderScope,
    )) {
      throw StateError(
        'This account cannot provision security responders in the selected scope.',
      );
    }
    if (!_within(agency.coverage, responderScope)) {
      throw StateError(
        'Responder scope must be inside the configured agency coverage.',
      );
    }

    final normalizedService = _normalizeServiceNumber(serviceNumber);
    final normalizedName = displayName.trim();
    if (normalizedService.length < 4) {
      throw ArgumentError('Enter a valid service or force number.');
    }
    if (normalizedName.length < 3) {
      throw ArgumentError('Enter the responder name and rank.');
    }
    if (accessCode.length < 8) {
      throw ArgumentError('Responder access code must contain at least 8 characters.');
    }

    final now = DateTime.now().toUtc();
    final existingIndex = _responders.indexWhere(
      (item) =>
          item.agencyId == agencyId &&
          _normalizeServiceNumber(item.serviceNumber) == normalizedService,
    );
    final previous = existingIndex < 0 ? null : _responders[existingIndex];
    final responder = EmergencyResponderProfile(
      id: previous?.id ?? newLocalId('RESP', now),
      agencyId: agencyId,
      serviceNumber: normalizedService,
      displayName: normalizedName,
      authorizedScope: responderScope,
      createdAt: previous?.createdAt ?? now,
      createdBy: previous?.createdBy ?? actorId,
      active: active,
    );

    final credential = await _newResponderCredential(accessCode);
    final credentialKey = _responderCredentialKey(responder.id);
    final previousCredential = await _credentialStorage.read(key: credentialKey);
    await _credentialStorage.write(
      key: credentialKey,
      value: jsonEncode({
        'salt': credential.salt,
        'hash': credential.hash,
      }),
    );

    try {
      await _persistence?.persistMutation(
        entityType: 'emergency_responder',
        entityId: responder.id,
        mutationType: SyncMutationType.upsert,
        payload: _responderToJson(responder),
        scopeKey: scopeStorageKey(responderScope),
        ownerId: normalizedService,
      );
    } catch (_) {
      if (previousCredential == null) {
        await _credentialStorage.delete(key: credentialKey);
      } else {
        await _credentialStorage.write(
          key: credentialKey,
          value: previousCredential,
        );
      }
      rethrow;
    }

    if (existingIndex < 0) {
      _responders.add(responder);
    } else {
      _responders[existingIndex] = responder;
    }
    _responders.sort((a, b) => a.displayName.compareTo(b.displayName));
    _governance.recordAudit(
      actorId: actorId,
      action: 'emergency_responder_provisioned',
      entityType: 'emergency_responder',
      entityId: responder.id,
      detail:
          '${responder.displayName} provisioned for ${agency.shortName} within ${responderScope.label}.',
      scope: responderScope,
    );
    notifyListeners();
    return responder;
  }

  Future<ResponderAuthenticationResult> authenticateResponderCredential({
    required String agencyId,
    required String serviceNumber,
    required String accessCode,
    required GeographicScope requestedScope,
  }) async {
    final normalizedService = _normalizeServiceNumber(serviceNumber);
    final attemptKey =
        _responderAttemptKey(agencyId, normalizedService);
    final now = DateTime.now().toUtc();
    final attemptState = await _readAttemptState(attemptKey);

    if (attemptState?.lockedUntil != null &&
        now.isBefore(attemptState!.lockedUntil!)) {
      return ResponderAuthenticationResult.locked(
        attemptState.lockedUntil!,
      );
    }
    if (attemptState?.lockedUntil != null &&
        !now.isBefore(attemptState!.lockedUntil!)) {
      await _credentialStorage.delete(key: attemptKey);
    }

    final agency = agencyById(agencyId);
    EmergencyResponderProfile? responder;
    if (agency != null && agency.active) {
      for (final item in _responders) {
        if (item.active &&
            item.agencyId == agencyId &&
            _normalizeServiceNumber(item.serviceNumber) == normalizedService) {
          responder = item;
          break;
        }
      }
    }

    final credentialValid = responder == null
        ? await _runDummyCredentialCheck(accessCode)
        : await _verifyStoredResponderCredential(
            responder.id,
            accessCode,
          );

    if (!credentialValid) {
      final lockedUntil = await _registerFailedAttempt(
        attemptKey: attemptKey,
        previous: attemptState,
        now: now,
      );
      return lockedUntil == null
          ? const ResponderAuthenticationResult.rejected()
          : ResponderAuthenticationResult.locked(lockedUntil);
    }

    await _credentialStorage.delete(key: attemptKey);

    if (agency == null ||
        !agency.active ||
        responder == null ||
        !_within(agency.coverage, requestedScope) ||
        !_within(responder.authorizedScope, requestedScope)) {
      return const ResponderAuthenticationResult.rejected();
    }

    return ResponderAuthenticationResult.authenticated(responder);
  }

  Future<EmergencyResponderProfile?> verifyResponderCredential({
    required String agencyId,
    required String serviceNumber,
    required String accessCode,
    required GeographicScope requestedScope,
  }) async {
    final result = await authenticateResponderCredential(
      agencyId: agencyId,
      serviceNumber: serviceNumber,
      accessCode: accessCode,
      requestedScope: requestedScope,
    );
    return result.status == ResponderAuthenticationStatus.authenticated
        ? result.responder
        : null;
  }

  Future<void> clearLocalCredentials() async {
    for (final responder in _responders) {
      await _credentialStorage.delete(
        key: _responderCredentialKey(responder.id),
      );
      await _credentialStorage.delete(
        key: _responderAttemptKey(
          responder.agencyId,
          _normalizeServiceNumber(responder.serviceNumber),
        ),
      );
    }
  }

  List<EmergencyAgency> agenciesForScope(GeographicScope scope) => _agencies
      .where((agency) => agency.active && _overlaps(agency.coverage, scope))
      .toList(growable: false);

  List<EmergencyDispatch> dispatchesForScope(GeographicScope scope) =>
      _dispatches.where((item) => _overlaps(scope, item.scope)).toList(growable: false)
        ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

  List<EmergencyDispatch> dispatchesForAgency({
    required GeographicScope scope,
    required String agencyId,
  }) =>
      _dispatches
          .where(
            (item) =>
                item.agencyId == agencyId && _overlaps(scope, item.scope),
          )
          .toList(growable: false)
        ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

  bool agencyCanAccessDispatch({
    required String agencyId,
    required EmergencyDispatch dispatch,
  }) =>
      dispatch.agencyId == agencyId;

  List<EmergencyDispatch> dispatchesForIncident(String incidentId) => _dispatches
      .where((item) => item.incidentId == incidentId)
      .toList(growable: false)
    ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

  EmergencyAgency? agencyById(String id) {
    for (final agency in _agencies) {
      if (agency.id == id) return agency;
    }
    return null;
  }

  int get activeDispatchCount => _dispatches
      .where((item) =>
          item.status != EmergencyDispatchStatus.resolved &&
          item.status != EmergencyDispatchStatus.closed)
      .length;

  int get awaitingAcknowledgementCount => _dispatches
      .where((item) => item.status == EmergencyDispatchStatus.assigned)
      .length;

  Future<EmergencyDispatch> assign({
    required String incidentId,
    required String agencyId,
    required GeographicScope scope,
    required EmergencyDispatchPriority priority,
    required String actorId,
    String? instructions,
  }) async {
    final agency = agencyById(agencyId);
    if (agency == null || !agency.active) {
      throw ArgumentError('Selected response agency is unavailable.');
    }
    if (!_overlaps(agency.coverage, scope)) {
      throw ArgumentError('Selected agency does not cover this incident scope.');
    }

    final assignedAt = DateTime.now().toUtc();
    final dispatch = EmergencyDispatch(
      id: newLocalId('DSP', assignedAt),
      incidentId: incidentId,
      agencyId: agencyId,
      scope: scope,
      priority: priority,
      status: EmergencyDispatchStatus.assigned,
      assignedAt: assignedAt,
      assignedBy: actorId,
      instructions: instructions?.trim().isEmpty == true ? null : instructions?.trim(),
      lastUpdatedBy: actorId,
    );
    await _persistence?.persistMutation(
      entityType: 'emergency_dispatch',
      entityId: dispatch.id,
      mutationType: SyncMutationType.create,
      payload: _dispatchToJson(dispatch),
      scopeKey: scopeStorageKey(scope),
      ownerId: actorId,
    );
    _dispatches.insert(0, dispatch);
    _governance.recordAudit(
      actorId: actorId,
      action: 'emergency_dispatch_assigned',
      entityType: 'emergency_dispatch',
      entityId: dispatch.id,
      detail: '${agency.shortName} assigned to $incidentId with ${priority.name} priority.',
      scope: scope,
    );
    notifyListeners();
    return dispatch;
  }

  void recordDispatchAudit({
    required String dispatchId,
    required String actorId,
    required String action,
    required String detail,
    String? actingAgencyId,
  }) {
    final index = _dispatches.indexWhere((item) => item.id == dispatchId);
    if (index < 0) return;
    final dispatch = _dispatches[index];
    if (actingAgencyId != null && dispatch.agencyId != actingAgencyId) {
      throw StateError(
        'This dispatch is assigned to a different response agency.',
      );
    }
    _governance.recordAudit(
      actorId: actorId,
      action: action,
      entityType: 'emergency_dispatch',
      entityId: dispatch.id,
      detail: detail,
      scope: dispatch.scope,
    );
  }

  Future<void> updateStatus({
    required String dispatchId,
    required EmergencyDispatchStatus status,
    required String actorId,
    String? actingAgencyId,
  }) async {
    final index = _dispatches.indexWhere((item) => item.id == dispatchId);
    if (index < 0) return;
    final current = _dispatches[index];
    if (actingAgencyId != null && current.agencyId != actingAgencyId) {
      throw StateError(
        'This dispatch is assigned to a different response agency.',
      );
    }
    if (!_isValidTransition(current.status, status)) {
      throw StateError(
        'Invalid response transition from ${current.status.name} to ${status.name}.',
      );
    }
    final now = DateTime.now().toUtc();
    final updated = EmergencyDispatch(
      id: current.id,
      incidentId: current.incidentId,
      agencyId: current.agencyId,
      scope: current.scope,
      priority: current.priority,
      status: status,
      assignedAt: current.assignedAt,
      assignedBy: current.assignedBy,
      instructions: current.instructions,
      acknowledgedAt: status == EmergencyDispatchStatus.acknowledged && current.acknowledgedAt == null
          ? now
          : current.acknowledgedAt,
      respondingAt: status == EmergencyDispatchStatus.responding && current.respondingAt == null
          ? now
          : current.respondingAt,
      onSceneAt: status == EmergencyDispatchStatus.onScene && current.onSceneAt == null
          ? now
          : current.onSceneAt,
      resolvedAt: status == EmergencyDispatchStatus.resolved && current.resolvedAt == null
          ? now
          : current.resolvedAt,
      closedAt: status == EmergencyDispatchStatus.closed && current.closedAt == null
          ? now
          : current.closedAt,
      lastUpdatedBy: actorId,
    );
    await _persistence?.persistMutation(
      entityType: 'emergency_dispatch',
      entityId: updated.id,
      mutationType: SyncMutationType.update,
      payload: _dispatchToJson(updated),
      scopeKey: scopeStorageKey(updated.scope),
      ownerId: actorId,
    );
    _dispatches[index] = updated;
    _governance.recordAudit(
      actorId: actorId,
      action: 'emergency_dispatch_${status.name}',
      entityType: 'emergency_dispatch',
      entityId: current.id,
      detail: 'Response status changed to ${status.name}.',
      scope: current.scope,
    );
    notifyListeners();
  }

  static Map<String, Object?> _responderToJson(
    EmergencyResponderProfile responder,
  ) =>
      {
        'id': responder.id,
        'agencyId': responder.agencyId,
        'serviceNumber': responder.serviceNumber,
        'displayName': responder.displayName,
        'authorizedScope': geographicScopeToJson(responder.authorizedScope),
        'createdAt': responder.createdAt.toUtc().toIso8601String(),
        'createdBy': responder.createdBy,
        'active': responder.active,
      };

  static EmergencyResponderProfile? _responderFromJson(
    Map<String, Object?> row,
  ) {
    final id = row['id']?.toString();
    final agencyId = row['agencyId']?.toString();
    final serviceNumber = row['serviceNumber']?.toString();
    final displayName = row['displayName']?.toString();
    final authorizedScope = geographicScopeFromJson(row['authorizedScope']);
    final createdAt =
        DateTime.tryParse(row['createdAt']?.toString() ?? '')?.toUtc();
    final createdBy = row['createdBy']?.toString();
    if (id == null ||
        agencyId == null ||
        serviceNumber == null ||
        displayName == null ||
        authorizedScope == null ||
        createdAt == null ||
        createdBy == null) {
      return null;
    }
    return EmergencyResponderProfile(
      id: id,
      agencyId: agencyId,
      serviceNumber: serviceNumber,
      displayName: displayName,
      authorizedScope: authorizedScope,
      createdAt: createdAt,
      createdBy: createdBy,
      active: row['active'] != false,
    );
  }

  static Map<String, Object?> _agencyToJson(EmergencyAgency agency) => {
        'id': agency.id,
        'name': agency.name,
        'shortName': agency.shortName,
        'type': agency.type.name,
        'coverage': geographicScopeToJson(agency.coverage),
        'commandDesk': agency.commandDesk,
        'contactPhone': agency.contactPhone,
        'active': agency.active,
      };

  static EmergencyAgency? _agencyFromJson(Map<String, Object?> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString();
    final shortName = row['shortName']?.toString();
    final type = _enumValue(EmergencyAgencyType.values, row['type']);
    final coverage = geographicScopeFromJson(row['coverage']);
    final commandDesk = row['commandDesk']?.toString();
    final contactPhone = row['contactPhone']?.toString();
    if (id == null ||
        name == null ||
        shortName == null ||
        type == null ||
        coverage == null ||
        commandDesk == null ||
        contactPhone == null) {
      return null;
    }
    return EmergencyAgency(
      id: id,
      name: name,
      shortName: shortName,
      type: type,
      coverage: coverage,
      commandDesk: commandDesk,
      contactPhone: contactPhone,
      active: row['active'] != false,
    );
  }

  static Map<String, Object?> _dispatchToJson(
    EmergencyDispatch dispatch,
  ) =>
      {
        'id': dispatch.id,
        'incidentId': dispatch.incidentId,
        'agencyId': dispatch.agencyId,
        'scope': geographicScopeToJson(dispatch.scope),
        'priority': dispatch.priority.name,
        'status': dispatch.status.name,
        'assignedAt': dispatch.assignedAt.toUtc().toIso8601String(),
        'assignedBy': dispatch.assignedBy,
        'instructions': dispatch.instructions,
        'acknowledgedAt':
            dispatch.acknowledgedAt?.toUtc().toIso8601String(),
        'respondingAt': dispatch.respondingAt?.toUtc().toIso8601String(),
        'onSceneAt': dispatch.onSceneAt?.toUtc().toIso8601String(),
        'resolvedAt': dispatch.resolvedAt?.toUtc().toIso8601String(),
        'closedAt': dispatch.closedAt?.toUtc().toIso8601String(),
        'lastUpdatedBy': dispatch.lastUpdatedBy,
      };

  static EmergencyDispatch? _dispatchFromJson(Map<String, Object?> row) {
    final id = row['id']?.toString();
    final incidentId = row['incidentId']?.toString();
    final agencyId = row['agencyId']?.toString();
    final scope = geographicScopeFromJson(row['scope']);
    final priority =
        _enumValue(EmergencyDispatchPriority.values, row['priority']);
    final status = _enumValue(EmergencyDispatchStatus.values, row['status']);
    final assignedAt =
        DateTime.tryParse(row['assignedAt']?.toString() ?? '')?.toUtc();
    final assignedBy = row['assignedBy']?.toString();
    if (id == null ||
        incidentId == null ||
        agencyId == null ||
        scope == null ||
        priority == null ||
        status == null ||
        assignedAt == null ||
        assignedBy == null) {
      return null;
    }
    return EmergencyDispatch(
      id: id,
      incidentId: incidentId,
      agencyId: agencyId,
      scope: scope,
      priority: priority,
      status: status,
      assignedAt: assignedAt,
      assignedBy: assignedBy,
      instructions: _clean(row['instructions']),
      acknowledgedAt: _date(row['acknowledgedAt']),
      respondingAt: _date(row['respondingAt']),
      onSceneAt: _date(row['onSceneAt']),
      resolvedAt: _date(row['resolvedAt']),
      closedAt: _date(row['closedAt']),
      lastUpdatedBy: _clean(row['lastUpdatedBy']),
    );
  }

  Future<_ResponderLoginAttemptState?> _readAttemptState(
    String attemptKey,
  ) async {
    final raw = await _credentialStorage.read(key: attemptKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final failedAttempts =
          int.tryParse(decoded['failedAttempts']?.toString() ?? '');
      final windowStartedAt = DateTime.tryParse(
        decoded['windowStartedAt']?.toString() ?? '',
      )?.toUtc();
      final lockedRaw = decoded['lockedUntil']?.toString();
      final lockedUntil = lockedRaw == null || lockedRaw.isEmpty
          ? null
          : DateTime.tryParse(lockedRaw)?.toUtc();
      if (failedAttempts == null || windowStartedAt == null) return null;
      return _ResponderLoginAttemptState(
        failedAttempts: failedAttempts,
        windowStartedAt: windowStartedAt,
        lockedUntil: lockedUntil,
      );
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> _registerFailedAttempt({
    required String attemptKey,
    required _ResponderLoginAttemptState? previous,
    required DateTime now,
  }) async {
    final withinWindow = previous != null &&
        now.difference(previous.windowStartedAt) <
            _responderFailureWindow;
    final failedAttempts = withinWindow
        ? previous.failedAttempts + 1
        : 1;
    final windowStartedAt =
        withinWindow ? previous.windowStartedAt : now;
    final lockedUntil = failedAttempts >= _responderMaxFailures
        ? now.add(_responderLockoutDuration)
        : null;
    await _credentialStorage.write(
      key: attemptKey,
      value: jsonEncode({
        'failedAttempts': failedAttempts,
        'windowStartedAt': windowStartedAt.toIso8601String(),
        'lockedUntil': lockedUntil?.toIso8601String(),
      }),
    );
    return lockedUntil;
  }

  Future<bool> _verifyStoredResponderCredential(
    String responderId,
    String accessCode,
  ) async {
    final stored = await _credentialStorage.read(
      key: _responderCredentialKey(responderId),
    );
    if (stored == null || stored.isEmpty) {
      await _runDummyCredentialCheck(accessCode);
      return false;
    }
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map ||
          decoded['salt'] is! String ||
          decoded['hash'] is! String) {
        await _runDummyCredentialCheck(accessCode);
        return false;
      }
      final credential = _ResponderCredential(
        salt: decoded['salt'] as String,
        hash: decoded['hash'] as String,
      );
      final actual = base64UrlEncode(
        await _deriveAccessCode(
          accessCode,
          base64Url.decode(credential.salt),
        ),
      );
      return _constantTimeEquals(credential.hash, actual);
    } catch (_) {
      await _runDummyCredentialCheck(accessCode);
      return false;
    }
  }

  static Future<bool> _runDummyCredentialCheck(String accessCode) async {
    await _deriveAccessCode(
      accessCode,
      _dummyResponderSalt,
    );
    return false;
  }

  static Future<_ResponderCredential> _newResponderCredential(
    String accessCode,
  ) async {
    final random = Random.secure();
    final salt = List<int>.generate(
      16,
      (_) => random.nextInt(256),
      growable: false,
    );
    final hash = await _deriveAccessCode(accessCode, salt);
    return _ResponderCredential(
      salt: base64UrlEncode(salt),
      hash: base64UrlEncode(hash),
    );
  }

  static Future<List<int>> _deriveAccessCode(
    String accessCode,
    List<int> salt,
  ) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    final secret = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(accessCode)),
      nonce: salt,
    );
    return secret.extractBytes();
  }

  static String _normalizeServiceNumber(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  static const int _responderMaxFailures = 5;
  static const Duration _responderFailureWindow = Duration(minutes: 15);
  static const Duration _responderLockoutDuration = Duration(minutes: 15);
  static const List<int> _dummyResponderSalt = <int>[
    0x55,
    0x53,
    0x45,
    0x53,
    0x46,
    0x2d,
    0x53,
    0x45,
    0x43,
    0x55,
    0x52,
    0x49,
    0x54,
    0x59,
    0x2d,
    0x31,
  ];

  static String _responderCredentialKey(String responderId) =>
      'usesf.security.responder.$responderId.access_code';

  static String _responderAttemptKey(
    String agencyId,
    String normalizedServiceNumber,
  ) {
    final identity = base64UrlEncode(
      utf8.encode('$agencyId|$normalizedServiceNumber'),
    ).replaceAll('=', '');
    return 'usesf.security.responder.$identity.attempts';
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var index = 0; index < a.length; index++) {
      difference |= a.codeUnitAt(index) ^ b.codeUnitAt(index);
    }
    return difference == 0;
  }

  static T? _enumValue<T extends Enum>(List<T> values, Object? raw) {
    final name = raw?.toString();
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static DateTime? _date(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toUtc();
  }

  static String? _clean(Object? raw) {
    final value = raw?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static bool _isValidTransition(
    EmergencyDispatchStatus current,
    EmergencyDispatchStatus next,
  ) =>
      switch (current) {
        EmergencyDispatchStatus.assigned =>
          next == EmergencyDispatchStatus.acknowledged,
        EmergencyDispatchStatus.acknowledged =>
          next == EmergencyDispatchStatus.responding,
        EmergencyDispatchStatus.responding =>
          next == EmergencyDispatchStatus.onScene,
        EmergencyDispatchStatus.onScene =>
          next == EmergencyDispatchStatus.resolved,
        EmergencyDispatchStatus.resolved =>
          next == EmergencyDispatchStatus.closed,
        EmergencyDispatchStatus.closed => false,
      };

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

class EmergencyResponse extends InheritedNotifier<EmergencyResponseController> {
  const EmergencyResponse({
    super.key,
    required EmergencyResponseController controller,
    required super.child,
  }) : super(notifier: controller);

  static EmergencyResponseController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<EmergencyResponse>();
      assert(value != null, 'EmergencyResponse is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<EmergencyResponse>();
    final value = element?.widget as EmergencyResponse?;
    assert(value != null, 'EmergencyResponse is missing above this context.');
    return value!.notifier!;
  }
}
