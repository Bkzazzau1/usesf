import 'package:flutter/material.dart';

import '../access/access_policy.dart';
import '../access/effective_member_access.dart';
import '../devices/managed_device_store.dart';
import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../membership/membership_store.dart';
import '../meeting/operational_call_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'assignment_control_actions.dart';
import 'assignment_store.dart';
import 'group_assignment_panel.dart';
import 'live_deployment_map.dart';

class AssignmentControlPage extends StatefulWidget {
  const AssignmentControlPage({super.key});

  @override
  State<AssignmentControlPage> createState() => _AssignmentControlPageState();
}

class _AssignmentControlPageState extends State<AssignmentControlPage> {
  _RegisterView? _register;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final devices = ManagedDevices.of(context);
    final assignments = Assignments.of(context);
    final calls = OperationalCalls.of(context);
    final stateCoordinatorScope = stateCoordinatorGroupScope(context, session);
    final assignmentScopes = TgcgAccessPolicy.scopesFor(
      context,
      TgcgCapability.manageAssignments,
    );
    final deviceScopes = TgcgAccessPolicy.scopesFor(
      context,
      TgcgCapability.manageDevices,
    );
    final canManageAssignments = assignmentScopes.isNotEmpty;
    final canManageDevices = deviceScopes.isNotEmpty;
    final canCreateGroupAssignment =
        stateCoordinatorGroupScope(context, session) != null;
    final authorizedUnits = membership.geography.pollingUnits
        .where(
          (unit) => assignmentScopes.any(
            (scope) => TgcgPermissionPolicy.scopeAllows(scope, unit.scope),
          ),
        )
        .toList(growable: false);
    final authorizedMembers = membership.members
        .where((member) {
          final scope = membership.registrationScopeForMember(member.id);
          return scope != null &&
              assignmentScopes.any(
                (authority) =>
                    TgcgPermissionPolicy.scopeAllows(authority, scope),
              );
        })
        .toList(growable: false);
    final authorizedMemberIds = authorizedMembers
        .map((member) => member.id)
        .toSet();
    final visibleDevices = devices.devices
        .where((device) {
          if (canManageDevices) return true;
          final memberId = device.assignedMemberId;
          return memberId != null && authorizedMemberIds.contains(memberId);
        })
        .toList(growable: false);
    final visible =
        assignments.assignments
            .where(
              (item) => assignmentScopes.any(
                (scope) =>
                    TgcgPermissionPolicy.scopeAllows(scope, item.targetScope) ||
                    TgcgPermissionPolicy.scopeAllows(item.targetScope, scope),
              ),
            )
            .toList()
          ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
    final visibleGroups = canCreateGroupAssignment
        ? assignments.groupAssignments
        : const <GroupAssignment>[];
    final openGroups = visibleGroups
        .where((group) => group.status != GroupAssignmentStatus.submitted)
        .toList(growable: false);
    final individual = visible
        .where(
          (item) =>
              item.groupAssignmentId == null &&
              item.status != AssignmentStatus.completed,
        )
        .toList(growable: false);
    final submitted = <_SubmittedEntry>[
      for (final item in visible)
        if (item.groupAssignmentId == null &&
            item.status == AssignmentStatus.completed)
          _SubmittedEntry.individual(item),
      for (final group in visibleGroups)
        if (group.status == GroupAssignmentStatus.submitted)
          _SubmittedEntry.group(group),
    ]..sort((a, b) => b.at.compareTo(a.at));
    final register =
        _register ??
        (canCreateGroupAssignment
            ? _RegisterView.group
            : _RegisterView.individual);

    final coverageByUnit = <String, PollingUnitCoverageSnapshot>{};
    for (final scope in assignmentScopes) {
      for (final snapshot in assignments.coverageForScope(scope)) {
        coverageByUnit[snapshot.unit.code] = snapshot;
      }
    }
    final coverage = coverageByUnit.values.toList(growable: false);
    final gaps = coverage.where((item) => item.needsAttention).toList();
    final staffed = coverage.where((item) => !item.isBelowMinimum).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'FIELD DEPLOYMENT',
          title: 'Jobs & Assignment Control',
          subtitle:
              '${assignmentScopes.length} authorized scope${assignmentScopes.length == 1 ? '' : 's'}: any registered member inside your authority can receive a job or temporary field assignment without changing the member\'s permanent home polling unit.',
          trailing: canManageAssignments
              ? Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (stateCoordinatorScope != null)
                      OutlinedButton.icon(
                        onPressed: () => showStateCoordinatorCallMemberDialog(
                          context,
                          calls: calls,
                          membership: membership,
                          session: session,
                          stateScope: stateCoordinatorScope,
                        ),
                        icon: const Icon(Icons.video_call_outlined),
                        label: const Text('Call member'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _setStaffingRequirement(
                        context,
                        assignments,
                        session,
                        authorizedUnits,
                        assignmentScopes,
                      ),
                      icon: const Icon(Icons.groups_2_outlined),
                      label: const Text('Staffing needs'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _createAssignment(
                        context,
                        membership,
                        assignments,
                        session,
                        authorizedMembers,
                        authorizedUnits,
                        assignmentScopes,
                      ),
                      icon: const Icon(Icons.add_task_rounded),
                      label: const Text('New assignment'),
                    ),
                  ],
                )
              : null,
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 980
                ? 5
                : constraints.maxWidth >= 620
                ? 3
                : 2;
            const gap = 10.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                TgcgMetricCard(
                  width: width,
                  label: 'Jobs / assignments',
                  value: '${visible.length}',
                  detail: 'Within current scope',
                  icon: Icons.assignment_outlined,
                  tone: TgcgMetricTone.info,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Active jobs',
                  value: '${visible.where((item) => !item.isTerminal).length}',
                  detail: 'Open duties and deployments',
                  icon: Icons.play_circle_outline_rounded,
                  tone: TgcgMetricTone.success,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'At location',
                  value:
                      '${visible.where((item) => assignments.presenceFor(item) == AssignmentPresence.insideGeofence).length}',
                  detail: 'Fresh GPS inside geofence',
                  icon: Icons.gps_fixed_rounded,
                  tone: TgcgMetricTone.success,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'GPS alerts',
                  value:
                      '${visible.where((item) => item.status == AssignmentStatus.gpsMismatch || assignments.presenceFor(item) == AssignmentPresence.stale).length}',
                  detail: 'Mismatch or stale location',
                  icon: Icons.location_off_outlined,
                  tone: TgcgMetricTone.warning,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Managed phones',
                  value: '${visibleDevices.length}',
                  detail:
                      '${visibleDevices.where((item) => item.status == ManagedDeviceStatus.assigned).length} assigned • ${visibleDevices.where((item) => item.status == ManagedDeviceStatus.available).length} available',
                  icon: Icons.phone_android_rounded,
                  tone: TgcgMetricTone.neutral,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LiveDeploymentMap(
          assignments: visible,
          controller: assignments,
          membership: membership,
          snapshots: coverage,
          authorizedUnits: authorizedUnits,
        ),
        const SizedBox(height: 16),
        _RegisterTabs(
          selected: register,
          showGroups: canCreateGroupAssignment,
          groupCount: openGroups.length,
          individualCount: individual.length,
          submittedCount: submitted.length,
          onSelect: (view) => setState(() => _register = view),
        ),
        const SizedBox(height: 12),
        switch (register) {
          _RegisterView.group => GroupAssignmentPanel(
            controller: assignments,
            membership: membership,
            groups: openGroups,
            onCreate: () => _createGroupAssignment(
              context,
              membership,
              assignments,
              session,
              authorizedMembers,
              authorizedUnits,
            ),
            onCancel: (group) =>
                _cancelGroupAssignment(context, assignments, session, group),
            onCallChairman: (group) => _callGroupChairman(
              context,
              calls,
              membership,
              session,
              stateCoordinatorScope!,
              group,
            ),
            onCallGroup: (group) => _callGroupConference(
              context,
              calls,
              session,
              stateCoordinatorScope!,
              group,
            ),
          ),
          _RegisterView.individual => _AssignmentList(
            title: 'Individual assignments',
            subtitle:
                'Open individual duties: member, location, status, managed phone and latest geofence presence.',
            emptyTitle: 'No open individual assignments',
            emptyMessage:
                'Use New assignment to deploy a member to a polling unit or a location-flexible duty.',
            assignments: individual,
            membership: membership,
            controller: assignments,
            canManage: canManageAssignments,
            authorizedMembers: authorizedMembers,
            actorId: session.accessId.isEmpty
                ? session.operatorName
                : session.accessId,
            authorizedScope: assignmentScopes.isEmpty
                ? session.scope
                : assignmentScopes.first,
            calls: calls,
            session: session,
            stateCoordinatorScope: stateCoordinatorScope,
          ),
          _RegisterView.submitted => _SubmittedAssignments(
            entries: submitted,
            membership: membership,
            controller: assignments,
          ),
        },
        const SizedBox(height: 16),
        _CoverageGapPanel(
          snapshots: gaps,
          totalPollingUnits: coverage.length,
          staffedPollingUnits: staffed,
        ),
        const SizedBox(height: 16),
        _DeviceRegistry(
          devices: devices,
          visibleDevices: visibleDevices,
          membership: membership,
          canManage: canManageDevices,
          onRegister: () => _registerDevice(context, devices, session),
          onAssign: () => _assignDevice(
            context,
            devices,
            membership,
            session,
            authorizedMembers,
            deviceScopes,
          ),
        ),
      ],
    );
  }

  Future<void> _callGroupChairman(
    BuildContext context,
    OperationalCallController calls,
    MembershipOperationsController membership,
    TgcgSessionController session,
    GeographicScope stateScope,
    GroupAssignment group,
  ) async {
    final chairman = membership.memberById(group.chairmanMemberId);
    if (chairman == null) return;
    try {
      await startStateCoordinatorMemberCall(
        context,
        calls: calls,
        session: session,
        stateScope: stateScope,
        member: chairman,
        kind: OperationalCallKind.video,
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _callGroupConference(
    BuildContext context,
    OperationalCallController calls,
    TgcgSessionController session,
    GeographicScope stateScope,
    GroupAssignment group,
  ) async {
    try {
      await startStateCoordinatorGroupCall(
        context,
        calls: calls,
        session: session,
        stateScope: stateScope,
        memberIds: group.memberIds,
        groupAssignmentId: group.id,
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _createGroupAssignment(
    BuildContext context,
    MembershipOperationsController membership,
    AssignmentController assignments,
    TgcgSessionController session,
    List<TgcgMember> authorizedMembers,
    List<CanonicalPollingUnit> authorizedUnits,
  ) async {
    final created = await showGroupAssignmentDialog(
      context: context,
      membership: membership,
      assignments: assignments,
      session: session,
      authorizedMembers: authorizedMembers,
      authorizedUnits: authorizedUnits,
    );
    if (created && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group assignment created.')),
      );
    }
  }

  Future<void> _cancelGroupAssignment(
    BuildContext context,
    AssignmentController assignments,
    TgcgSessionController session,
    GroupAssignment group,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel group assignment'),
        content: Text(group.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel group'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final authorizedScope = stateCoordinatorGroupScope(
      context,
      session,
      listen: false,
    );
    if (authorizedScope == null) return;

    try {
      await assignments.cancelGroupAssignment(
        groupAssignmentId: group.id,
        cancelledBy: session.accessId.isEmpty
            ? session.operatorName
            : session.accessId,
        cancelledByRole: TgcgRole.stateCoordinator,
        authorizedScope: authorizedScope,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group assignment cancelled.')),
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _setStaffingRequirement(
    BuildContext context,
    AssignmentController assignments,
    TgcgSessionController session,
    List<CanonicalPollingUnit> authorizedUnits,
    List<GeographicScope> assignmentScopes,
  ) async {
    if (authorizedUnits.isEmpty) return;

    final lgaIds = authorizedUnits
        .map((unit) => unit.scope.lgaId)
        .whereType<String>()
        .toSet();
    var lgaId = authorizedUnits.first.scope.lgaId!;
    var units = authorizedUnits
        .where((unit) => unit.scope.lgaId == lgaId)
        .toList(growable: false);
    var pollingUnitId = units.first.code;
    var minimum = assignments.minimumStaffingFor(pollingUnitId);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Polling-unit staffing need'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: lgaId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'LGA',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                  items: authorizedUnits
                      .map((unit) => unit.scope)
                      .where((scope) => scope.lgaId != null)
                      .fold<Map<String, String>>(<String, String>{}, (
                        map,
                        scope,
                      ) {
                        if (lgaIds.contains(scope.lgaId)) {
                          map[scope.lgaId!] = scope.lgaName ?? scope.lgaId!;
                        }
                        return map;
                      })
                      .entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      lgaId = value;
                      units = authorizedUnits
                          .where((unit) => unit.scope.lgaId == lgaId)
                          .toList(growable: false);
                      pollingUnitId = units.first.code;
                      minimum = assignments.minimumStaffingFor(pollingUnitId);
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('staffing-pu-$lgaId-$pollingUnitId'),
                  initialValue: pollingUnitId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Polling unit',
                    prefixIcon: Icon(Icons.how_to_vote_outlined),
                  ),
                  items: units
                      .map(
                        (unit) => DropdownMenuItem(
                          value: unit.code,
                          child: Text(
                            '${unit.displayCode} • ${unit.scope.pollingUnitName ?? unit.scope.label}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      pollingUnitId = value;
                      minimum = assignments.minimumStaffingFor(pollingUnitId);
                    });
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Required personnel',
                        style: TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: minimum > 0
                          ? () => setDialogState(() => minimum--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Container(
                      width: 62,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: TgcgColors.navy50,
                        borderRadius: BorderRadius.circular(TgcgRadius.sm),
                        border: Border.all(color: TgcgColors.border),
                      ),
                      child: Text(
                        '$minimum',
                        style: const TextStyle(
                          color: TgcgColors.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: minimum < 100
                          ? () => setDialogState(() => minimum++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Coverage gaps compare active assignments and fresh GPS presence against this requirement.',
                  style: TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await assignments.setMinimumStaffing(
                  pollingUnitId: pollingUnitId,
                  minimumStaffing: minimum,
                  actorId: session.accessId.isEmpty
                      ? session.operatorName
                      : session.accessId,
                  authorizedScope:
                      _scopeCovering(
                        assignmentScopes,
                        _scopeForUnit(authorizedUnits, pollingUnitId),
                      ) ??
                      session.scope,
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save requirement'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Polling-unit staffing requirement updated.'),
        ),
      );
    }
  }

  Future<void> _createAssignment(
    BuildContext context,
    MembershipOperationsController membership,
    AssignmentController assignments,
    TgcgSessionController session,
    List<TgcgMember> authorizedMembers,
    List<CanonicalPollingUnit> authorizedUnits,
    List<GeographicScope> assignmentScopes,
  ) async {
    if (authorizedMembers.isEmpty) {
      return;
    }

    var memberId = authorizedMembers.first.id;
    final authorizedLgaIds = authorizedUnits
        .map((unit) => unit.scope.lgaId)
        .whereType<String>()
        .toSet();
    final authorizedLgas = membership.geography.lgas
        .where((lga) => authorizedLgaIds.contains(lga.id))
        .toList(growable: false);

    String? lgaId = authorizedLgas.isEmpty ? null : authorizedLgas.first.id;
    var units = lgaId == null
        ? const <CanonicalPollingUnit>[]
        : authorizedUnits
              .where((unit) => unit.scope.lgaId == lgaId)
              .toList(growable: false);
    String? pollingUnitId = units.isEmpty ? null : units.first.code;
    var locationBound = authorizedLgas.isNotEmpty;
    var priority = AssignmentPriority.normal;
    final selectedCapabilities = <TgcgCapability>{};
    final availableCapabilities = _assignmentGrantOptions(
      _delegableCapabilities(context, session),
    );
    final coordinateStateScope = stateCoordinatorGroupScope(
      context,
      session,
      listen: false,
    );
    final title = TextEditingController(text: 'Field Duty Assignment');
    final instructions = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign a job to a member'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: memberId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Member',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    items: authorizedMembers
                        .map(
                          (member) => DropdownMenuItem(
                            value: member.id,
                            child: Text(
                              '${member.fullName} • ${member.membershipNumber ?? member.id}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => memberId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: locationBound,
                    onChanged: (value) => setDialogState(() {
                      locationBound = value;
                    }),
                    title: const Text(
                      'Tie this assignment to a polling unit',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Turn this off for special or location-flexible assignments. GPS is still required when work is captured or submitted.',
                    ),
                  ),
                  if (locationBound) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: lgaId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Target LGA',
                        prefixIcon: Icon(Icons.location_city_outlined),
                      ),
                      items: authorizedLgas
                          .map(
                            (lga) => DropdownMenuItem(
                              value: lga.id,
                              child: Text(lga.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          lgaId = value;
                          units = authorizedUnits
                              .where((unit) => unit.scope.lgaId == lgaId)
                              .toList(growable: false);
                          pollingUnitId = units.isEmpty
                              ? null
                              : units.first.code;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('assignment-pu-$lgaId'),
                      initialValue: pollingUnitId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Operational polling unit',
                        prefixIcon: Icon(Icons.how_to_vote_outlined),
                      ),
                      items: units
                          .map(
                            (unit) => DropdownMenuItem(
                              value: unit.code,
                              child: Text(
                                '${unit.displayCode} • ${unit.scope.pollingUnitName ?? unit.scope.label}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => pollingUnitId = value),
                    ),
                    if (coordinateStateScope != null &&
                        pollingUnitId != null) ...[
                      const SizedBox(height: 10),
                      Builder(
                        builder: (context) {
                          final unit = membership.geography.pollingUnit(
                            pollingUnitId!,
                          );
                          if (unit == null) return const SizedBox.shrink();
                          final ready =
                              unit.operationalLatitude != null &&
                              unit.operationalLongitude != null;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final changed =
                                    await showPollingUnitCoordinateDialog(
                                      context,
                                      membership: membership,
                                      unit: unit,
                                      actorId: session.accessId.isEmpty
                                          ? session.operatorName
                                          : session.accessId,
                                      stateScope: coordinateStateScope,
                                    );
                                if (changed && dialogContext.mounted) {
                                  setDialogState(() {});
                                }
                              },
                              icon: Icon(
                                ready
                                    ? Icons.gps_fixed_rounded
                                    : Icons.add_location_alt_outlined,
                              ),
                              label: Text(
                                ready ? 'Polling-unit GPS' : 'Add GPS',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AssignmentPriority>(
                    initialValue: priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: AssignmentPriority.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.name.toUpperCase()),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => priority = value ?? priority),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Job / assignment title',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: instructions,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Instructions',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    title: const Text(
                      'Temporary app access',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text(
                      'Choose only the tools this assignment needs. Access disappears automatically when the assignment closes.',
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: availableCapabilities.map((capability) {
                            final selected = selectedCapabilities.contains(
                              capability,
                            );
                            return FilterChip(
                              selected: selected,
                              label: Text(
                                _assignmentCapabilityLabel(capability),
                              ),
                              onSelected: (value) => setDialogState(() {
                                if (value) {
                                  selectedCapabilities.add(capability);
                                } else {
                                  selectedCapabilities.remove(capability);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: locationBound && pollingUnitId == null
                  ? null
                  : () async {
                      try {
                        final authorizedScope =
                            _scopeCovering(
                              assignmentScopes,
                              locationBound && pollingUnitId != null
                                  ? membership.geography
                                        .pollingUnit(pollingUnitId!)
                                        ?.scope
                                  : membership.registrationScopeForMember(
                                      memberId,
                                    ),
                            ) ??
                            assignmentScopes.first;
                        await assignments.createAssignment(
                          title: title.text,
                          memberId: memberId,
                          pollingUnitId: locationBound ? pollingUnitId : null,
                          assignedBy: session.accessId.isEmpty
                              ? session.operatorName
                              : session.accessId,
                          authorizedScope: authorizedScope,
                          priority: priority,
                          instructions: instructions.text,
                          grantedCapabilities: Set.unmodifiable(
                            selectedCapabilities,
                          ),
                          assignerCapabilities: _delegableCapabilities(
                            context,
                            session,
                            within: authorizedScope,
                          ),
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } on StateError catch (error) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(
                          dialogContext,
                        ).showSnackBar(SnackBar(content: Text(error.message)));
                      }
                    },
              icon: const Icon(Icons.assignment_turned_in_outlined),
              label: const Text('Create assignment'),
            ),
          ],
        ),
      ),
    );

    title.dispose();
    instructions.dispose();
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Member assignment created and queued for sync.'),
        ),
      );
    }
  }

  Future<void> _registerDevice(
    BuildContext context,
    ManagedDeviceController devices,
    TgcgSessionController session,
  ) async {
    final label = TextEditingController(text: 'USESF Managed Phone');
    final serial = TextEditingController();
    final imei = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Register managed phone'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Device label'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: serial,
                decoration: const InputDecoration(
                  labelText: 'Serial reference (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: imei,
                decoration: const InputDecoration(
                  labelText: 'IMEI reference (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await devices.registerDevice(
                label: label.text,
                serialReference: serial.text,
                imeiReference: imei.text,
                registeredBy: session.accessId.isEmpty
                    ? session.operatorName
                    : session.accessId,
              );
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, true);
              }
            },
            icon: const Icon(Icons.phone_android_rounded),
            label: const Text('Register'),
          ),
        ],
      ),
    );

    label.dispose();
    serial.dispose();
    imei.dispose();
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Managed phone registered.')),
      );
    }
  }

  Future<void> _assignDevice(
    BuildContext context,
    ManagedDeviceController devices,
    MembershipOperationsController membership,
    TgcgSessionController session,
    List<TgcgMember> authorizedMembers,
    List<GeographicScope> deviceScopes,
  ) async {
    final available = devices.devices
        .where((item) => item.status == ManagedDeviceStatus.available)
        .toList(growable: false);
    if (available.isEmpty || authorizedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Register an available phone before assigning it.'),
        ),
      );
      return;
    }

    var deviceId = available.first.id;
    var memberId = authorizedMembers.first.id;
    final assigned = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign managed phone'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: deviceId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  items: available
                      .map(
                        (device) => DropdownMenuItem(
                          value: device.id,
                          child: Text(device.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => deviceId = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: memberId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Member'),
                  items: authorizedMembers
                      .map(
                        (member) => DropdownMenuItem(
                          value: member.id,
                          child: Text(
                            '${member.fullName} • ${member.membershipNumber ?? member.id}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => memberId = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await devices.assignToMember(
                    deviceId: deviceId,
                    memberId: memberId,
                    assignedBy: session.accessId.isEmpty
                        ? session.operatorName
                        : session.accessId,
                    authorizedScope: deviceScopes.isEmpty
                        ? session.scope
                        : deviceScopes.first,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } on StateError catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text(error.message)));
                }
              },
              icon: const Icon(Icons.link_rounded),
              label: const Text('Assign phone'),
            ),
          ],
        ),
      ),
    );

    if (assigned == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Managed phone assigned to member.')),
      );
    }
  }
}

GeographicScope? _scopeForUnit(
  List<CanonicalPollingUnit> units,
  String pollingUnitId,
) {
  for (final unit in units) {
    if (unit.code == pollingUnitId) return unit.scope;
  }
  return null;
}

GeographicScope? _scopeCovering(
  List<GeographicScope> authorities,
  GeographicScope? target,
) {
  if (target == null) return authorities.isEmpty ? null : authorities.first;
  for (final scope in authorities) {
    if (TgcgPermissionPolicy.scopeAllows(scope, target)) return scope;
  }
  return null;
}

/// Capabilities the signed-in coordinator may delegate: the union of their
/// role capabilities (optionally only roles covering [within]). Capabilities
/// held only through the coordinator's own assignments are not delegable, so
/// temporary access cannot be passed down a chain.
Set<TgcgCapability> _delegableCapabilities(
  BuildContext context,
  TgcgSessionController session, {
  GeographicScope? within,
}) {
  final member = TgcgAccessPolicy.memberAccess(context, listen: false);
  if (member == null) {
    final role = session.role;
    if (role == null) return const {};
    if (within != null &&
        !TgcgPermissionPolicy.scopeAllows(session.scope, within)) {
      return const {};
    }
    return TgcgPermissionPolicy.capabilitiesFor(role);
  }
  return member.grants
      .where((grant) => grant.source == EffectiveGrantSource.role)
      .where(
        (grant) =>
            within == null ||
            TgcgPermissionPolicy.scopeAllows(grant.scope, within),
      )
      .expand((grant) => grant.capabilities)
      .toSet();
}

List<TgcgCapability> _assignmentGrantOptions(Set<TgcgCapability> own) =>
    assignmentGrantableCapabilities.where(own.contains).toList(growable: false);

String _assignmentCapabilityLabel(TgcgCapability capability) =>
    switch (capability) {
      TgcgCapability.viewGeography => 'Geography',
      TgcgCapability.viewIncidents => 'View incidents',
      TgcgCapability.createIncident => 'Report incidents',
      TgcgCapability.submitFieldReport => 'Field reports',
      TgcgCapability.viewCommunications => 'Messages',
      TgcgCapability.sendOperationalMessage => 'Send messages',
      TgcgCapability.viewMediaIntelligence => 'Media',
      TgcgCapability.viewDiscussionRoom => 'Discussion forum',
      TgcgCapability.createDiscussionThread => 'Start discussions',
      TgcgCapability.postDiscussionReply => 'Comment / reply',
      TgcgCapability.viewMeetingRoom => 'Meeting rooms',
      TgcgCapability.startMeeting => 'Start meetings',
      TgcgCapability.joinMeeting => 'Join meetings',
      TgcgCapability.viewEvidence => 'Evidence',
      _ => capability.name,
    };

class _CoverageGapPanel extends StatelessWidget {
  const _CoverageGapPanel({
    required this.snapshots,
    required this.totalPollingUnits,
    required this.staffedPollingUnits,
  });

  final List<PollingUnitCoverageSnapshot> snapshots;
  final int totalPollingUnits;
  final int staffedPollingUnits;

  @override
  Widget build(BuildContext context) {
    final unstaffed = snapshots.where((item) => item.isUnstaffed).length;
    final presenceGaps = snapshots.where((item) => item.hasPresenceGap).length;
    final gpsAlerts = snapshots.where((item) => item.hasGpsAlert).length;

    return TgcgSectionCard(
      title: 'Coverage Gap Engine',
      subtitle:
          'Rule-based staffing and presence checks across the polling units currently loaded in this scope.',
      trailing: TgcgStatusPill(
        label: '${snapshots.length} NEED ATTENTION',
        color: snapshots.isEmpty ? TgcgColors.success : TgcgColors.warning,
        icon: snapshots.isEmpty
            ? Icons.check_circle_outline_rounded
            : Icons.warning_amber_rounded,
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TgcgStatusPill(
                label: '$staffedPollingUnits / $totalPollingUnits STAFFED',
                color: TgcgColors.success,
                compact: true,
              ),
              TgcgStatusPill(
                label: '$unstaffed UNSTAFFED',
                color: unstaffed == 0 ? TgcgColors.success : TgcgColors.warning,
                compact: true,
              ),
              TgcgStatusPill(
                label: '$presenceGaps PRESENCE GAPS',
                color: presenceGaps == 0
                    ? TgcgColors.success
                    : TgcgColors.warning,
                compact: true,
              ),
              TgcgStatusPill(
                label: '$gpsAlerts GPS ALERTS',
                color: gpsAlerts == 0 ? TgcgColors.success : TgcgColors.warning,
                compact: true,
              ),
            ],
          ),
          if (snapshots.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...snapshots
                .take(12)
                .map(
                  (snapshot) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: TgcgColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(TgcgRadius.sm),
                      border: Border.all(color: TgcgColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          color: TgcgColors.accentStrong,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                snapshot.unit.displayCode,
                                style: const TextStyle(
                                  color: TgcgColors.ink,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                snapshot.unit.scope.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 9.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        TgcgStatusPill(
                          label:
                              '${snapshot.activeAssignments} / ${snapshot.minimumStaffing} REQUIRED',
                          color: snapshot.isBelowMinimum
                              ? TgcgColors.warning
                              : TgcgColors.info,
                          compact: true,
                        ),
                        const SizedBox(width: 5),
                        TgcgStatusPill(
                          label: '${snapshot.atLocation} PRESENT',
                          color:
                              snapshot.atLocation ==
                                      snapshot.activeAssignments &&
                                  snapshot.activeAssignments > 0
                              ? TgcgColors.success
                              : TgcgColors.warning,
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                ),
            if (snapshots.length > 12)
              Text(
                '+${snapshots.length - 12} additional polling units require attention.',
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: TgcgEmptyState(
                icon: Icons.task_alt_rounded,
                title: 'No coverage gaps',
                message:
                    'Every loaded polling unit in this scope satisfies the current minimum staffing and GPS rules.',
              ),
            ),
        ],
      ),
    );
  }
}

class _AssignmentList extends StatelessWidget {
  const _AssignmentList({
    required this.assignments,
    required this.membership,
    required this.controller,
    required this.canManage,
    required this.authorizedMembers,
    required this.actorId,
    required this.authorizedScope,
    required this.calls,
    required this.session,
    required this.stateCoordinatorScope,
    this.title = 'Deployment assignments',
    this.subtitle =
        'Member duty location, status, managed device and latest geofence presence.',
    this.emptyTitle = 'No assignments in this scope',
    this.emptyMessage =
        'Create an assignment to deploy a member to a polling unit.',
  });

  final String title;
  final String subtitle;
  final String emptyTitle;
  final String emptyMessage;
  final List<MemberAssignment> assignments;
  final MembershipOperationsController membership;
  final AssignmentController controller;
  final bool canManage;
  final List<TgcgMember> authorizedMembers;
  final String actorId;
  final GeographicScope authorizedScope;
  final OperationalCallController calls;
  final TgcgSessionController session;
  final GeographicScope? stateCoordinatorScope;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    title: title,
    subtitle: subtitle,
    child: assignments.isEmpty
        ? TgcgEmptyState(
            icon: Icons.assignment_outlined,
            title: emptyTitle,
            message: emptyMessage,
          )
        : Column(
            children: assignments.map((assignment) {
              final member = membership.memberById(assignment.memberId);
              final presence = controller.presenceFor(assignment);
              final targetUnit = assignment.targetPollingUnitId == null
                  ? null
                  : membership.geography.pollingUnit(
                      assignment.targetPollingUnitId!,
                    );
              final coordinateReady =
                  targetUnit?.operationalLatitude != null &&
                  targetUnit?.operationalLongitude != null;
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 9),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [TgcgColors.surface, TgcgColors.navy50],
                  ),
                  borderRadius: BorderRadius.circular(TgcgRadius.md),
                  border: Border.all(color: TgcgColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: TgcgColors.accent.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(TgcgRadius.sm),
                      ),
                      child: const Icon(
                        Icons.assignment_ind_outlined,
                        color: TgcgColors.accentStrong,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assignment.title,
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${member?.fullName ?? assignment.memberId} • ${assignment.targetScope.label}',
                            style: const TextStyle(
                              color: TgcgColors.muted,
                              fontSize: 10.5,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              TgcgStatusPill(
                                label: _statusLabel(assignment.status),
                                color: _statusColor(assignment.status),
                                compact: true,
                              ),
                              TgcgStatusPill(
                                label: _presenceLabel(presence),
                                color: _presenceColor(presence),
                                compact: true,
                              ),
                              if (targetUnit != null)
                                TgcgStatusPill(
                                  label: coordinateReady
                                      ? 'GPS READY'
                                      : 'GPS MISSING',
                                  color: coordinateReady
                                      ? TgcgColors.success
                                      : TgcgColors.warning,
                                  icon: coordinateReady
                                      ? Icons.gps_fixed_rounded
                                      : Icons.location_off_outlined,
                                  compact: true,
                                ),
                              if (assignment.deviceId != null)
                                TgcgStatusPill(
                                  label: assignment.deviceId!,
                                  color: TgcgColors.info,
                                  icon: Icons.phone_android_outlined,
                                  compact: true,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!assignment.isTerminal &&
                        (canManage || stateCoordinatorScope != null))
                      PopupMenuButton<_AssignmentMenuAction>(
                        tooltip: 'Assignment actions',
                        onSelected: (action) async {
                          if (action == _AssignmentMenuAction.videoCall ||
                              action == _AssignmentMenuAction.audioCall) {
                            final targetMember = membership.memberById(
                              assignment.memberId,
                            );
                            final scope = stateCoordinatorScope;
                            if (targetMember == null || scope == null) {
                              return;
                            }
                            try {
                              await startStateCoordinatorMemberCall(
                                context,
                                calls: calls,
                                session: session,
                                stateScope: scope,
                                member: targetMember,
                                kind: action == _AssignmentMenuAction.audioCall
                                    ? OperationalCallKind.audio
                                    : OperationalCallKind.video,
                                assignmentId: assignment.id,
                              );
                            } on StateError catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.message)),
                              );
                            }
                          } else if (action ==
                              _AssignmentMenuAction.coordinate) {
                            final pollingUnitId =
                                assignment.targetPollingUnitId;
                            if (pollingUnitId == null) return;
                            final unit = membership.geography.pollingUnit(
                              pollingUnitId,
                            );
                            if (unit == null) return;
                            await showPollingUnitCoordinateDialog(
                              context,
                              membership: membership,
                              unit: unit,
                              actorId: actorId,
                              stateScope: stateCoordinatorScope!,
                            );
                          } else if (action == _AssignmentMenuAction.reassign) {
                            await _reassign(context, assignment);
                          } else if (action == _AssignmentMenuAction.cancel) {
                            await _cancel(context, assignment);
                          }
                        },
                        itemBuilder: (context) => [
                          if (stateCoordinatorScope != null) ...[
                            const PopupMenuItem(
                              value: _AssignmentMenuAction.videoCall,
                              child: Row(
                                children: [
                                  Icon(Icons.videocam_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('Video call'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: _AssignmentMenuAction.audioCall,
                              child: Row(
                                children: [
                                  Icon(Icons.call_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('Audio call'),
                                ],
                              ),
                            ),
                            if (assignment.targetPollingUnitId != null)
                              const PopupMenuItem(
                                value: _AssignmentMenuAction.coordinate,
                                child: Row(
                                  children: [
                                    Icon(Icons.gps_fixed_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text('Polling-unit GPS'),
                                  ],
                                ),
                              ),
                          ],
                          if (canManage && !assignment.belongsToGroup) ...[
                            if (stateCoordinatorScope != null)
                              const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: _AssignmentMenuAction.reassign,
                              child: Row(
                                children: [
                                  Icon(Icons.swap_horiz_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Reassign'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: _AssignmentMenuAction.cancel,
                              child: Row(
                                children: [
                                  Icon(Icons.cancel_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('Cancel assignment'),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
  );

  Future<void> _reassign(
    BuildContext context,
    MemberAssignment assignment,
  ) async {
    final candidates = authorizedMembers
        .where((member) => member.id != assignment.memberId)
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other authorized member is available.'),
        ),
      );
      return;
    }

    var selectedMemberId = candidates.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reassign duty'),
          content: SizedBox(
            width: 520,
            child: DropdownButtonFormField<String>(
              initialValue: selectedMemberId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'New member',
                prefixIcon: Icon(Icons.person_search_outlined),
              ),
              items: candidates
                  .map(
                    (member) => DropdownMenuItem(
                      value: member.id,
                      child: Text(
                        '${member.fullName} • ${member.membershipNumber ?? member.id}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setDialogState(() => selectedMemberId = value);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Back'),
            ),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await controller.reassign(
                    assignmentId: assignment.id,
                    newMemberId: selectedMemberId,
                    actorId: actorId,
                    authorizedScope: authorizedScope,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } on StateError catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text(error.message)));
                }
              },
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Reassign'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Assignment reassigned.')));
    }
  }

  Future<void> _cancel(
    BuildContext context,
    MemberAssignment assignment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel assignment?'),
        content: Text(
          'Cancel ${assignment.title} for ${assignment.targetScope.label}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep assignment'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel assignment'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await controller.transition(
        assignmentId: assignment.id,
        status: AssignmentStatus.cancelled,
        actorId: actorId,
        authorizedScope: authorizedScope,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Assignment cancelled.')));
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

enum _AssignmentMenuAction {
  videoCall,
  audioCall,
  coordinate,
  reassign,
  cancel,
}

class _DeviceRegistry extends StatelessWidget {
  const _DeviceRegistry({
    required this.devices,
    required this.visibleDevices,
    required this.membership,
    required this.canManage,
    required this.onRegister,
    required this.onAssign,
  });

  final ManagedDeviceController devices;
  final List<ManagedDevice> visibleDevices;
  final MembershipOperationsController membership;
  final bool canManage;
  final VoidCallback onRegister;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    title: 'Managed phone registry',
    subtitle:
        'Organization-issued phones used for assignment GPS, evidence and field synchronization.',
    trailing: canManage
        ? Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onRegister,
                icon: const Icon(Icons.add_to_home_screen_outlined),
                label: const Text('Register phone'),
              ),
              FilledButton.icon(
                onPressed: onAssign,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Assign phone'),
              ),
            ],
          )
        : null,
    child: visibleDevices.isEmpty
        ? const TgcgEmptyState(
            icon: Icons.phone_android_outlined,
            title: 'No managed phones registered',
            message:
                'Register organization-issued phones before binding them to field members.',
          )
        : Column(
            children: visibleDevices.map((device) {
              final member = device.assignedMemberId == null
                  ? null
                  : membership.memberById(device.assignedMemberId!);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.phone_android_rounded),
                ),
                title: Text(
                  device.label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  device.assignedMemberId == null
                      ? '${device.id} • Available'
                      : '${device.id} • ${member?.fullName ?? device.assignedMemberId}',
                ),
                trailing: TgcgStatusPill(
                  label: device.status.name.toUpperCase(),
                  color: switch (device.status) {
                    ManagedDeviceStatus.available => TgcgColors.info,
                    ManagedDeviceStatus.assigned => TgcgColors.success,
                    ManagedDeviceStatus.maintenance => TgcgColors.warning,
                    ManagedDeviceStatus.revoked => TgcgColors.danger,
                  },
                  compact: true,
                ),
              );
            }).toList(),
          ),
  );
}

String _statusLabel(AssignmentStatus status) => switch (status) {
  AssignmentStatus.assigned => 'ASSIGNED',
  AssignmentStatus.accepted => 'ACCEPTED',
  AssignmentStatus.enRoute => 'EN ROUTE',
  AssignmentStatus.checkedIn => 'CHECKED IN',
  AssignmentStatus.active => 'ACTIVE',
  AssignmentStatus.completed => 'COMPLETED',
  AssignmentStatus.declined => 'DECLINED',
  AssignmentStatus.reassigned => 'REASSIGNED',
  AssignmentStatus.overdue => 'OVERDUE',
  AssignmentStatus.gpsMismatch => 'GPS MISMATCH',
  AssignmentStatus.cancelled => 'CANCELLED',
};

Color _statusColor(AssignmentStatus status) => switch (status) {
  AssignmentStatus.completed ||
  AssignmentStatus.checkedIn ||
  AssignmentStatus.active => TgcgColors.success,
  AssignmentStatus.accepted || AssignmentStatus.enRoute => TgcgColors.info,
  AssignmentStatus.gpsMismatch ||
  AssignmentStatus.overdue ||
  AssignmentStatus.declined => TgcgColors.warning,
  AssignmentStatus.cancelled => TgcgColors.muted,
  AssignmentStatus.assigned ||
  AssignmentStatus.reassigned => TgcgColors.primary,
};

String _presenceLabel(AssignmentPresence presence) => switch (presence) {
  AssignmentPresence.unknown => 'GPS UNKNOWN',
  AssignmentPresence.liveNoGeofence => 'LIVE GPS',
  AssignmentPresence.insideGeofence => 'AT LOCATION',
  AssignmentPresence.outsideGeofence => 'OUTSIDE GEOFENCE',
  AssignmentPresence.stale => 'GPS STALE',
};

Color _presenceColor(AssignmentPresence presence) => switch (presence) {
  AssignmentPresence.unknown => TgcgColors.muted,
  AssignmentPresence.liveNoGeofence => TgcgColors.info,
  AssignmentPresence.insideGeofence => TgcgColors.success,
  AssignmentPresence.outsideGeofence => TgcgColors.warning,
  AssignmentPresence.stale => TgcgColors.warning,
};

enum _RegisterView { group, individual, submitted }

/// Large toggle buttons for the assignment register lists.
class _RegisterTabs extends StatelessWidget {
  const _RegisterTabs({
    required this.selected,
    required this.showGroups,
    required this.groupCount,
    required this.individualCount,
    required this.submittedCount,
    required this.onSelect,
  });

  final _RegisterView selected;
  final bool showGroups;
  final int groupCount;
  final int individualCount;
  final int submittedCount;
  final ValueChanged<_RegisterView> onSelect;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      if (showGroups)
        (
          view: _RegisterView.group,
          icon: Icons.groups_2_outlined,
          label: 'Group assignments',
          detail: 'Teams in progress',
          count: groupCount,
        ),
      (
        view: _RegisterView.individual,
        icon: Icons.person_pin_circle_outlined,
        label: 'Individual assignments',
        detail: 'Open member duties',
        count: individualCount,
      ),
      (
        view: _RegisterView.submitted,
        icon: Icons.task_alt_rounded,
        label: 'Submitted',
        detail: 'Completed and submitted',
        count: submittedCount,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? tabs.length : 1;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tab in tabs)
              SizedBox(
                width: width,
                child: _RegisterTabButton(
                  icon: tab.icon,
                  label: tab.label,
                  detail: tab.detail,
                  count: tab.count,
                  selected: tab.view == selected,
                  onTap: () => onSelect(tab.view),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RegisterTabButton extends StatelessWidget {
  const _RegisterTabButton({
    required this.icon,
    required this.label,
    required this.detail,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TgcgRadius.md),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: selected ? TgcgGradients.brand : null,
          color: selected ? null : TgcgColors.surface,
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          border: Border.all(
            color: selected ? TgcgColors.accent : TgcgColors.border,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected ? TgcgShadows.soft : null,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected
                    ? TgcgColors.accent.withValues(alpha: .18)
                    : TgcgColors.primarySoft,
                borderRadius: BorderRadius.circular(TgcgRadius.sm),
              ),
              child: Icon(
                icon,
                color: selected ? TgcgColors.accent : TgcgColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white70 : TgcgColors.muted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 34),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? TgcgColors.accent : TgcgColors.navy100,
                borderRadius: BorderRadius.circular(TgcgRadius.sm),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? TgcgColors.primaryDark : TgcgColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A completed individual assignment or a chairman-submitted group.
class _SubmittedEntry {
  _SubmittedEntry.individual(MemberAssignment this.assignment)
    : group = null,
      at = assignment.completedAt ?? assignment.assignedAt;

  _SubmittedEntry.group(GroupAssignment this.group)
    : assignment = null,
      at = group.submittedAt ?? group.assignedAt;

  final MemberAssignment? assignment;
  final GroupAssignment? group;
  final DateTime at;
}

class _SubmittedAssignments extends StatelessWidget {
  const _SubmittedAssignments({
    required this.entries,
    required this.membership,
    required this.controller,
  });

  final List<_SubmittedEntry> entries;
  final MembershipOperationsController membership;
  final AssignmentController controller;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    title: 'Submitted assignments',
    subtitle:
        'Completed individual duties and group assignments submitted by their chairman, newest first.',
    child: entries.isEmpty
        ? const TgcgEmptyState(
            icon: Icons.task_alt_rounded,
            title: 'Nothing submitted yet',
            message:
                'Completed individual assignments and submitted group assignments will appear here.',
          )
        : Column(children: [for (final entry in entries) _row(entry)]),
  );

  Widget _row(_SubmittedEntry entry) {
    final group = entry.group;
    final assignment = entry.assignment;
    final String title;
    final String who;
    final String where;
    final int evidence;
    if (group != null) {
      final chairman = membership.memberById(group.chairmanMemberId);
      final children = controller.assignmentsForGroup(group.id);
      title = group.title;
      who =
          'Submitted by ${chairman?.fullName ?? group.submittedBy ?? group.chairmanMemberId} • ${group.memberIds.length} members';
      where = group.targetScopes.map((scope) => scope.label).join(', ');
      evidence = children.fold<int>(
        0,
        (total, item) => total + item.evidence.length,
      );
    } else {
      final item = assignment!;
      final member = membership.memberById(item.memberId);
      final unitId = item.targetPollingUnitId;
      final unit = unitId == null
          ? null
          : membership.geography.pollingUnit(unitId);
      title = item.title;
      who = 'Completed by ${member?.fullName ?? item.memberId}';
      where = unit == null
          ? item.targetScope.label
          : '${unit.displayCode} • ${item.targetScope.label}';
      evidence = item.evidence.length;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: TgcgColors.success.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(TgcgRadius.sm),
            ),
            child: Icon(
              group != null ? Icons.groups_2_outlined : Icons.task_alt_rounded,
              color: TgcgColors.success,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  who,
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  where,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    TgcgStatusPill(
                      label: group != null ? 'GROUP SUBMITTED' : 'COMPLETED',
                      color: TgcgColors.success,
                      compact: true,
                    ),
                    TgcgStatusPill(
                      label: '$evidence EVIDENCE',
                      color: TgcgColors.info,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _submittedTime(entry.at),
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _submittedTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}
