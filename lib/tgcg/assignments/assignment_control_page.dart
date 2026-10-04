import 'package:flutter/material.dart';

import '../devices/managed_device_store.dart';
import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../geography/kaduna_map.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'assignment_store.dart';

class AssignmentControlPage extends StatefulWidget {
  const AssignmentControlPage({super.key});

  @override
  State<AssignmentControlPage> createState() => _AssignmentControlPageState();
}

class _AssignmentControlPageState extends State<AssignmentControlPage> {
  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final devices = ManagedDevices.of(context);
    final assignments = Assignments.of(context);
    final canManageAssignments = TgcgPermissionPolicy.may(
      session.role!,
      session.scope,
      TgcgCapability.manageAssignments,
    );
    final canManageDevices = TgcgPermissionPolicy.may(
      session.role!,
      session.scope,
      TgcgCapability.manageDevices,
    );
    final authorizedUnits = membership.geography.pollingUnits
        .where(
          (unit) =>
              TgcgPermissionPolicy.scopeAllows(session.scope, unit.scope),
        )
        .toList(growable: false);
    final authorizedMembers = membership.members
        .where((member) {
          final scope = membership.registrationScopeForMember(member.id);
          return scope != null &&
              TgcgPermissionPolicy.scopeAllows(session.scope, scope);
        })
        .toList(growable: false);
    final authorizedMemberIds =
        authorizedMembers.map((member) => member.id).toSet();
    final visibleDevices = devices.devices.where((device) {
      if (canManageDevices) return true;
      final memberId = device.assignedMemberId;
      return memberId != null && authorizedMemberIds.contains(memberId);
    }).toList(growable: false);
    final visible = assignments.assignmentsForScope(session.scope);
    final coverage = assignments.coverageForScope(session.scope);
    final gaps = coverage.where((item) => item.needsAttention).toList();
    final staffed =
        coverage.where((item) => !item.isBelowMinimum).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'FIELD DEPLOYMENT',
          title: 'Jobs & Assignment Control',
          subtitle:
              '${session.scope.label}: any registered member can receive an authorized job or temporary field assignment. The assignment is tracked separately and never changes the member\'s permanent home polling unit.',
          trailing: canManageAssignments
              ? Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _setStaffingRequirement(
                        context,
                        assignments,
                        session,
                        authorizedUnits,
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
        _AssignmentCoverageMap(
          snapshots: coverage,
          authorizedUnits: authorizedUnits,
        ),
        const SizedBox(height: 16),
        _CoverageGapPanel(
          snapshots: gaps,
          totalPollingUnits: coverage.length,
          staffedPollingUnits: staffed,
        ),
        const SizedBox(height: 16),
        _AssignmentList(
          assignments: visible,
          membership: membership,
          controller: assignments,
          canManage: canManageAssignments,
          authorizedMembers: authorizedMembers,
          actorId:
              session.accessId.isEmpty ? session.operatorName : session.accessId,
          authorizedScope: session.scope,
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
          ),
        ),
      ],
    );
  }

  Future<void> _setStaffingRequirement(
    BuildContext context,
    AssignmentController assignments,
    TgcgSessionController session,
    List<CanonicalPollingUnit> authorizedUnits,
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
                      .fold<Map<String, String>>(
                        <String, String>{},
                        (map, scope) {
                          if (lgaIds.contains(scope.lgaId)) {
                            map[scope.lgaId!] = scope.lgaName ?? scope.lgaId!;
                          }
                          return map;
                        },
                      )
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
                      minimum =
                          assignments.minimumStaffingFor(pollingUnitId);
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
                      minimum =
                          assignments.minimumStaffingFor(pollingUnitId);
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
                        borderRadius:
                            BorderRadius.circular(TgcgRadius.sm),
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
                  authorizedScope: session.scope,
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

    String? lgaId =
        authorizedLgas.isEmpty ? null : authorizedLgas.first.id;
    var units = lgaId == null
        ? const <CanonicalPollingUnit>[]
        : authorizedUnits
            .where((unit) => unit.scope.lgaId == lgaId)
            .toList(growable: false);
    String? pollingUnitId = units.isEmpty ? null : units.first.code;
    var locationBound = authorizedLgas.isNotEmpty;
    var priority = AssignmentPriority.normal;
    final selectedCapabilities = <TgcgCapability>{};
    final availableCapabilities =
        _assignmentGrantOptionsFor(session.role!);
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
                        pollingUnitId =
                            units.isEmpty ? null : units.first.code;
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
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AssignmentPriority>(
                    initialValue: priority,
                    decoration:
                        const InputDecoration(labelText: 'Priority'),
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
                    decoration:
                        const InputDecoration(labelText: 'Job / assignment title'),
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
                            final selected =
                                selectedCapabilities.contains(capability);
                            return FilterChip(
                              selected: selected,
                              label: Text(_assignmentCapabilityLabel(capability)),
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
                        await assignments.createAssignment(
                          title: title.text,
                          memberId: memberId,
                          pollingUnitId:
                              locationBound ? pollingUnitId : null,
                          assignedBy: session.accessId.isEmpty
                              ? session.operatorName
                              : session.accessId,
                          authorizedScope: session.scope,
                          priority: priority,
                          instructions: instructions.text,
                          grantedCapabilities:
                              Set.unmodifiable(selectedCapabilities),
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } on StateError catch (error) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(error.message)),
                        );
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
        const SnackBar(content: Text('Member assignment created and queued for sync.')),
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
                    authorizedScope: session.scope,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } on StateError catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(error.message)),
                  );
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

List<TgcgCapability> _assignmentGrantOptionsFor(TgcgRole role) {
  const grantable = <TgcgCapability>[
    TgcgCapability.viewGeography,
    TgcgCapability.viewIncidents,
    TgcgCapability.createIncident,
    TgcgCapability.submitFieldReport,
    TgcgCapability.viewCommunications,
    TgcgCapability.sendOperationalMessage,
    TgcgCapability.viewMediaIntelligence,
    TgcgCapability.viewDiscussionRoom,
    TgcgCapability.createDiscussionThread,
    TgcgCapability.postDiscussionReply,
    TgcgCapability.viewMeetingRoom,
    TgcgCapability.startMeeting,
    TgcgCapability.joinMeeting,
    TgcgCapability.viewEvidence,
  ];
  final own = TgcgPermissionPolicy.capabilitiesFor(role);
  return grantable.where(own.contains).toList(growable: false);
}

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

class _AssignmentCoverageMap extends StatelessWidget {
  const _AssignmentCoverageMap({
    required this.snapshots,
    required this.authorizedUnits,
  });

  final List<PollingUnitCoverageSnapshot> snapshots;
  final List<CanonicalPollingUnit> authorizedUnits;

  @override
  Widget build(BuildContext context) {
    final authorizedLgas = authorizedUnits
        .map((unit) => unit.scope.lgaId)
        .whereType<String>()
        .toSet();
    final byLga = <String, List<PollingUnitCoverageSnapshot>>{};
    for (final snapshot in snapshots) {
      final lgaId = snapshot.unit.scope.lgaId;
      if (lgaId == null) continue;
      byLga.putIfAbsent(lgaId, () => []).add(snapshot);
    }

    Color fill(String lgaId) {
      if (!authorizedLgas.contains(lgaId)) {
        return TgcgColors.navy100;
      }
      final items = byLga[lgaId] ?? const <PollingUnitCoverageSnapshot>[];
      if (items.isEmpty) return TgcgColors.navy700;
      final critical = items.any(
        (item) => item.isUnstaffed || item.hasGpsAlert,
      );
      if (critical) return TgcgColors.danger;
      final gaps = items.any((item) => item.needsAttention);
      if (gaps) return TgcgColors.warning;
      return TgcgColors.success;
    }

    String? badge(String lgaId) {
      final items = byLga[lgaId];
      if (items == null || items.isEmpty) return null;
      final present =
          items.fold<int>(0, (total, item) => total + item.atLocation);
      final required =
          items.fold<int>(0, (total, item) => total + item.minimumStaffing);
      return '$present/$required present';
    }

    return TgcgSectionCard(
      title: 'Kaduna Assignment Readiness Map',
      subtitle:
          'LGA-level view of polling-unit staffing requirements and fresh GPS presence.',
      trailing: const Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          TgcgStatusPill(
            label: 'READY',
            color: TgcgColors.success,
            compact: true,
          ),
          TgcgStatusPill(
            label: 'GAP',
            color: TgcgColors.warning,
            compact: true,
          ),
          TgcgStatusPill(
            label: 'CRITICAL / GPS',
            color: TgcgColors.danger,
            compact: true,
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: KadunaMap(
            fillColor: fill,
            badge: badge,
          ),
        ),
      ),
    );
  }
}

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
    final presenceGaps =
        snapshots.where((item) => item.hasPresenceGap).length;
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
                color: unstaffed == 0
                    ? TgcgColors.success
                    : TgcgColors.warning,
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
                color: gpsAlerts == 0
                    ? TgcgColors.success
                    : TgcgColors.warning,
                compact: true,
              ),
            ],
          ),
          if (snapshots.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...snapshots.take(12).map(
                  (snapshot) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: TgcgColors.surfaceRaised,
                      borderRadius:
                          BorderRadius.circular(TgcgRadius.sm),
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
                          color: snapshot.atLocation ==
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
  });

  final List<MemberAssignment> assignments;
  final MembershipOperationsController membership;
  final AssignmentController controller;
  final bool canManage;
  final List<TgcgMember> authorizedMembers;
  final String actorId;
  final GeographicScope authorizedScope;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Deployment assignments',
        subtitle:
            'Member duty location, status, managed device and latest geofence presence.',
        child: assignments.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.assignment_outlined,
                title: 'No assignments in this scope',
                message:
                    'Create an assignment to deploy a member to a polling unit.',
              )
            : Column(
                children: assignments.map((assignment) {
                  final member = membership.memberById(assignment.memberId);
                  final presence = controller.presenceFor(assignment);
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
                            borderRadius:
                                BorderRadius.circular(TgcgRadius.sm),
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
                        if (canManage && !assignment.isTerminal)
                          PopupMenuButton<_AssignmentMenuAction>(
                            tooltip: 'Assignment actions',
                            onSelected: (action) async {
                              if (action == _AssignmentMenuAction.reassign) {
                                await _reassign(context, assignment);
                              } else if (action ==
                                  _AssignmentMenuAction.cancel) {
                                await _cancel(context, assignment);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: _AssignmentMenuAction.reassign,
                                child: Row(
                                  children: [
                                    Icon(Icons.swap_horiz_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text('Reassign'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
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
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(error.message)),
                  );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assignment reassigned.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assignment cancelled.')),
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }
}

enum _AssignmentMenuAction {
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
                        ManagedDeviceStatus.maintenance =>
                          TgcgColors.warning,
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
      AssignmentStatus.accepted || AssignmentStatus.enRoute =>
        TgcgColors.info,
      AssignmentStatus.gpsMismatch ||
      AssignmentStatus.overdue ||
      AssignmentStatus.declined => TgcgColors.warning,
      AssignmentStatus.cancelled => TgcgColors.muted,
      AssignmentStatus.assigned || AssignmentStatus.reassigned =>
        TgcgColors.primary,
    };

String _presenceLabel(AssignmentPresence presence) => switch (presence) {
      AssignmentPresence.unknown => 'GPS UNKNOWN',
      AssignmentPresence.insideGeofence => 'AT LOCATION',
      AssignmentPresence.outsideGeofence => 'OUTSIDE GEOFENCE',
      AssignmentPresence.stale => 'GPS STALE',
    };

Color _presenceColor(AssignmentPresence presence) => switch (presence) {
      AssignmentPresence.unknown => TgcgColors.muted,
      AssignmentPresence.insideGeofence => TgcgColors.success,
      AssignmentPresence.outsideGeofence => TgcgColors.warning,
      AssignmentPresence.stale => TgcgColors.warning,
    };
