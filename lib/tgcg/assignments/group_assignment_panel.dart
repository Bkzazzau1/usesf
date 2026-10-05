import 'package:flutter/material.dart';

import '../access/access_policy.dart';
import '../access/effective_member_access.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'assignment_store.dart';

class GroupAssignmentPanel extends StatelessWidget {
  const GroupAssignmentPanel({
    super.key,
    required this.controller,
    required this.membership,
    required this.onCreate,
  });

  final AssignmentController controller;
  final MembershipOperationsController membership;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final groups = controller.groupAssignments;
    return TgcgSectionCard(
      title: 'Group assignments',
      trailing: FilledButton.tonalIcon(
        onPressed: onCreate,
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('New group'),
      ),
      child: groups.isEmpty
          ? const SizedBox.shrink()
          : Column(
              children: groups.take(12).map((group) {
                final children = controller.assignmentsForGroup(group.id);
                final freshGps = children.where((assignment) {
                  final ping = assignment.lastLocation;
                  if (ping == null) return false;
                  return DateTime.now()
                          .toUtc()
                          .difference(ping.capturedAt)
                          .abs() <=
                      const Duration(minutes: 7);
                }).length;
                final chairman =
                    membership.memberById(group.chairmanMemberId);
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
                          color: TgcgColors.primarySoft,
                          borderRadius:
                              BorderRadius.circular(TgcgRadius.sm),
                        ),
                        child: const Icon(
                          Icons.groups_2_outlined,
                          color: TgcgColors.primary,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.title,
                              style: const TextStyle(
                                color: TgcgColors.ink,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              chairman?.fullName ?? group.chairmanMemberId,
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
                                  label: _groupStatusLabel(group.status),
                                  color: _groupStatusColor(group.status),
                                  compact: true,
                                ),
                                TgcgStatusPill(
                                  label:
                                      '${group.memberIds.length} MEMBERS',
                                  color: TgcgColors.info,
                                  compact: true,
                                ),
                                TgcgStatusPill(
                                  label:
                                      '${group.targetScopes.length} TARGETS',
                                  color: TgcgColors.accentStrong,
                                  compact: true,
                                ),
                                TgcgStatusPill(
                                  label: '$freshGps GPS',
                                  color: freshGps == group.memberIds.length &&
                                          group.memberIds.isNotEmpty
                                      ? TgcgColors.success
                                      : TgcgColors.warning,
                                  compact: true,
                                ),
                                TgcgStatusPill(
                                  label:
                                      _distributionLabel(group.distribution)
                                          .toUpperCase(),
                                  color: TgcgColors.muted,
                                  compact: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

Future<bool> showGroupAssignmentDialog({
  required BuildContext context,
  required MembershipOperationsController membership,
  required AssignmentController assignments,
  required TgcgSessionController session,
  required List<TgcgMember> authorizedMembers,
  required List<CanonicalPollingUnit> authorizedUnits,
  required List<GeographicScope> assignmentScopes,
}) async {
  if (authorizedMembers.isEmpty || authorizedUnits.isEmpty) return false;

  final role = TgcgAccessPolicy.roleFor(
    context,
    TgcgCapability.manageAssignments,
    targetScope: GeographicScope.kaduna,
    listen: false,
  );
  if (role != TgcgRole.stateCoordinator) {
    throw StateError('Only the State Coordinator can create group assignments.');
  }

  final authorizedScope = assignmentScopes.firstWhere(
    (scope) =>
        scope.level == GeographyLevel.state && scope.stateId == 'KD',
    orElse: () => GeographicScope.kaduna,
  );

  final title = TextEditingController(text: 'Group Field Assignment');
  final instructions = TextEditingController();
  final searchTargets = TextEditingController();
  final searchMembers = TextEditingController();

  var areaLevel = _GroupAreaLevel.lga;
  var memberMode = _GroupMemberMode.manual;
  var distribution = GroupAssignmentDistribution.together;
  var priority = AssignmentPriority.normal;
  var automaticChairman = true;
  String? chairmanMemberId;
  final selectedTargetKeys = <String>{};
  final selectedMemberIds = <String>{};
  final manualTargetByMember = <String, String>{};
  final selectedCapabilities = <TgcgCapability>{};

  List<_AreaOption> targetOptions() => _groupAreaOptions(
        level: areaLevel,
        geography: membership.geography,
        authorizedUnits: authorizedUnits,
      );

  List<GeographicScope> selectedTargets() {
    final options = targetOptions();
    return options
        .where((option) => selectedTargetKeys.contains(option.key))
        .map((option) => option.scope)
        .toList(growable: false);
  }

  List<String> effectiveMembers() {
    if (memberMode == _GroupMemberMode.manual) {
      return authorizedMembers
          .where((member) => selectedMemberIds.contains(member.id))
          .map((member) => member.id)
          .toList(growable: false);
    }
    final targets = selectedTargets();
    return authorizedMembers.where((member) {
      final scope = membership.registrationScopeForMember(member.id);
      if (scope == null) return false;
      return targets.any(
        (target) => GeographyRegistry.scopeContains(target, scope),
      );
    }).map((member) => member.id).toList(growable: false);
  }

  final delegable = _groupDelegableCapabilities(
    context,
    session,
    authorizedScope,
  );
  final capabilityOptions = assignmentGrantableCapabilities
      .where(delegable.contains)
      .where(
        (capability) =>
            !groupAssignmentRestrictedCapabilities.contains(capability),
      )
      .toList(growable: false);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final options = targetOptions();
        final targetNeedle = searchTargets.text.trim().toLowerCase();
        final visibleTargets = options.where((option) {
          if (targetNeedle.isEmpty) return true;
          return option.label.toLowerCase().contains(targetNeedle);
        }).toList(growable: false);

        final memberNeedle = searchMembers.text.trim().toLowerCase();
        final visibleMembers = authorizedMembers.where((member) {
          if (memberNeedle.isEmpty) return true;
          return member.fullName.toLowerCase().contains(memberNeedle) ||
              (member.membershipNumber ?? '')
                  .toLowerCase()
                  .contains(memberNeedle) ||
              member.phoneNumber.toLowerCase().contains(memberNeedle);
        }).toList(growable: false);

        final members = effectiveMembers();
        if (!automaticChairman &&
            chairmanMemberId != null &&
            !members.contains(chairmanMemberId)) {
          chairmanMemberId = null;
        }

        if (distribution == GroupAssignmentDistribution.manual &&
            selectedTargetKeys.isNotEmpty) {
          final firstTarget = selectedTargetKeys.first;
          for (final memberId in members) {
            manualTargetByMember.putIfAbsent(memberId, () => firstTarget);
          }
          manualTargetByMember.removeWhere(
            (memberId, _) => !members.contains(memberId),
          );
        }

        final canCreate =
            title.text.trim().isNotEmpty &&
            members.isNotEmpty &&
            selectedTargetKeys.isNotEmpty &&
            (automaticChairman ||
                (chairmanMemberId != null &&
                    members.contains(chairmanMemberId))) &&
            (distribution != GroupAssignmentDistribution.manual ||
                members.every(
                  (memberId) =>
                      manualTargetByMember[memberId] != null &&
                      selectedTargetKeys
                          .contains(manualTargetByMember[memberId]),
                ));

        return AlertDialog(
          title: const Text('Create group assignment'),
          content: SizedBox(
            width: 820,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    onChanged: (_) => setDialogState(() {}),
                    decoration:
                        const InputDecoration(labelText: 'Assignment title'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<GroupAssignmentDistribution>(
                    initialValue: distribution,
                    decoration:
                        const InputDecoration(labelText: 'Movement mode'),
                    items: GroupAssignmentDistribution.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(_distributionLabel(item)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      distribution = value ?? distribution;
                    }),
                  ),
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
                    onChanged: (value) => setDialogState(() {
                      priority = value ?? priority;
                    }),
                  ),
                  const SizedBox(height: 18),
                  const _DialogHeading('Targets'),
                  const SizedBox(height: 8),
                  SegmentedButton<_GroupAreaLevel>(
                    segments: const [
                      ButtonSegment(
                        value: _GroupAreaLevel.lga,
                        label: Text('LGA'),
                      ),
                      ButtonSegment(
                        value: _GroupAreaLevel.ward,
                        label: Text('Ward'),
                      ),
                      ButtonSegment(
                        value: _GroupAreaLevel.pollingUnit,
                        label: Text('Polling unit'),
                      ),
                    ],
                    selected: {areaLevel},
                    onSelectionChanged: (value) => setDialogState(() {
                      areaLevel = value.first;
                      selectedTargetKeys.clear();
                      manualTargetByMember.clear();
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchTargets,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Search targets',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 190,
                    child: ListView.builder(
                      itemCount: visibleTargets.length,
                      itemBuilder: (context, index) {
                        final option = visibleTargets[index];
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selectedTargetKeys.contains(option.key),
                          title: Text(option.label),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              selectedTargetKeys.add(option.key);
                            } else {
                              selectedTargetKeys.remove(option.key);
                              manualTargetByMember.removeWhere(
                                (_, targetKey) => targetKey == option.key,
                              );
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _DialogHeading('Members'),
                  const SizedBox(height: 8),
                  SegmentedButton<_GroupMemberMode>(
                    segments: const [
                      ButtonSegment(
                        value: _GroupMemberMode.manual,
                        label: Text('Manual'),
                      ),
                      ButtonSegment(
                        value: _GroupMemberMode.targetGeography,
                        label: Text('By geography'),
                      ),
                    ],
                    selected: {memberMode},
                    onSelectionChanged: (value) => setDialogState(() {
                      memberMode = value.first;
                      manualTargetByMember.clear();
                    }),
                  ),
                  if (memberMode == _GroupMemberMode.manual) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchMembers,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Search members',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 210,
                      child: ListView.builder(
                        itemCount: visibleMembers.length,
                        itemBuilder: (context, index) {
                          final member = visibleMembers[index];
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: selectedMemberIds.contains(member.id),
                            title: Text(member.fullName),
                            secondary: Text(
                              member.membershipNumber ?? member.id,
                              style: const TextStyle(fontSize: 10),
                            ),
                            onChanged: (value) => setDialogState(() {
                              if (value == true) {
                                selectedMemberIds.add(member.id);
                              } else {
                                selectedMemberIds.remove(member.id);
                                manualTargetByMember.remove(member.id);
                              }
                            }),
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TgcgStatusPill(
                        label: '${members.length} MEMBERS',
                        color: TgcgColors.info,
                        compact: true,
                      ),
                    ),
                  ],
                  if (distribution == GroupAssignmentDistribution.manual &&
                      members.isNotEmpty &&
                      selectedTargetKeys.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const _DialogHeading('Member targets'),
                    const SizedBox(height: 8),
                    ...members.map((memberId) {
                      final member = membership.memberById(memberId);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('group-target-$memberId'),
                          initialValue: manualTargetByMember[memberId],
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: member?.fullName ?? memberId,
                          ),
                          items: options
                              .where(
                                (option) =>
                                    selectedTargetKeys.contains(option.key),
                              )
                              .map(
                                (option) => DropdownMenuItem(
                                  value: option.key,
                                  child: Text(
                                    option.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setDialogState(() {
                            if (value != null) {
                              manualTargetByMember[memberId] = value;
                            }
                          }),
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 18),
                  const _DialogHeading('Chairman'),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: automaticChairman,
                    title: const Text('Automatic chairman'),
                    onChanged: (value) => setDialogState(() {
                      automaticChairman = value;
                      if (value) chairmanMemberId = null;
                    }),
                  ),
                  if (!automaticChairman)
                    DropdownButtonFormField<String>(
                      initialValue: chairmanMemberId,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Group chairman'),
                      items: members.map((memberId) {
                        final member = membership.memberById(memberId);
                        return DropdownMenuItem(
                          value: memberId,
                          child: Text(
                            member?.fullName ?? memberId,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) => setDialogState(() {
                        chairmanMemberId = value;
                      }),
                    ),
                  const SizedBox(height: 18),
                  const _DialogHeading('Temporary access'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: capabilityOptions.map((capability) {
                      return FilterChip(
                        selected:
                            selectedCapabilities.contains(capability),
                        label: Text(_capabilityLabel(capability)),
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: instructions,
                    minLines: 2,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(labelText: 'Instructions'),
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
              onPressed: !canCreate
                  ? null
                  : () async {
                      try {
                        final currentOptions = {
                          for (final option in targetOptions())
                            option.key: option.scope,
                        };
                        final manualTargets =
                            <String, GeographicScope>{};
                        if (distribution ==
                            GroupAssignmentDistribution.manual) {
                          for (final memberId in members) {
                            final key = manualTargetByMember[memberId];
                            final scope =
                                key == null ? null : currentOptions[key];
                            if (scope != null) {
                              manualTargets[memberId] = scope;
                            }
                          }
                        }

                        await assignments.createGroupAssignment(
                          title: title.text,
                          memberIds: members,
                          targetScopes: selectedTargets(),
                          distribution: distribution,
                          assignedBy: session.accessId.isEmpty
                              ? session.operatorName
                              : session.accessId,
                          assignedByRole: role,
                          authorizedScope: authorizedScope,
                          chairmanMemberId:
                              automaticChairman ? null : chairmanMemberId,
                          manualTargetsByMember: manualTargets,
                          priority: priority,
                          instructions: instructions.text,
                          grantedCapabilities:
                              Set.unmodifiable(selectedCapabilities),
                          assignerCapabilities: delegable,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } on StateError catch (error) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(error.message)),
                        );
                      } on ArgumentError catch (error) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(error.message.toString())),
                        );
                      }
                    },
              icon: const Icon(Icons.groups_2_outlined),
              label: const Text('Create group'),
            ),
          ],
        );
      },
    ),
  );

  title.dispose();
  instructions.dispose();
  searchTargets.dispose();
  searchMembers.dispose();
  return result == true;
}

enum _GroupAreaLevel { lga, ward, pollingUnit }

enum _GroupMemberMode { manual, targetGeography }

class _AreaOption {
  const _AreaOption({
    required this.key,
    required this.label,
    required this.scope,
  });

  final String key;
  final String label;
  final GeographicScope scope;
}

class _DialogHeading extends StatelessWidget {
  const _DialogHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: TgcgColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      );
}

List<_AreaOption> _groupAreaOptions({
  required _GroupAreaLevel level,
  required GeographyRegistry geography,
  required List<CanonicalPollingUnit> authorizedUnits,
}) {
  switch (level) {
    case _GroupAreaLevel.lga:
      final lgaIds = authorizedUnits
          .map((unit) => unit.scope.lgaId)
          .whereType<String>()
          .toSet();
      final values = geography.lgas
          .where((lga) => lgaIds.contains(lga.id))
          .map(
            (lga) => _AreaOption(
              key: _scopeKey(lga.scope),
              label: lga.name,
              scope: lga.scope,
            ),
          )
          .toList();
      values.sort((a, b) => a.label.compareTo(b.label));
      return values;
    case _GroupAreaLevel.ward:
      final values = <String, _AreaOption>{};
      for (final unit in authorizedUnits) {
        final scope = unit.scope;
        if (scope.wardId == null) continue;
        final ward = GeographicScope(
          level: GeographyLevel.ward,
          country: scope.country,
          zoneId: scope.zoneId,
          zoneName: scope.zoneName,
          stateId: scope.stateId,
          stateName: scope.stateName,
          senatorialDistrictId: scope.senatorialDistrictId,
          senatorialDistrictName: scope.senatorialDistrictName,
          lgaId: scope.lgaId,
          lgaName: scope.lgaName,
          wardId: scope.wardId,
          wardName: scope.wardName,
        );
        values[_scopeKey(ward)] = _AreaOption(
          key: _scopeKey(ward),
          label: '${scope.wardName ?? scope.wardId} • ${scope.lgaName ?? ''}',
          scope: ward,
        );
      }
      final result = values.values.toList();
      result.sort((a, b) => a.label.compareTo(b.label));
      return result;
    case _GroupAreaLevel.pollingUnit:
      final result = authorizedUnits
          .map(
            (unit) => _AreaOption(
              key: _scopeKey(unit.scope),
              label:
                  '${unit.displayCode} • ${unit.scope.wardName ?? ''} • ${unit.scope.lgaName ?? ''}',
              scope: unit.scope,
            ),
          )
          .toList();
      result.sort((a, b) => a.label.compareTo(b.label));
      return result;
  }
}

Set<TgcgCapability> _groupDelegableCapabilities(
  BuildContext context,
  TgcgSessionController session,
  GeographicScope within,
) {
  final member = TgcgAccessPolicy.memberAccess(context, listen: false);
  if (member == null) {
    final role = session.role;
    if (role == null ||
        !TgcgPermissionPolicy.scopeAllows(session.scope, within)) {
      return const {};
    }
    return TgcgPermissionPolicy.capabilitiesFor(role);
  }
  return member.grants
      .where((grant) => grant.source == EffectiveGrantSource.role)
      .where(
        (grant) =>
            TgcgPermissionPolicy.scopeAllows(grant.scope, within),
      )
      .expand((grant) => grant.capabilities)
      .toSet();
}

String _scopeKey(GeographicScope scope) =>
    '${scope.level.name}:${scope.stateId ?? ''}:'
    '${scope.senatorialDistrictId ?? ''}:${scope.lgaId ?? ''}:'
    '${scope.wardId ?? ''}:${scope.pollingUnitId ?? ''}';

String _distributionLabel(GroupAssignmentDistribution distribution) =>
    switch (distribution) {
      GroupAssignmentDistribution.together => 'Move together',
      GroupAssignmentDistribution.manual => 'Manual distribution',
      GroupAssignmentDistribution.automatic => 'Automatic distribution',
    };

String _groupStatusLabel(GroupAssignmentStatus status) => switch (status) {
      GroupAssignmentStatus.assigned => 'ASSIGNED',
      GroupAssignmentStatus.active => 'ACTIVE',
      GroupAssignmentStatus.submitted => 'SUBMITTED',
      GroupAssignmentStatus.cancelled => 'CANCELLED',
    };

Color _groupStatusColor(GroupAssignmentStatus status) => switch (status) {
      GroupAssignmentStatus.assigned => TgcgColors.info,
      GroupAssignmentStatus.active => TgcgColors.success,
      GroupAssignmentStatus.submitted => TgcgColors.success,
      GroupAssignmentStatus.cancelled => TgcgColors.muted,
    };

String _capabilityLabel(TgcgCapability capability) => switch (capability) {
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
