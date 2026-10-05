import 'package:flutter/material.dart';

import 'domain/models.dart';
import 'domain/permissions.dart';

export 'domain/models.dart';

enum TgcgModule {
  overview,
  accreditation,
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

class TgcgSessionController extends ChangeNotifier {
  TgcgRole? _role;
  String _operatorName = '';
  String _accessId = '';
  String? _agencyId;
  GeographicScope _scope = GeographicScope.kaduna;

  TgcgRole? get role => _role;
  String get operatorName => _operatorName;
  String get accessId => _accessId;

  /// Response agency for a Security Officer session; null for other roles.
  String? get agencyId => _agencyId;
  GeographicScope get scope => _scope;
  bool get isAuthenticated => _role != null;

  void signIn({
    required TgcgRole role,
    required String operatorName,
    required String accessId,
    GeographicScope scope = GeographicScope.kaduna,
    String? agencyId,
  }) {
    if (role == TgcgRole.securityOfficer &&
        (agencyId == null || agencyId.trim().isEmpty)) {
      throw ArgumentError(
        'Security Officer access requires an authorized response agency.',
      );
    }
    _role = role;
    _agencyId = agencyId;
    _operatorName =
        operatorName.trim().isEmpty ? roleLabel(role) : operatorName.trim();
    _accessId = accessId.trim();
    _scope = scope;
    notifyListeners();
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
  }

  void signOut() {
    _role = null;
    _operatorName = '';
    _accessId = '';
    _agencyId = null;
    _scope = GeographicScope.kaduna;
    notifyListeners();
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
      TgcgRole.monitoringEvaluationOfficer => Icons.monitoring_outlined,
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
    modules.add(TgcgModule.accreditation);
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
  if (has(TgcgCapability.viewEvidence)) {
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
  if (has(TgcgCapability.viewAudit) ||
      has(TgcgCapability.manageUsers) ||
      has(TgcgCapability.manageSystemSettings)) {
    modules.add(TgcgModule.governance);
  }

  return modules;
}
