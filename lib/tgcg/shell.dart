import 'package:flutter/material.dart';

import 'access/access_policy.dart';
import 'ai/ai_verification_page.dart';
import 'assignments/assignment_control_page.dart';
import 'alerts/alert_center_page.dart';
import 'analytics/ai_data_analytics_page.dart';
import 'collation/collation_page.dart';
import 'communications/bulk_communications_page.dart';
import 'communications/communications_page.dart';
import 'dashboard_page.dart';
import 'domain/permissions.dart';
import 'discussion/discussion_room_page.dart';
import 'evidence/evidence_capture_page.dart';
import 'evidence/evidence_intelligence_page.dart';
import 'field/field_monitoring_page.dart';
import 'field/situation_room_page.dart';
import 'geography/geography_page.dart';
import 'governance/governance_page.dart';
import 'governance/role_assignment_page.dart';
import 'media/media_intelligence_page.dart';
import 'meeting/meeting_room_page.dart';
import 'membership/member_operations_page.dart';
import 'membership/member_shell.dart';
import 'membership/pvc_enrollment_page.dart';
import 'membership/state_member_enrollment_page.dart';
import 'monitoring/system_monitoring_page.dart';
import 'offline/offline_persistence.dart';
import 'operations/live_operations_page.dart';
import 'presentation/presentation_tour_sheet.dart';
import 'reports/reports_page.dart';
import 'results/result_capture_page.dart';
import 'security/security_response_portal_page.dart';
import 'session.dart';
import 'ui/tgcg_design.dart';

class TgcgShell extends StatefulWidget {
  const TgcgShell({super.key});

  @override
  State<TgcgShell> createState() => _TgcgShellState();
}

class _TgcgShellState extends State<TgcgShell> {
  TgcgModule selectedModule = TgcgModule.overview;
  String? _preferredRoleMemberId;

  void _select(TgcgModule module) => setState(() => selectedModule = module);

  void _openRoleAssignmentFor(String memberId) {
    setState(() {
      _preferredRoleMemberId = memberId;
      selectedModule = TgcgModule.roleAssignment;
    });
  }

  void _openTour(Set<TgcgModule> allowed) {
    showPresentationTour(
      context,
      allowedModules: allowed,
      onOpenModule: _select,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final capabilities = TgcgAccessPolicy.capabilities(context);
    final memberLayoutRole = session.role == TgcgRole.member
        ? TgcgAccessPolicy.roleFor(
              context,
              TgcgCapability.viewGeography,
            ) ??
            TgcgRole.member
        : session.role!;
    final allowed = session.role == TgcgRole.member
        ? modulesForCapabilities(
            capabilities,
            role: memberLayoutRole,
          )
        : allowedModules(session.role!);
    if (!allowed.contains(selectedModule)) {
      selectedModule = allowed.contains(TgcgModule.overview)
          ? TgcgModule.overview
          : allowed.first;
    }

    final evidenceRole = TgcgAccessPolicy.roleFor(
      context,
      TgcgCapability.viewEvidence,
    );
    final evidenceIntelligence =
        allowed.contains(TgcgModule.evidenceCapture) &&
        evidenceRole == TgcgRole.stateCoordinator;
    final destinations = _destinations
        .where((item) => allowed.contains(item.module))
        .map(
          (item) => item.module == TgcgModule.evidenceCapture &&
                  evidenceIntelligence
              ? _Destination(
                  item.module,
                  'Evidence Intelligence',
                  Icons.fact_check_outlined,
                  item.group,
                )
              : item,
        )
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1100;
        return Scaffold(
          backgroundColor: TgcgColors.canvas,
          appBar: desktop
              ? null
              : AppBar(
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  flexibleSpace: Container(
                    decoration: const BoxDecoration(
                      gradient: TgcgGradients.commandBar,
                      border: Border(
                        bottom: BorderSide(color: TgcgColors.gold200),
                      ),
                    ),
                  ),
                  title: const _CompactBrand(),
                  actions: [
                    const _CompactSync(),
                    const SizedBox(width: 2),
                    IconButton(
                      tooltip: 'Presentation Tour',
                      onPressed: () => _openTour(allowed),
                      icon: const Icon(Icons.slideshow_rounded),
                    ),
                    if (allowed.contains(TgcgModule.alertCenter))
                      IconButton(
                        tooltip: 'Alert Centre',
                        onPressed: () => _select(TgcgModule.alertCenter),
                        icon: const Badge(
                          smallSize: 7,
                          child: Icon(Icons.notifications_none_rounded),
                        ),
                      ),
                    const SizedBox(width: 6),
                  ],
                ),
          drawer: desktop
              ? null
              : Drawer(
                  backgroundColor: Colors.transparent,
                  child: _Navigation(
                    destinations: destinations,
                    selectedModule: selectedModule,
                    onSelect: (module) {
                      _select(module);
                      Navigator.pop(context);
                    },
                  ),
                ),
          body: desktop
              ? Row(
                  children: [
                    SizedBox(
                      width: 284,
                      child: _Navigation(
                        destinations: destinations,
                        selectedModule: selectedModule,
                        onSelect: _select,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _CommandBar(
                            selectedModule: selectedModule,
                            evidenceIntelligence: evidenceIntelligence,
                            showAlerts: allowed.contains(TgcgModule.alertCenter),
                            onAlerts: () => _select(TgcgModule.alertCenter),
                            onTour: () => _openTour(allowed),
                          ),
                          Expanded(child: _pageFor(selectedModule)),
                        ],
                      ),
                    ),
                  ],
                )
              : _pageFor(selectedModule),
        );
      },
    );
  }

  Widget _pageFor(TgcgModule module) {
    final session = TgcgSession.of(context, listen: false);
    return switch (module) {
        TgcgModule.overview => session.role == TgcgRole.member
            ? const MemberShell()
            : TgcgDashboardPage(onOpenModule: _select),
        TgcgModule.memberEnrollment =>
          TgcgAccessPolicy.roleFor(
            context,
            TgcgCapability.manageMembership,
            listen: false,
          ) ==
              TgcgRole.stateCoordinator
          ? StateMemberEnrollmentPage(
              onAssignRole: _openRoleAssignmentFor,
            )
          : PvcEnrollmentPage(
              onOpenAssignments: () => _select(TgcgModule.assignmentControl),
            ),
        TgcgModule.membershipNetwork => MemberOperationsPage(
            onOpenModule: _select,
          ),
        TgcgModule.roleAssignment => RoleAssignmentPage(
            initialMemberId: _preferredRoleMemberId,
          ),
        TgcgModule.geography => const GeographyPage(),
        TgcgModule.assignmentControl => const AssignmentControlPage(),
        TgcgModule.liveOperations => const LiveOperationsPage(),
        TgcgModule.aiVerification => const AiVerificationPage(),
        TgcgModule.aiAnalytics => const AiDataAnalyticsPage(),
        TgcgModule.alertCenter => const AlertCenterPage(),
        TgcgModule.fieldMonitoring => const FieldMonitoringPage(),
        TgcgModule.evidenceCapture =>
          TgcgAccessPolicy.roleFor(
            context,
            TgcgCapability.viewEvidence,
            listen: false,
          ) ==
              TgcgRole.stateCoordinator
          ? const EvidenceIntelligencePage()
          : const EvidenceCapturePage(),
        TgcgModule.situationRoom => const SituationRoomPage(),
        TgcgModule.securityResponse => const SecurityResponsePortalPage(),
        TgcgModule.resultCapture => const ResultCapturePage(),
        TgcgModule.collation => const CollationPage(),
        TgcgModule.mediaIntelligence => const MediaIntelligencePage(),
        TgcgModule.communications => const CommunicationsPage(),
        TgcgModule.bulkCommunications => const BulkCommunicationsPage(),
        TgcgModule.discussionRoom => const DiscussionRoomPage(),
        TgcgModule.meetingRoom => const MeetingRoomPage(),
        TgcgModule.systemMonitoring => const SystemMonitoringPage(),
        TgcgModule.reports => const ReportsPage(),
        TgcgModule.governance => const GovernancePage(),
      };
  }
}

enum _NavGroup { command, fieldOperations, coordination, control }

class _Destination {
  const _Destination(this.module, this.label, this.icon, this.group);
  final TgcgModule module;
  final String label;
  final IconData icon;
  final _NavGroup group;
}

const _destinations = <_Destination>[
  _Destination(TgcgModule.overview, 'Command Overview', Icons.space_dashboard_outlined, _NavGroup.command),
  _Destination(TgcgModule.liveOperations, 'Live Operations', Icons.travel_explore_rounded, _NavGroup.command),
  _Destination(TgcgModule.aiAnalytics, 'AI Data Analytics', Icons.query_stats_rounded, _NavGroup.command),
  _Destination(TgcgModule.alertCenter, 'Alert Centre', Icons.notifications_active_outlined, _NavGroup.command),
  _Destination(TgcgModule.membershipNetwork, 'Member Operations', Icons.groups_2_outlined, _NavGroup.command),
  _Destination(TgcgModule.situationRoom, 'Situation Room', Icons.radar_rounded, _NavGroup.command),
  _Destination(TgcgModule.securityResponse, 'Security Response', Icons.emergency_share_outlined, _NavGroup.command),
  _Destination(TgcgModule.mediaIntelligence, 'Media Intelligence', Icons.insights_outlined, _NavGroup.command),
  _Destination(TgcgModule.geography, 'Geographic Operations', Icons.public_rounded, _NavGroup.command),
  _Destination(TgcgModule.assignmentControl, 'Assignment Control', Icons.assignment_ind_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.memberEnrollment, 'Member Enrolment', Icons.how_to_reg_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.aiVerification, 'AI Verification', Icons.auto_awesome_rounded, _NavGroup.fieldOperations),
  _Destination(TgcgModule.fieldMonitoring, 'Field Monitoring', Icons.sensors_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.evidenceCapture, 'Evidence Capture', Icons.perm_media_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.resultCapture, 'Result Capture', Icons.ballot_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.collation, 'Collation', Icons.account_tree_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.communications, 'Communications', Icons.forum_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.bulkCommunications, 'Bulk Communications', Icons.send_to_mobile_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.discussionRoom, 'Discussion Forum', Icons.dynamic_feed_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.meetingRoom, 'Meeting Room', Icons.video_camera_front_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.roleAssignment, 'Role Assignment', Icons.manage_accounts_outlined, _NavGroup.control),
  _Destination(TgcgModule.systemMonitoring, 'System Monitoring', Icons.monitor_heart_outlined, _NavGroup.control),
  _Destination(TgcgModule.reports, 'Reports & Exports', Icons.description_outlined, _NavGroup.control),
  _Destination(TgcgModule.governance, 'Data & Governance', Icons.shield_outlined, _NavGroup.control),
];

class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.destinations,
    required this.selectedModule,
    required this.onSelect,
  });

  final List<_Destination> destinations;
  final TgcgModule selectedModule;
  final ValueChanged<TgcgModule> onSelect;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: TgcgGradients.navigation,
        border: Border(
          right: BorderSide(color: Color(0x332B527D)),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .035),
                borderRadius: BorderRadius.circular(TgcgRadius.md),
                border: Border.all(
                  color: TgcgColors.accent.withValues(alpha: .16),
                ),
              ),
              child: const _Brand(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                children: [
                  for (final group in _NavGroup.values)
                    if (destinations.any((item) => item.group == group)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 15, 10, 7),
                        child: Text(
                          _groupLabel(group),
                          style: const TextStyle(
                            color: TgcgColors.gold200,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      ...destinations
                          .where((item) => item.group == group)
                          .map(
                            (item) => _NavTile(
                              item: item,
                              active: item.module == selectedModule,
                              onTap: () => onSelect(item.module),
                            ),
                          ),
                    ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _OperatorCard(session: session),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.active, required this.onTap});
  final _Destination item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(TgcgRadius.sm),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                gradient: active
                    ? LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          TgcgColors.accent.withValues(alpha: .18),
                          Colors.white.withValues(alpha: .035),
                        ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(TgcgRadius.sm),
                border: Border.all(
                  color: active
                      ? TgcgColors.accent.withValues(alpha: .24)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 3,
                    height: active ? 22 : 10,
                    decoration: BoxDecoration(
                      color: active ? TgcgColors.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Icon(
                    item.icon,
                    size: 19,
                    color: active
                        ? TgcgColors.gold400
                        : const Color(0xFFAAB8CC),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? Colors.white : const Color(0xFFD3DCE9),
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _OperatorCard extends StatelessWidget {
  const _OperatorCard({required this.session});
  final TgcgSessionController session;

  @override
  Widget build(BuildContext context) {
    final accessSummary = TgcgAccessPolicy.accessSummary(context);
    final accessScopes = TgcgAccessPolicy.scopesForAny(
      context,
      TgcgAccessPolicy.capabilities(context),
    );
    final scopeSummary = accessScopes.length > 1
        ? '${accessScopes.length} authorized scopes'
        : accessScopes.isEmpty
            ? session.scope.label
            : accessScopes.first.label;

    return Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          border: Border.all(
            color: TgcgColors.accent.withValues(alpha: .14),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: TgcgColors.accent.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(TgcgRadius.sm),
                    border: Border.all(
                      color: TgcgColors.accent.withValues(alpha: .18),
                    ),
                  ),
                  child: const Icon(Icons.person_outline_rounded, color: TgcgColors.accent, size: 19),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.operatorName.isEmpty ? 'USESF Operator' : session.operatorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        accessSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFA4AAB9), fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: session.signOut,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.logout_rounded, color: Color(0xFFA4AAB9), size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: Color(0xFF7E8698), size: 14),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    scopeSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF8C94A6), fontSize: 9.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
  }
}

class _CommandBar extends StatelessWidget {
  const _CommandBar({
    required this.selectedModule,
    required this.evidenceIntelligence,
    required this.showAlerts,
    required this.onAlerts,
    required this.onTour,
  });

  final TgcgModule selectedModule;
  final bool evidenceIntelligence;
  final bool showAlerts;
  final VoidCallback onAlerts;
  final VoidCallback onTour;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final pending = OfflinePersistence.of(context).pendingOutbox.length;
    final accessSummary = TgcgAccessPolicy.accessSummary(context);
    final scopes = TgcgAccessPolicy.scopesForAny(
      context,
      TgcgAccessPolicy.capabilities(context),
    );
    final scopeSummary = scopes.length > 1
        ? '${scopes.length} authorized scopes'
        : scopes.isEmpty
            ? session.scope.label
            : scopes.first.label;
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        gradient: TgcgGradients.commandBar,
        border: Border(bottom: BorderSide(color: TgcgColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0806162D),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            _moduleLabel(
              selectedModule,
              evidenceIntelligence: evidenceIntelligence,
            ),
            style: const TextStyle(color: TgcgColors.ink, fontSize: 14, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const TextField(
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Search members, assignments, polling units or incidents',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                ),
              ),
            ),
          ),
          const Spacer(),
          TgcgStatusPill(
            label: pending == 0 ? 'SYNCED' : '$pending TO SYNC',
            color: pending == 0 ? TgcgColors.success : TgcgColors.warning,
            icon: pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
            compact: true,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onTour,
            icon: const Icon(Icons.slideshow_rounded, size: 17),
            label: const Text('Tour'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (showAlerts) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Alert Centre',
              onPressed: onAlerts,
              icon: const Badge(
                smallSize: 7,
                child: Icon(Icons.notifications_none_rounded),
              ),
            ),
          ],
          const SizedBox(width: 4),
          Tooltip(
            message: '$accessSummary • $scopeSummary',
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: TgcgGradients.goldWash,
                borderRadius: BorderRadius.circular(TgcgRadius.sm),
                border: Border.all(color: TgcgColors.gold200),
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                color: TgcgColors.primaryDark,
                size: 19,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSync extends StatelessWidget {
  const _CompactSync();

  @override
  Widget build(BuildContext context) {
    final pending = OfflinePersistence.of(context).pendingOutbox.length;
    return TgcgStatusPill(
      label: pending == 0 ? 'SYNCED' : '$pending QUEUED',
      color: pending == 0 ? TgcgColors.success : TgcgColors.warning,
      icon: pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
      compact: true,
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => const Row(
        children: [
          TgcgLogo(size: 39),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'USESF',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: .7, fontSize: 14),
                ),
                SizedBox(height: 2),
                Text(
                  'Engagement & Sensitization Forum',
                  style: TextStyle(
                    color: TgcgColors.gold200,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .15,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TgcgLogo(size: 36),
          SizedBox(width: 8),
          Text('USESF', style: TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.ink)),
        ],
      );
}

String _groupLabel(_NavGroup group) => switch (group) {
      _NavGroup.command => 'COMMAND',
      _NavGroup.fieldOperations => 'FIELD OPERATIONS',
      _NavGroup.coordination => 'COORDINATION',
      _NavGroup.control => 'CONTROL',
    };

String _moduleLabel(
  TgcgModule module, {
  bool evidenceIntelligence = false,
}) => switch (module) {
      TgcgModule.overview => 'Command Overview',
      TgcgModule.memberEnrollment => 'Member Enrolment',
      TgcgModule.membershipNetwork => 'Registered Members',
      TgcgModule.roleAssignment => 'Role Assignment',
      TgcgModule.geography => 'Geographic Operations',
      TgcgModule.assignmentControl => 'Assignment Control Centre',
      TgcgModule.liveOperations => 'Live Operations',
      TgcgModule.aiVerification => 'AI Verification Centre',
      TgcgModule.aiAnalytics => 'AI Data Analytics Centre',
      TgcgModule.alertCenter => 'Alert Centre',
      TgcgModule.fieldMonitoring => 'Field Monitoring',
      TgcgModule.evidenceCapture =>
        evidenceIntelligence ? 'Evidence Intelligence' : 'Evidence Capture',
      TgcgModule.situationRoom => 'Situation Room',
      TgcgModule.securityResponse => 'Security & Emergency Response',
      TgcgModule.resultCapture => 'Result Capture',
      TgcgModule.collation => 'Collation',
      TgcgModule.mediaIntelligence => 'Media Intelligence',
      TgcgModule.communications => 'Communications',
      TgcgModule.bulkCommunications => 'Bulk Communications Centre',
      TgcgModule.discussionRoom => 'Discussion Forum',
      TgcgModule.meetingRoom => 'Meeting Room',
      TgcgModule.systemMonitoring => 'System Monitoring',
      TgcgModule.reports => 'Reports & Exports',
      TgcgModule.governance => 'Data & Governance',
    };
