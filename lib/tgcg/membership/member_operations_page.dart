import 'package:flutter/material.dart';

import '../assignments/assignment_store.dart';
import '../devices/managed_device_store.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'membership_store.dart';

class MemberOperationsPage extends StatefulWidget {
  const MemberOperationsPage({
    super.key,
    required this.onOpenModule,
  });

  final ValueChanged<TgcgModule> onOpenModule;

  @override
  State<MemberOperationsPage> createState() => _MemberOperationsPageState();
}

class _MemberOperationsPageState extends State<MemberOperationsPage> {
  String query = '';
  String? selectedMemberId;
  _MemberFilter filter = _MemberFilter.all;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final assignments = Assignments.of(context);
    final devices = ManagedDevices.of(context);

    final visibleMembers = membership.members.where((member) {
      final scope = membership.registrationScopeForMember(member.id);
      if (scope == null) return false;
      if (!TgcgPermissionPolicy.scopeAllows(session.scope, scope)) return false;

      final active = assignments.activeAssignmentsForMember(member.id);
      final managedDevice = devices.deviceForMember(member.id);
      final homePu = membership.homePollingUnitForMember(member.id);

      final matchesFilter = switch (filter) {
        _MemberFilter.all => true,
        _MemberFilter.unassigned => active.isEmpty,
        _MemberFilter.assigned => active.isNotEmpty,
        _MemberFilter.atLocation => active.any(
            (item) =>
                assignments.presenceFor(item) ==
                AssignmentPresence.insideGeofence,
          ),
        _MemberFilter.noDevice => managedDevice == null,
        _MemberFilter.noHomePollingUnit => homePu == null,
      };
      if (!matchesFilter) return false;

      final needle = query.trim().toLowerCase();
      if (needle.isEmpty) return true;
      return member.fullName.toLowerCase().contains(needle) ||
          member.phoneNumber.toLowerCase().contains(needle) ||
          (member.email ?? '').toLowerCase().contains(needle) ||
          (member.membershipNumber ?? '').toLowerCase().contains(needle) ||
          (homePu?.displayCode.toLowerCase().contains(needle) ?? false) ||
          (homePu?.scope.label.toLowerCase().contains(needle) ?? false);
    }).toList(growable: false);

    if (visibleMembers.isNotEmpty &&
        !visibleMembers.any((member) => member.id == selectedMemberId)) {
      selectedMemberId = visibleMembers.first.id;
    }
    final selectedMember = selectedMemberId == null
        ? null
        : membership.memberById(selectedMemberId!);

    final scopedMembers = membership.members.where((member) {
      final scope = membership.registrationScopeForMember(member.id);
      return scope != null &&
          TgcgPermissionPolicy.scopeAllows(session.scope, scope);
    }).toList(growable: false);
    final scopedMemberIds = scopedMembers.map((member) => member.id).toSet();
    final scopedAssignments = assignments.assignments
        .where((item) => scopedMemberIds.contains(item.memberId))
        .toList(growable: false);
    final activeAssignments =
        scopedAssignments.where((item) => !item.isTerminal).toList(growable: false);
    final presentMembers = activeAssignments
        .where(
          (item) =>
              assignments.presenceFor(item) ==
              AssignmentPresence.insideGeofence,
        )
        .map((item) => item.memberId)
        .toSet()
        .length;
    final homeLinked = scopedMembers
        .where((member) => membership.homePollingUnitForMember(member.id) != null)
        .length;
    final deviceBound = scopedMembers
        .where((member) => devices.deviceForMember(member.id) != null)
        .length;

    final canAssign = TgcgPermissionPolicy.may(
      session.role!,
      session.scope,
      TgcgCapability.manageAgentAssignments,
    );
    final canEnroll = TgcgPermissionPolicy.may(
      session.role!,
      session.scope,
      TgcgCapability.manageMembership,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'ONE MEMBER REGISTRY',
          title: 'Member Operations',
          subtitle:
              '${session.scope.label}: every person follows the same enrolment process. Jobs, field duties and temporary deployment are attached later as assignments without creating a second member identity.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canEnroll)
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.onOpenModule(TgcgModule.accreditation),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Enrol member'),
                ),
              if (canAssign)
                FilledButton.icon(
                  onPressed: () =>
                      widget.onOpenModule(TgcgModule.assignmentControl),
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('Assign job'),
                ),
            ],
          ),
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
                  label: 'Members',
                  value: '${scopedMembers.length}',
                  detail: 'Single identity registry',
                  icon: Icons.groups_2_outlined,
                  tone: TgcgMetricTone.info,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Home PU linked',
                  value: '$homeLinked',
                  detail:
                      '${scopedMembers.length - homeLinked} still require linkage',
                  icon: Icons.home_work_outlined,
                  tone: homeLinked == scopedMembers.length &&
                          scopedMembers.isNotEmpty
                      ? TgcgMetricTone.success
                      : TgcgMetricTone.warning,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Active assignments',
                  value: '${activeAssignments.length}',
                  detail: 'Jobs currently open',
                  icon: Icons.assignment_turned_in_outlined,
                  tone: TgcgMetricTone.success,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Members present',
                  value: '$presentMembers',
                  detail: 'Fresh GPS inside assignment geofence',
                  icon: Icons.gps_fixed_rounded,
                  tone: TgcgMetricTone.success,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Managed phones',
                  value: '$deviceBound',
                  detail:
                      '${scopedMembers.length - deviceBound} members without a bound device',
                  icon: Icons.phone_android_rounded,
                  tone: TgcgMetricTone.neutral,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _MemberFilterBar(
          query: query,
          filter: filter,
          onQueryChanged: (value) => setState(() => query = value),
          onFilterChanged: (value) => setState(() => filter = value),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final directory = _MemberDirectory(
              members: visibleMembers,
              selectedMemberId: selectedMemberId,
              membership: membership,
              assignments: assignments,
              devices: devices,
              onSelect: (value) =>
                  setState(() => selectedMemberId = value),
            );
            final inspector = _MemberInspector(
              member: selectedMember,
              membership: membership,
              assignments: assignments,
              devices: devices,
              canAssign: canAssign,
              onOpenAssignments: () =>
                  widget.onOpenModule(TgcgModule.assignmentControl),
            );

            if (constraints.maxWidth < 1080) {
              return Column(
                children: [
                  directory,
                  const SizedBox(height: 14),
                  inspector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: directory),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: inspector),
              ],
            );
          },
        ),
      ],
    );
  }
}

enum _MemberFilter {
  all,
  unassigned,
  assigned,
  atLocation,
  noDevice,
  noHomePollingUnit,
}

class _MemberFilterBar extends StatelessWidget {
  const _MemberFilterBar({
    required this.query,
    required this.filter,
    required this.onQueryChanged,
    required this.onFilterChanged,
  });

  final String query;
  final _MemberFilter filter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_MemberFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final search = TextField(
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                labelText: 'Search members',
                hintText: 'Name, phone, membership number or polling unit',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            );
            final filters = Wrap(
              spacing: 7,
              runSpacing: 7,
              children: _MemberFilter.values
                  .map(
                    (item) => ChoiceChip(
                      selected: item == filter,
                      label: Text(_filterLabel(item)),
                      onSelected: (_) => onFilterChanged(item),
                    ),
                  )
                  .toList(),
            );

            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: 10),
                  filters,
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 5, child: search),
                const SizedBox(width: 12),
                Expanded(flex: 6, child: filters),
              ],
            );
          },
        ),
      );
}

class _MemberDirectory extends StatelessWidget {
  const _MemberDirectory({
    required this.members,
    required this.selectedMemberId,
    required this.membership,
    required this.assignments,
    required this.devices,
    required this.onSelect,
  });

  final List<TgcgMember> members;
  final String? selectedMemberId;
  final MembershipOperationsController membership;
  final AssignmentController assignments;
  final ManagedDeviceController devices;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Member directory',
        subtitle:
            'All registered members can receive jobs or temporary assignments. Home polling unit remains a permanent identity attribute.',
        trailing: TgcgStatusPill(
          label: '${members.length} SHOWN',
          color: TgcgColors.info,
          compact: true,
        ),
        child: members.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.person_search_outlined,
                title: 'No matching members',
                message: 'Change the search or member-status filter.',
              )
            : Column(
                children: members.map((member) {
                  final active =
                      assignments.activeAssignmentsForMember(member.id);
                  final homePu =
                      membership.homePollingUnitForMember(member.id);
                  final device = devices.deviceForMember(member.id);
                  final atLocation = active.any(
                    (item) =>
                        assignments.presenceFor(item) ==
                        AssignmentPresence.insideGeofence,
                  );
                  final selected = member.id == selectedMemberId;

                  return InkWell(
                    onTap: () => onSelect(member.id),
                    borderRadius: BorderRadius.circular(TgcgRadius.md),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: selected
                            ? TgcgColors.primarySoft
                            : TgcgColors.surfaceSoft,
                        borderRadius:
                            BorderRadius.circular(TgcgRadius.md),
                        border: Border.all(
                          color: selected
                              ? TgcgColors.primary.withValues(alpha: .30)
                              : TgcgColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: TgcgColors.navy100,
                            foregroundColor: TgcgColors.primary,
                            child: Text(
                              member.fullName.isEmpty
                                  ? '?'
                                  : member.fullName[0].toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: TgcgColors.ink,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${member.membershipNumber ?? member.id} • ${homePu?.displayCode ?? 'HOME PU PENDING'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: TgcgColors.muted,
                                    fontSize: 10.2,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    TgcgStatusPill(
                                      label:
                                          '${active.length} ACTIVE JOB${active.length == 1 ? '' : 'S'}',
                                      color: active.isEmpty
                                          ? TgcgColors.muted
                                          : TgcgColors.info,
                                      compact: true,
                                    ),
                                    if (atLocation)
                                      const TgcgStatusPill(
                                        label: 'AT LOCATION',
                                        color: TgcgColors.success,
                                        icon: Icons.gps_fixed_rounded,
                                        compact: true,
                                      ),
                                    TgcgStatusPill(
                                      label: device == null
                                          ? 'NO MANAGED PHONE'
                                          : 'PHONE BOUND',
                                      color: device == null
                                          ? TgcgColors.warning
                                          : TgcgColors.success,
                                      compact: true,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: TgcgColors.muted,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
      );
}

class _MemberInspector extends StatelessWidget {
  const _MemberInspector({
    required this.member,
    required this.membership,
    required this.assignments,
    required this.devices,
    required this.canAssign,
    required this.onOpenAssignments,
  });

  final TgcgMember? member;
  final MembershipOperationsController membership;
  final AssignmentController assignments;
  final ManagedDeviceController devices;
  final bool canAssign;
  final VoidCallback onOpenAssignments;

  @override
  Widget build(BuildContext context) {
    final member = this.member;
    if (member == null) {
      return const TgcgSectionCard(
        child: TgcgEmptyState(
          icon: Icons.person_outline_rounded,
          title: 'Select a member',
          message:
              'Choose a member to inspect identity, home polling unit, device and assignment history.',
        ),
      );
    }

    final homePu = membership.homePollingUnitForMember(member.id);
    final registration =
        membership.registrationScopeForMember(member.id);
    final device = devices.deviceForMember(member.id);
    final history = assignments.assignmentsForMember(member.id);
    final active = history.where((item) => !item.isTerminal).toList();
    final operationalProfiles = membership.agents
        .where((item) => item.memberId == member.id)
        .toList(growable: false);

    return TgcgSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: TgcgGradients.navigation,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(TgcgRadius.lg),
              ),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: TgcgColors.gold100,
                  foregroundColor: TgcgColors.primaryDark,
                  child: Text(
                    member.fullName.isEmpty
                        ? '?'
                        : member.fullName[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                Text(
                  member.fullName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  member.membershipNumber ?? member.id,
                  style: const TextStyle(
                    color: TgcgColors.gold200,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    TgcgStatusPill(
                      label: member.status.name.toUpperCase(),
                      color: member.status == RecordStatus.verified
                          ? TgcgColors.success
                          : TgcgColors.info,
                      compact: true,
                    ),
                    TgcgStatusPill(
                      label:
                          '${active.length} ACTIVE ASSIGNMENT${active.length == 1 ? '' : 'S'}',
                      color: active.isEmpty
                          ? TgcgColors.muted
                          : TgcgColors.success,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _InspectorTitle('Identity'),
                _DetailRow(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: member.phoneNumber,
                ),
                _DetailRow(
                  icon: Icons.alternate_email_rounded,
                  label: 'Email',
                  value: member.email ?? 'Not provided',
                ),
                _DetailRow(
                  icon: Icons.location_city_outlined,
                  label: 'Registration scope',
                  value: registration?.label ?? 'Not linked',
                ),
                const SizedBox(height: 12),
                const _InspectorTitle('Home polling unit'),
                _DetailRow(
                  icon: Icons.home_work_outlined,
                  label: homePu?.displayCode ?? 'Pending',
                  value: homePu?.scope.label ??
                      'A home polling unit has not been linked yet.',
                ),
                const SizedBox(height: 12),
                const _InspectorTitle('Managed device'),
                _DetailRow(
                  icon: Icons.phone_android_rounded,
                  label: device?.id ?? 'No device',
                  value: device?.label ??
                      'No organization-managed phone is currently bound.',
                ),
                const SizedBox(height: 12),
                const _InspectorTitle('Operational qualifications'),
                if (operationalProfiles.isEmpty)
                  const Text(
                    'No special operational qualification is recorded. This does not prevent the member from receiving a normal assignment.',
                    style: TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 10.5,
                      height: 1.45,
                    ),
                  )
                else
                  ...operationalProfiles.map(
                    (profile) => Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        children: [
                          Icon(
                            roleIcon(profile.role),
                            size: 17,
                            color: TgcgColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              roleLabel(profile.role),
                              style: const TextStyle(
                                color: TgcgColors.ink,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TgcgStatusPill(
                            label: profile.status.name.toUpperCase(),
                            color: profile.status ==
                                    AccreditationStatus.approved
                                ? TgcgColors.success
                                : TgcgColors.warning,
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                if (canAssign)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onOpenAssignments,
                      icon: const Icon(Icons.add_task_rounded),
                      label: const Text('Assign job to this member'),
                    ),
                  ),
                const SizedBox(height: 16),
                const _InspectorTitle('Assignment history'),
                if (history.isEmpty)
                  const Text(
                    'No assignment history yet.',
                    style: TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 10.5,
                    ),
                  )
                else
                  ...history.take(8).map(
                    (assignment) => _AssignmentHistoryRow(
                      assignment: assignment,
                      presence: assignments.presenceFor(assignment),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentHistoryRow extends StatelessWidget {
  const _AssignmentHistoryRow({
    required this.assignment,
    required this.presence,
  });

  final MemberAssignment assignment;
  final AssignmentPresence presence;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              assignment.isTerminal
                  ? Icons.task_alt_rounded
                  : Icons.assignment_outlined,
              size: 18,
              color: assignment.isTerminal
                  ? TgcgColors.success
                  : TgcgColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assignment.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    assignment.targetScope.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            TgcgStatusPill(
              label: _assignmentLabel(assignment.status),
              color: _assignmentColor(assignment.status, presence),
              compact: true,
            ),
          ],
        ),
      );
}

class _InspectorTitle extends StatelessWidget {
  const _InspectorTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: TgcgColors.primaryMid,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: .85,
          ),
        ),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: TgcgColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.7,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

String _filterLabel(_MemberFilter filter) => switch (filter) {
      _MemberFilter.all => 'All',
      _MemberFilter.unassigned => 'Unassigned',
      _MemberFilter.assigned => 'Assigned',
      _MemberFilter.atLocation => 'At location',
      _MemberFilter.noDevice => 'No managed phone',
      _MemberFilter.noHomePollingUnit => 'No home PU',
    };

String _assignmentLabel(AssignmentStatus status) => switch (status) {
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

Color _assignmentColor(
  AssignmentStatus status,
  AssignmentPresence presence,
) {
  if (presence == AssignmentPresence.insideGeofence) {
    return TgcgColors.success;
  }
  return switch (status) {
    AssignmentStatus.completed => TgcgColors.success,
    AssignmentStatus.gpsMismatch ||
    AssignmentStatus.overdue ||
    AssignmentStatus.declined => TgcgColors.warning,
    AssignmentStatus.cancelled => TgcgColors.muted,
    _ => TgcgColors.info,
  };
}
