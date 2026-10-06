import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'domain/models.dart';
import 'domain/permissions.dart';
import 'offline/offline_payloads.dart';

export 'domain/models.dart';

enum TgcgModule {
  overview,
  memberEnrollment,
  membershipNetwork,
  roleAssignment,
  geography,
  assignmentControl,
  liveOperations,
  aiVerification,
  aiAnalytics,
  alertCenter,
  fieldMonitoring,
  evidenceCapture,
  situationRoom,
  securityResponse,
  resultCapture,
  collation,
  mediaIntelligence,
  communications,
  bulkCommunications,
  discussionRoom,
  meetingRoom,
  systemMonitoring,
  reports,
  governance,
}

enum SessionTerminationReason {
  explicitSignOut,
  centrallyRevoked,
  centralValidationFailed,
  accountUnavailable,
}

class TgcgSessionController extends ChangeNotifier {
  TgcgSessionController({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _persistedSessionKey = 'usesf.session.v2';

  final FlutterSecureStorage _secureStorage;

  TgcgRole? _role;
  String _operatorName = '';
  String _accessId = '';
  String? _agencyId;
  GeographicScope _scope = GeographicScope.kaduna;
  String? _securitySessionToken;
  SessionTerminationReason? _lastTerminationReason;

  Future<void> Function(String sessionToken)? onSecuritySessionSignOut;

  TgcgRole? get role => _role;
  String get operatorName => _operatorName;
  String get accessId => _accessId;

  /// Response agency for a Security Officer session; null for other roles.
  String? get agencyId => _agencyId;
  GeographicScope get scope => _scope;
  bool get isAuthenticated => _role != null;
  bool get isSecuritySession => _role == TgcgRole.securityOfficer;
  String? get securitySessionToken => _securitySessionToken;
  SessionTerminationReason? get lastTerminationReason =>
      _lastTerminationReason;

  Future<void> restorePersistedSession() async {
    final raw = await _secureStorage.read(key: _persistedSessionKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await clearPersistedSession();
        return;
      }
      final roleName = decoded['role']?.toString();
      final role = _enumByName(TgcgRole.values, roleName);
      final operatorName = decoded['operatorName']?.toString() ?? '';
      final accessId = decoded['accessId']?.toString() ?? '';
      final agencyId = _clean(decoded['agencyId']);
      final scope = geographicScopeFromJson(decoded['scope']);
      final securitySessionToken = _clean(decoded['securitySessionToken']);

      if (role == null ||
          accessId.trim().isEmpty ||
          scope == null ||
          (role == TgcgRole.securityOfficer &&
              (agencyId == null || agencyId.isEmpty))) {
        await clearPersistedSession();
        return;
      }

      _role = role;
      _operatorName =
          operatorName.trim().isEmpty ? roleLabel(role) : operatorName.trim();
      _accessId = accessId.trim();
      _agencyId = role == TgcgRole.securityOfficer ? agencyId : null;
      _scope = scope;
      _securitySessionToken =
          role == TgcgRole.securityOfficer ? securitySessionToken : null;
      _lastTerminationReason = null;
      notifyListeners();
    } catch (_) {
      await clearPersistedSession();
    }
  }

  Future<void> signIn({
    required TgcgRole role,
    required String operatorName,
    required String accessId,
    GeographicScope scope = GeographicScope.kaduna,
    String? agencyId,
    String? securitySessionToken,
  }) {
    if (role == TgcgRole.securityOfficer &&
        (agencyId == null || agencyId.trim().isEmpty)) {
      throw ArgumentError(
        'Security Officer access requires an authorized response agency.',
      );
    }
    if (accessId.trim().isEmpty) {
      throw ArgumentError('Authenticated access requires an account ID.');
    }

    _role = role;
    _agencyId =
        role == TgcgRole.securityOfficer ? agencyId?.trim() : null;
    _operatorName =
        operatorName.trim().isEmpty ? roleLabel(role) : operatorName.trim();
    _accessId = accessId.trim();
    _scope = scope;
    _securitySessionToken =
        role == TgcgRole.securityOfficer ? securitySessionToken : null;
    _lastTerminationReason = null;
    notifyListeners();
    return _persistSession();
  }

  void updateScope(GeographicScope scope) {
    final unchanged = _scope.level == scope.level &&
        _scope.country == scope.country &&
        _scope.zoneId == scope.zoneId &&
        _scope.stateId == scope.stateId &&
        _scope.senatorialDistrictId == scope.senatorialDistrictId &&
        _scope.lgaId == scope.lgaId &&
        _scope.wardId == scope.wardId &&
        _scope.pollingUnitId == scope.pollingUnitId;
    if (unchanged) return;
    _scope = scope;
    notifyListeners();
    unawaited(_persistSession());
  }

  Future<void> signOut({
    SessionTerminationReason reason = SessionTerminationReason.explicitSignOut,
  }) async {
    final securityToken = _securitySessionToken;
    _clearInMemory(reason);
    await clearPersistedSession();

    if (reason == SessionTerminationReason.explicitSignOut &&
        securityToken != null &&
        securityToken.isNotEmpty) {
      try {
        await onSecuritySessionSignOut?.call(securityToken);
      } catch (_) {
        // Local sign-out remains authoritative for this device even when
        // central session revocation cannot be delivered immediately.
      }
    }
  }

  Future<void> clearPersistedSession() =>
      _secureStorage.delete(key: _persistedSessionKey);

  Future<void> _persistSession() async {
    final role = _role;
    if (role == null) {
      await clearPersistedSession();
      return;
    }
    await _secureStorage.write(
      key: _persistedSessionKey,
      value: jsonEncode({
        'version': 2,
        'role': role.name,
        'operatorName': _operatorName,
        'accessId': _accessId,
        'agencyId': _agencyId,
        'scope': geographicScopeToJson(_scope),
        'securitySessionToken': _securitySessionToken,
      }),
    );
  }

  void _clearInMemory(SessionTerminationReason reason) {
    _role = null;
    _operatorName = '';
    _accessId = '';
    _agencyId = null;
    _scope = GeographicScope.kaduna;
    _securitySessionToken = null;
    _lastTerminationReason = reason;
    notifyListeners();
  }

  static T? _enumByName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static String? _clean(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class TgcgSession extends InheritedNotifier<TgcgSessionController> {
  const TgcgSession({
    super.key,
    required TgcgSessionController controller,
    required super.child,
  }) : super(notifier: controller);

  static TgcgSessionController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<TgcgSession>();
      assert(value != null, 'TgcgSession is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<TgcgSession>();
    final value = element?.widget as TgcgSession?;
    assert(value != null, 'TgcgSession is missing above this context.');
    return value!.notifier!;
  }
}

String roleLabel(TgcgRole role) => switch (role) {
      TgcgRole.stateAdministrator => 'State Administrator',
      TgcgRole.stateCollationOfficer => 'State Collation Officer',
      TgcgRole.situationRoomDirector => 'Situation Room Director',
      TgcgRole.senatorialCoordinator => 'Senatorial Zone Coordinator',
      TgcgRole.stateCoordinator => 'State Coordinator',
      TgcgRole.lgaCoordinator => 'LGA Coordinator',
      TgcgRole.wardCoordinator => 'Ward Coordinator',
      TgcgRole.pollingUnitCoordinator => 'Polling Unit Coordinator',
      TgcgRole.pollingUnitAgent => 'Polling Unit Agent',
      TgcgRole.mediaOfficer => 'Media Officer',
      TgcgRole.womenMobilizationCoordinator => 'Women Mobilization Coordinator',
      TgcgRole.youthMobilizationCoordinator => 'Youth Mobilization Coordinator',
      TgcgRole.communicationsOfficer => 'Communications Officer',
      TgcgRole.logisticsOfficer => 'Logistics Officer',
      TgcgRole.monitoringEvaluationOfficer => 'Monitoring & Evaluation Officer',
      TgcgRole.dataEvidenceOfficer => 'Data & Evidence Officer',
      TgcgRole.transportCoordinator => 'Transport Coordinator',
      TgcgRole.trainingOfficer => 'Training Officer',
      TgcgRole.ictOfficer => 'ICT Officer',
      TgcgRole.member => 'Member',
      TgcgRole.observer => 'Observer',
      TgcgRole.legalOfficer => 'Legal Officer',
      TgcgRole.technicalSupport => 'Technical Support',
      TgcgRole.readOnlyExecutive => 'Executive Viewer',
      TgcgRole.securityOfficer => 'Security Officer',
    };

String roleDescription(TgcgRole role) => switch (role) {
      TgcgRole.stateAdministrator =>
        'Kaduna State system administration, access control and operational oversight.',
      TgcgRole.stateCollationOfficer =>
        'State-wide result verification, collation, reconciliation and reporting.',
      TgcgRole.situationRoomDirector =>
        'Live incidents, field reporting, verification and response coordination.',
      TgcgRole.senatorialCoordinator =>
        'Coordination and operational monitoring across the LGAs of an assigned senatorial zone.',
      TgcgRole.stateCoordinator =>
        'Kaduna State member network, assignments, incidents and result verification.',
      TgcgRole.lgaCoordinator =>
        'LGA field coordination, reporting, member assignments and operational deployment.',
      TgcgRole.wardCoordinator =>
        'Ward-level coordination, member roles, assignments and operational reporting.',
      TgcgRole.pollingUnitCoordinator =>
        'Polling-unit coordination, member assignments, presence and operational reporting.',
      TgcgRole.pollingUnitAgent =>
        'Polling-unit field duty, incident reporting, evidence and result submission.',
      TgcgRole.mediaOfficer =>
        'Media information, field updates, review, coordination and escalation within the assigned scope.',
      TgcgRole.womenMobilizationCoordinator =>
        'Women-focused coordination, meetings, communications and assigned operational activities.',
      TgcgRole.youthMobilizationCoordinator =>
        'Youth-focused coordination, meetings, communications and assigned operational activities.',
      TgcgRole.communicationsOfficer =>
        'Operational communications, discussion and meeting coordination.',
      TgcgRole.logisticsOfficer =>
        'Logistics coordination, location-aware operations and field communications.',
      TgcgRole.monitoringEvaluationOfficer =>
        'Monitoring, field reporting, evidence review and operational reporting.',
      TgcgRole.dataEvidenceOfficer =>
        'Data, evidence, audit and reporting responsibilities within the assigned scope.',
      TgcgRole.transportCoordinator =>
        'Transport coordination, geographic operations and field communications.',
      TgcgRole.trainingOfficer =>
        'Training coordination, discussion, communications and meeting support.',
      TgcgRole.ictOfficer =>
        'ICT support, system visibility and operational technical coordination.',
      TgcgRole.member =>
        'Registered member identity. Operational access is granted by roles or active assignments.',
      TgcgRole.observer =>
        'Observation, structured field reporting and evidence submission.',
      TgcgRole.legalOfficer =>
        'Evidence review, disputes, incidents, audit and legal documentation.',
      TgcgRole.technicalSupport =>
        'Technical operations, user support, system monitoring and troubleshooting.',
      TgcgRole.readOnlyExecutive =>
        'Read-only state command, incident, collation and audit visibility.',
      TgcgRole.securityOfficer =>
        'Agency-only response desk for assigned incidents, evidence, coordinates and responder status updates.',
    };

IconData roleIcon(TgcgRole role) => switch (role) {
      TgcgRole.stateAdministrator => Icons.admin_panel_settings_rounded,
      TgcgRole.stateCollationOfficer => Icons.account_tree_rounded,
      TgcgRole.situationRoomDirector => Icons.radar_rounded,
      TgcgRole.senatorialCoordinator => Icons.hub_rounded,
      TgcgRole.stateCoordinator => Icons.map_rounded,
      TgcgRole.lgaCoordinator => Icons.location_city_rounded,
      TgcgRole.wardCoordinator => Icons.grid_view_rounded,
      TgcgRole.pollingUnitCoordinator => Icons.place_rounded,
      TgcgRole.pollingUnitAgent => Icons.how_to_vote_rounded,
      TgcgRole.mediaOfficer => Icons.campaign_outlined,
      TgcgRole.womenMobilizationCoordinator => Icons.groups_2_outlined,
      TgcgRole.youthMobilizationCoordinator => Icons.diversity_3_outlined,
      TgcgRole.communicationsOfficer => Icons.forum_outlined,
      TgcgRole.logisticsOfficer => Icons.inventory_2_outlined,
      TgcgRole.monitoringEvaluationOfficer => Icons.query_stats_outlined,
      TgcgRole.dataEvidenceOfficer => Icons.fact_check_outlined,
      TgcgRole.transportCoordinator => Icons.local_shipping_outlined,
      TgcgRole.trainingOfficer => Icons.school_outlined,
      TgcgRole.ictOfficer => Icons.computer_outlined,
      TgcgRole.member => Icons.person_pin_circle_rounded,
      TgcgRole.observer => Icons.visibility_rounded,
      TgcgRole.legalOfficer => Icons.gavel_rounded,
      TgcgRole.technicalSupport => Icons.support_agent_rounded,
      TgcgRole.readOnlyExecutive => Icons.dashboard_customize_rounded,
      TgcgRole.securityOfficer => Icons.local_police_rounded,
    };

Set<TgcgModule> allowedModules(TgcgRole role) {
  // Accredited security personnel get a dedicated agency-response workspace
  // rather than the wider USESF command environment.
  if (role == TgcgRole.securityOfficer) {
    return const {TgcgModule.securityResponse};
  }
  return modulesForCapabilities(
    TgcgPermissionPolicy.capabilitiesFor(role),
    role: role,
  );
}

Set<TgcgModule> modulesForCapabilities(
  Set<TgcgCapability> capabilities, {
  TgcgRole? role,
}) {
  if (role == TgcgRole.securityOfficer) {
    return const {TgcgModule.securityResponse};
  }

  final modules = <TgcgModule>{TgcgModule.overview};
  bool has(TgcgCapability capability) => capabilities.contains(capability);

  if (has(TgcgCapability.manageMembership)) {
    modules.add(TgcgModule.memberEnrollment);
  }
  if (role == TgcgRole.stateAdministrator) {
    modules.add(TgcgModule.membershipNetwork);
  }
  if (has(TgcgCapability.manageRoleAssignments)) {
    modules.add(TgcgModule.membershipNetwork);
    modules.add(TgcgModule.roleAssignment);
  }
  if (has(TgcgCapability.viewGeography)) {
    modules.add(TgcgModule.geography);
    if (role != TgcgRole.member &&
        role != TgcgRole.pollingUnitAgent &&
        role != TgcgRole.observer) {
      modules.add(TgcgModule.liveOperations);
      modules.add(TgcgModule.aiAnalytics);
      modules.add(TgcgModule.alertCenter);
    }
  }
  if (has(TgcgCapability.manageAssignments)) {
    modules.add(TgcgModule.assignmentControl);
  }
  if (has(TgcgCapability.viewIncidents) ||
      has(TgcgCapability.createIncident) ||
      has(TgcgCapability.submitFieldReport)) {
    modules.add(TgcgModule.fieldMonitoring);
  }
  if (has(TgcgCapability.viewEvidence) ||
      has(TgcgCapability.captureEvidence)) {
    modules.add(TgcgModule.evidenceCapture);
  }
  if (has(TgcgCapability.viewSituationRoom)) {
    modules.add(TgcgModule.situationRoom);
  }
  if (has(TgcgCapability.viewSituationRoom) &&
      has(TgcgCapability.assignIncident)) {
    modules.add(TgcgModule.securityResponse);
  }
  if (has(TgcgCapability.submitElectionResult) ||
      has(TgcgCapability.verifyElectionResult) ||
      has(TgcgCapability.disputeElectionResult)) {
    modules.add(TgcgModule.resultCapture);
  }
  if (has(TgcgCapability.verifyElectionResult) ||
      has(TgcgCapability.manageMembership) ||
      has(TgcgCapability.manageEvidence)) {
    modules.add(TgcgModule.aiVerification);
  }
  if (has(TgcgCapability.viewCollation)) {
    modules.add(TgcgModule.collation);
  }
  if (has(TgcgCapability.viewMediaIntelligence)) {
    modules.add(TgcgModule.mediaIntelligence);
  }
  if (has(TgcgCapability.viewCommunications)) {
    modules.add(TgcgModule.communications);
  }
  if (has(TgcgCapability.sendBroadcast)) {
    modules.add(TgcgModule.bulkCommunications);
  }
  if (has(TgcgCapability.viewDiscussionRoom)) {
    modules.add(TgcgModule.discussionRoom);
  }
  if (has(TgcgCapability.viewMeetingRoom)) {
    modules.add(TgcgModule.meetingRoom);
  }
  if (has(TgcgCapability.viewAudit) ||
      has(TgcgCapability.manageSystemSettings) ||
      has(TgcgCapability.viewSituationRoom)) {
    modules.add(TgcgModule.systemMonitoring);
  }
  if (has(TgcgCapability.exportReports)) {
    modules.add(TgcgModule.reports);
  }
  if (role == TgcgRole.stateCoordinator ||
      has(TgcgCapability.viewAudit) ||
      has(TgcgCapability.manageUsers) ||
      has(TgcgCapability.manageSystemSettings)) {
    modules.add(TgcgModule.governance);
  }

  return modules;
}
