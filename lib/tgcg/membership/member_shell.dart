import 'package:flutter/material.dart';

import '../assignments/assignment_location_service.dart';
import '../assignments/assignment_store.dart';
import '../assignments/assignment_tracking_store.dart';
import '../devices/managed_device_store.dart';
import '../evidence/device_evidence_service.dart';
import '../geography/geography_registry.dart';
import '../governance/governance_store.dart';
import '../meeting/operational_call_stage.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'membership_store.dart';

class MemberShell extends StatelessWidget {
  const MemberShell({super.key});

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final devices = ManagedDevices.of(context);
    final assignments = Assignments.of(context);
    final governance = GovernanceOperations.of(context);
    final member = membership.memberById(session.accessId);

    if (member == null) {
      return Scaffold(
        backgroundColor: TgcgColors.canvas,
        appBar: AppBar(
          title: const Text('Member Access'),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              onPressed: () async {
                await AssignmentTracking.of(context, listen: false).stop();
                session.signOut();
              },
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        body: const Center(
          child: TgcgEmptyState(
            icon: Icons.person_off_outlined,
            title: 'Member profile unavailable',
            message:
                'The signed-in identity is not linked to an enrolled USESF member.',
          ),
        ),
      );
    }

    final homePu = membership.homePollingUnitForMember(member.id);
    final registration = membership.registrationScopeForMember(member.id);
    final managedDevice = devices.deviceForMember(member.id);
    final activeAssignments = assignments.activeAssignmentsForMember(member.id);
    final activeRoles = governance.activeRolesForMember(member.id);

    if (member.isBlocked) {
      return _BlockedMemberScaffold(member: member);
    }

    if (activeRoles.isEmpty && activeAssignments.isEmpty) {
      return _WaitingForAccessScaffold(
        member: member,
        homePu: homePu,
        registration: registration,
      );
    }

    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(
        title: const Row(
          children: [
            TgcgLogo(size: 34),
            SizedBox(width: 10),
            Text('USESF Member'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await AssignmentTracking.of(context, listen: false).stop();
              session.signOut();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        children: [
          IncomingOperationalCallCard(memberId: member.id),
          TgcgPageHeader(
            eyebrow: 'MEMBER PROFILE',
            title: member.fullName,
            subtitle:
                'Your USESF identity, home polling unit and assignment readiness.',
            trailing: TgcgStatusPill(
              label: member.status.name.toUpperCase(),
              color: member.status == RecordStatus.verified
                  ? TgcgColors.success
                  : TgcgColors.info,
              icon: Icons.verified_user_outlined,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 760;
              final profile = _ProfileCard(
                memberId: member.membershipNumber ?? member.id,
                pvcVin: member.pvcVin,
                phone: member.phoneNumber,
                email: member.email,
                emailVerified: member.emailVerified,
                location: registration?.label ?? 'Kaduna State',
              );
              final pollingUnit = _HomePollingUnitCard(unit: homePu);
              if (!twoColumns) {
                return Column(
                  children: [
                    profile,
                    const SizedBox(height: 14),
                    pollingUnit,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: profile),
                  const SizedBox(width: 14),
                  Expanded(child: pollingUnit),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          TgcgSectionCard(
            title: 'Active roles',
            subtitle:
                'All active roles are combined automatically. Each role keeps its own geographic scope.',
            trailing: TgcgStatusPill(
              label: '${activeRoles.length} ACTIVE',
              color: TgcgColors.success,
              icon: Icons.manage_accounts_outlined,
              compact: true,
            ),
            child: Column(
              children: activeRoles
                  .map(
                    (role) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        roleIcon(role.role),
                        color: TgcgColors.primary,
                      ),
                      title: Text(
                        roleLabel(role.role),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(role.scope.label),
                      trailing: const TgcgStatusPill(
                        label: 'ACTIVE',
                        color: TgcgColors.success,
                        compact: true,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          TgcgSectionCard(
            title: 'Assignment centre',
            subtitle:
                'Your home polling unit remains permanent; temporary operational duties appear separately here.',
            trailing: TgcgStatusPill(
              label: '${activeAssignments.length} ACTIVE',
              color: activeAssignments.isEmpty
                  ? TgcgColors.muted
                  : TgcgColors.info,
              icon: Icons.assignment_outlined,
              compact: true,
            ),
            child: activeAssignments.isEmpty
                ? const TgcgEmptyState(
                    icon: Icons.assignment_outlined,
                    title: 'No active assignment',
                    message:
                        'An authorized coordinator can assign a duty without changing your home polling unit.',
                  )
                : Column(
                    children: activeAssignments
                        .map(
                          (assignment) => _MemberAssignmentCard(
                            assignment: assignment,
                            memberId: member.id,
                            managedDevice: managedDevice,
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 14),
          TgcgSectionCard(
            title: 'Managed assignment phone',
            subtitle:
                'Organization-issued phones can be bound to members for assignment GPS, evidence and sync.',
            child: managedDevice == null
                ? const TgcgEmptyState(
                    icon: Icons.phonelink_erase_outlined,
                    title: 'No managed phone assigned',
                    message:
                        'A coordinator can bind an organization-issued phone before an operational assignment begins.',
                  )
                : Column(
                    children: [
                      _Detail(label: 'Device', value: managedDevice.label),
                      _Detail(label: 'Device ID', value: managedDevice.id),
                      _Detail(
                        label: 'Status',
                        value: managedDevice.status.name.toUpperCase(),
                      ),
                      _Detail(
                        label: 'Last seen',
                        value: managedDevice.lastSeenAt == null
                            ? 'No heartbeat yet'
                            : managedDevice.lastSeenAt!
                                .toLocal()
                                .toString(),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          TgcgSectionCard(
            title: 'Location readiness',
            subtitle:
                'Location permission is required for device telemetry and for every assignment capture, evidence update and submission.',
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: homePu?.operationalLatitude == null
                        ? TgcgColors.warning.withValues(alpha: .08)
                        : TgcgColors.success.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(TgcgRadius.md),
                  ),
                  child: Icon(
                    homePu?.operationalLatitude == null
                        ? Icons.location_searching_rounded
                        : Icons.gps_fixed_rounded,
                    color: homePu?.operationalLatitude == null
                        ? TgcgColors.warning
                        : TgcgColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    homePu == null
                        ? 'Home polling unit has not been linked.'
                        : homePu.operationalLatitude == null
                            ? 'Home polling unit is linked, but its operational GPS coordinate is still pending.'
                            : 'Home polling unit coordinate is available for assignment geofencing.',
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
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

class _BlockedMemberScaffold extends StatelessWidget {
  const _BlockedMemberScaffold({required this.member});

  final TgcgMember member;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(
        title: const Text('Member Access'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await AssignmentTracking.of(context, listen: false).stop();
              session.signOut();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: TgcgSectionCard(
              title: 'Account blocked',
              subtitle:
                  'This member account has been blocked following internal identity review.',
              child: Column(
                children: [
                  const Icon(
                    Icons.block_rounded,
                    size: 56,
                    color: TgcgColors.danger,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    member.fullName,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    member.membershipNumber ?? member.id,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Operational access is disabled. The same account, roles and history can be restored if the backend System Admin later clears the review.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: TgcgColors.muted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaitingForAccessScaffold extends StatefulWidget {
  const _WaitingForAccessScaffold({
    required this.member,
    required this.homePu,
    required this.registration,
  });

  final TgcgMember member;
  final CanonicalPollingUnit? homePu;
  final GeographicScope? registration;

  @override
  State<_WaitingForAccessScaffold> createState() =>
      _WaitingForAccessScaffoldState();
}

class _WaitingForAccessScaffoldState extends State<_WaitingForAccessScaffold> {
  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final member = widget.member;

    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(
        title: const Row(
          children: [
            TgcgLogo(size: 34),
            SizedBox(width: 10),
            Text('USESF Member'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await AssignmentTracking.of(context, listen: false).stop();
              session.signOut();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        children: [
          IncomingOperationalCallCard(memberId: member.id),
          TgcgPageHeader(
            eyebrow: 'MEMBERSHIP ACTIVE',
            title: member.fullName,
            subtitle:
                'Your member account is active. Operational access will appear automatically when an authorized coordinator assigns a role or an assignment.',
            trailing: const TgcgStatusPill(
              label: 'WAITING FOR ACCESS',
              color: TgcgColors.info,
              icon: Icons.hourglass_top_rounded,
            ),
          ),
          const SizedBox(height: 16),
          TgcgSectionCard(
            title: 'Waiting for role or assignment',
            child: Column(
              children: [
                const Icon(
                  Icons.assignment_ind_outlined,
                  size: 54,
                  color: TgcgColors.primary,
                ),
                const SizedBox(height: 12),
                const Text(
                  'You are registered as a member, but you do not currently have an active role or assignment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w800,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'No operational modules are available yet. You can maintain your own account details while you wait.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final profile = _ProfileCard(
                memberId: member.membershipNumber ?? member.id,
                pvcVin: member.pvcVin,
                phone: member.phoneNumber,
                email: member.email,
                emailVerified: member.emailVerified,
                location:
                    widget.registration?.label ?? GeographicScope.kaduna.label,
              );
              final pollingUnit = _HomePollingUnitCard(unit: widget.homePu);
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [
                    profile,
                    const SizedBox(height: 14),
                    pollingUnit,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: profile),
                  const SizedBox(width: 14),
                  Expanded(child: pollingUnit),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          TgcgSectionCard(
            title: 'Account settings',
            subtitle:
                'PVC-derived electoral details are locked. You can update your phone, add an email and change your password.',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _editContact,
                  icon: const Icon(Icons.contact_phone_outlined),
                  label: const Text('Phone & email'),
                ),
                OutlinedButton.icon(
                  onPressed: _changePassword,
                  icon: const Icon(Icons.password_rounded),
                  label: const Text('Change password'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editContact() async {
    final member = widget.member;
    final phone = TextEditingController(text: member.phoneNumber);
    final email = TextEditingController(text: member.email ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update contact details'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  helperText: 'Phone is optional and is not verified.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                enabled: !member.emailVerified,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email address',
                  helperText: member.emailVerified
                      ? 'Verified email can only be changed by backend System Admin.'
                      : 'Email can be verified later for password recovery.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      try {
        await MembershipOperations.of(context, listen: false)
            .updateMemberContact(
          memberId: member.id,
          phoneNumber: phone.text,
          email: email.text,
        );
      } on StateError catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
    }
    phone.dispose();
    email.dispose();
  }

  Future<void> _changePassword() async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change password'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    helperText: 'Use at least 8 characters.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Confirm password'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: TgcgColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (password.text.length < 8) {
                  setDialogState(
                    () => error = 'Password must contain at least 8 characters.',
                  );
                  return;
                }
                if (password.text != confirm.text) {
                  setDialogState(() => error = 'The passwords do not match.');
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Change password'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      await MembershipOperations.of(context, listen: false).setMemberPassword(
        memberId: widget.member.id,
        password: password.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated.')),
        );
      }
    }
    password.dispose();
    confirm.dispose();
  }
}

class _MemberAssignmentCard extends StatefulWidget {
  const _MemberAssignmentCard({
    required this.assignment,
    required this.memberId,
    required this.managedDevice,
  });

  final MemberAssignment assignment;
  final String memberId;
  final ManagedDevice? managedDevice;

  @override
  State<_MemberAssignmentCard> createState() =>
      _MemberAssignmentCardState();
}

class _MemberAssignmentCardState extends State<_MemberAssignmentCard> {
  final AssignmentLocationService _location =
      const AssignmentLocationService();
  final DeviceEvidenceService _evidenceService = DeviceEvidenceService();
  bool _busy = false;

  @override
  void dispose() {
    _evidenceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assignments = Assignments.of(context);
    final tracking = AssignmentTracking.of(context);
    final session = TgcgSession.of(context, listen: false);
    final current =
        assignments.assignmentById(widget.assignment.id) ?? widget.assignment;
    final presence = assignments.presenceFor(current);
    final device = widget.managedDevice;
    final restricted = current.systemIntelligenceRestricted;
    final group = current.groupAssignmentId == null
        ? null
        : assignments.groupAssignmentById(current.groupAssignmentId!);
    final actions = _actionsFor(
      current.status,
      groupAssignment: current.belongsToGroup,
    );
    final canSubmitGroup = current.isGroupChairman &&
        current.groupAssignmentId != null &&
        group != null &&
        !group.isTerminal &&
        !current.isTerminal &&
        current.status != AssignmentStatus.assigned &&
        current.status != AssignmentStatus.reassigned;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: TgcgColors.primarySoft,
                  borderRadius: BorderRadius.circular(TgcgRadius.sm),
                ),
                child: const Icon(
                  Icons.assignment_turned_in_outlined,
                  color: TgcgColors.primary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.title,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _memberAssignmentTargetLabel(current, group),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                    if (current.instructions != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        current.instructions!,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        TgcgStatusPill(
                          label: restricted &&
                                  current.status ==
                                      AssignmentStatus.gpsMismatch
                              ? 'IN PROGRESS'
                              : _assignmentStatusLabel(current.status),
                          color: restricted &&
                                  current.status ==
                                      AssignmentStatus.gpsMismatch
                              ? TgcgColors.info
                              : _assignmentStatusColor(current.status),
                          compact: true,
                        ),
                        if (!restricted)
                          TgcgStatusPill(
                            label: _presenceLabel(presence),
                            color: _presenceColor(presence),
                            compact: true,
                          ),
                        if (current.isGroupChairman)
                          const TgcgStatusPill(
                            label: 'CHAIRMAN',
                            color: TgcgColors.accentStrong,
                            compact: true,
                          ),
                        if (!restricted && device != null)
                          TgcgStatusPill(
                            label: device.id,
                            color: TgcgColors.info,
                            icon: Icons.phone_android_outlined,
                            compact: true,
                          ),
                        if (!restricted &&
                            tracking.isTrackingAssignment(current.id))
                          const TgcgStatusPill(
                            label: 'LIVE GPS',
                            color: TgcgColors.success,
                            icon: Icons.location_searching_rounded,
                            compact: true,
                          ),
                        TgcgStatusPill(
                          label: '${current.evidence.length} EVIDENCE',
                          color: current.evidence.isEmpty
                              ? TgcgColors.muted
                              : TgcgColors.success,
                          icon: Icons.attachment_rounded,
                          compact: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!restricted && current.lastLocation != null) ...[
            const SizedBox(height: 10),
            Text(
              'Last GPS: ${current.lastLocation!.latitude.toStringAsFixed(6)}, '
              '${current.lastLocation!.longitude.toStringAsFixed(6)} • '
              '±${current.lastLocation!.accuracyMeters.toStringAsFixed(1)} m'
              '${current.lastLocation!.distanceFromTargetMeters == null ? '' : ' • ${current.lastLocation!.distanceFromTargetMeters!.toStringAsFixed(0)} m from target'}',
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 11),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions.map((action) {
                if (action == _MemberAssignmentAction.checkIn) {
                  return FilledButton.tonalIcon(
                    onPressed:
                        _busy || device == null ? null : () => _checkIn(current),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded, size: 17),
                    label: Text(
                      device == null ? 'Managed phone required' : 'Check in',
                    ),
                  );
                }
                if (action == _MemberAssignmentAction.refreshGps) {
                  return OutlinedButton.icon(
                    onPressed:
                        _busy || device == null ? null : () => _refreshGps(current),
                    icon: const Icon(Icons.gps_fixed_rounded, size: 17),
                    label: const Text('Refresh GPS'),
                  );
                }
                final target = _statusForAction(action);
                return FilledButton.tonalIcon(
                  onPressed: _busy || target == null
                      ? null
                      : () => _transition(
                            current,
                            target,
                            session.accessId.isEmpty
                                ? widget.memberId
                                : session.accessId,
                          ),
                  icon: Icon(_actionIcon(action), size: 17),
                  label: Text(_actionLabel(action)),
                );
              }).toList(),
            ),
          ],
          if (canSubmitGroup) ...[
            const SizedBox(height: 11),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _submitGroupAssignment(current),
              icon: const Icon(Icons.task_alt_rounded, size: 17),
              label: const Text('Submit group assignment'),
            ),
          ],
          if ((current.status == AssignmentStatus.checkedIn ||
                  current.status == AssignmentStatus.active) &&
              device != null) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!restricted)
                  FilledButton.tonalIcon(
                    onPressed: _busy || tracking.isStarting
                        ? null
                        : () async {
                            try {
                              if (tracking.isTrackingAssignment(current.id)) {
                                await tracking.stop();
                              } else {
                                await tracking.start(
                                  assignmentId: current.id,
                                  deviceId: device.id,
                                );
                              }
                            } on StateError catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.message)),
                              );
                            }
                          },
                    icon: Icon(
                      tracking.isTrackingAssignment(current.id)
                          ? Icons.location_disabled_outlined
                          : Icons.location_searching_rounded,
                      size: 17,
                    ),
                    label: Text(
                      tracking.isTrackingAssignment(current.id)
                          ? 'Stop live GPS'
                          : 'Start live GPS',
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _captureEvidence(
                            current,
                            EvidenceType.photo,
                          ),
                  icon: const Icon(Icons.photo_camera_outlined, size: 17),
                  label: const Text('Capture photo'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _captureEvidence(
                            current,
                            EvidenceType.video,
                          ),
                  icon: const Icon(Icons.videocam_outlined, size: 17),
                  label: const Text('Capture video'),
                ),
              ],
            ),
          ],
          if (!restricted &&
              device == null &&
              (current.status == AssignmentStatus.enRoute ||
                  current.status == AssignmentStatus.gpsMismatch ||
                  current.status == AssignmentStatus.active)) ...[
            const SizedBox(height: 9),
            const Text(
              'GPS check-in is disabled until an organization-managed phone is assigned to this member.',
              style: TextStyle(
                color: TgcgColors.warning,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submitGroupAssignment(
    MemberAssignment assignment,
  ) async {
    final groupAssignmentId = assignment.groupAssignmentId;
    if (groupAssignmentId == null || !assignment.isGroupChairman) return;
    setState(() => _busy = true);
    final tracking = AssignmentTracking.of(context, listen: false);
    try {
      await Assignments.of(context, listen: false).submitGroupAssignment(
        groupAssignmentId: groupAssignmentId,
        chairmanMemberId: widget.memberId,
      );
      if (tracking.isTrackingAssignment(assignment.id)) {
        await tracking.stop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group assignment submitted.')),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _captureEvidence(
    MemberAssignment assignment,
    EvidenceType type,
  ) async {
    final device = widget.managedDevice;
    if (device == null) return;
    setState(() => _busy = true);
    try {
      final fix = await _location.captureCurrentFix();
      if (!mounted) return;
      Assignments.of(context, listen: false).recordLocationHeartbeat(
        assignmentId: assignment.id,
        deviceId: device.id,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyMeters: fix.accuracyMeters,
        capturedAt: fix.capturedAt,
      );

      final captured = switch (type) {
        EvidenceType.photo => await _evidenceService.capturePhoto(),
        EvidenceType.video => await _evidenceService.captureVideo(),
        _ => null,
      };
      if (!mounted || captured == null) return;

      final latest =
          Assignments.of(context, listen: false).assignmentById(assignment.id) ??
              assignment;
      final ping = latest.lastLocation;
      final evidence = EvidenceAttachment(
        id: 'AEV-${DateTime.now().microsecondsSinceEpoch}',
        type: captured.type,
        fileName: captured.fileName,
        createdAt: captured.createdAt,
        uploaderId: widget.memberId,
        contentHash: captured.contentHash,
        mimeType: captured.mimeType,
        sourceReference: captured.path,
        latitude: captured.latitude ?? ping?.latitude,
        longitude: captured.longitude ?? ping?.longitude,
        caption:
            'Captured during USESF assignment ${assignment.id} from managed device ${device.id}.',
        origin: RecordOrigin.localEntry,
      );

      await Assignments.of(context, listen: false).attachEvidence(
        assignmentId: assignment.id,
        evidence: evidence,
        actorId: widget.memberId,
        deviceId: device.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${captured.type.name.toUpperCase()} evidence attached to the assignment.',
          ),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Evidence capture failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transition(
    MemberAssignment assignment,
    AssignmentStatus target,
    String actorId,
  ) async {
    setState(() => _busy = true);
    final tracking = AssignmentTracking.of(context, listen: false);
    try {
      if (target == AssignmentStatus.completed) {
        final device = widget.managedDevice;
        if (device == null) {
          throw StateError(
            'A device with location access is required to complete this assignment.',
          );
        }
        final fix = await _location.captureCurrentFix();
        if (!mounted) return;
        Assignments.of(context, listen: false).recordLocationHeartbeat(
          assignmentId: assignment.id,
          deviceId: device.id,
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracyMeters: fix.accuracyMeters,
          capturedAt: fix.capturedAt,
        );
      }

      await Assignments.of(context, listen: false).transition(
        assignmentId: assignment.id,
        status: target,
        actorId: actorId,
      );
      if (target == AssignmentStatus.completed ||
          target == AssignmentStatus.cancelled ||
          target == AssignmentStatus.declined) {
        if (tracking.isTrackingAssignment(assignment.id)) {
          await tracking.stop();
        }
      }
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkIn(MemberAssignment assignment) async {
    final device = widget.managedDevice;
    if (device == null) return;
    setState(() => _busy = true);
    try {
      final fix = await _location.captureCurrentFix();
      if (!mounted) return;
      final updated = await Assignments.of(context, listen: false).checkIn(
        assignmentId: assignment.id,
        actorId: widget.memberId,
        deviceId: device.id,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyMeters: fix.accuracyMeters,
        capturedAt: fix.capturedAt,
      );
      if (!mounted) return;
      if (updated.status == AssignmentStatus.checkedIn) {
        await AssignmentTracking.of(context, listen: false).start(
          assignmentId: updated.id,
          deviceId: device.id,
        );
      }
      if (!mounted) return;
      final message = assignment.systemIntelligenceRestricted
          ? 'Check-in recorded.'
          : updated.status == AssignmentStatus.checkedIn
              ? 'Presence confirmed inside the assigned polling-unit geofence.'
              : 'GPS captured, but the device is outside the assigned polling-unit geofence.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location capture failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshGps(MemberAssignment assignment) async {
    final device = widget.managedDevice;
    if (device == null) return;
    setState(() => _busy = true);
    try {
      final fix = await _location.captureCurrentFix();
      if (!mounted) return;
      Assignments.of(context, listen: false).recordLocationHeartbeat(
        assignmentId: assignment.id,
        deviceId: device.id,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyMeters: fix.accuracyMeters,
        capturedAt: fix.capturedAt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assignment GPS heartbeat refreshed.')),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location capture failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

enum _MemberAssignmentAction {
  accept,
  decline,
  enRoute,
  checkIn,
  start,
  refreshGps,
  complete,
}

List<_MemberAssignmentAction> _actionsFor(
  AssignmentStatus status, {
  bool groupAssignment = false,
}) {
  if (groupAssignment) {
    return switch (status) {
      AssignmentStatus.assigned => const [
          _MemberAssignmentAction.accept,
          _MemberAssignmentAction.decline,
        ],
      AssignmentStatus.accepted => const [
          _MemberAssignmentAction.enRoute,
        ],
      AssignmentStatus.enRoute || AssignmentStatus.gpsMismatch => const [
          _MemberAssignmentAction.checkIn,
        ],
      AssignmentStatus.checkedIn => const [
          _MemberAssignmentAction.start,
        ],
      _ => const [],
    };
  }
  return switch (status) {
      AssignmentStatus.assigned => const [
          _MemberAssignmentAction.accept,
          _MemberAssignmentAction.decline,
        ],
      AssignmentStatus.accepted => const [
          _MemberAssignmentAction.enRoute,
        ],
      AssignmentStatus.enRoute || AssignmentStatus.gpsMismatch => const [
          _MemberAssignmentAction.checkIn,
        ],
      AssignmentStatus.checkedIn => const [
          _MemberAssignmentAction.start,
          _MemberAssignmentAction.refreshGps,
        ],
      AssignmentStatus.active => const [
          _MemberAssignmentAction.refreshGps,
          _MemberAssignmentAction.complete,
        ],
      _ => const [],
    };
}

AssignmentStatus? _statusForAction(_MemberAssignmentAction action) =>
    switch (action) {
      _MemberAssignmentAction.accept => AssignmentStatus.accepted,
      _MemberAssignmentAction.decline => AssignmentStatus.declined,
      _MemberAssignmentAction.enRoute => AssignmentStatus.enRoute,
      _MemberAssignmentAction.start => AssignmentStatus.active,
      _MemberAssignmentAction.complete => AssignmentStatus.completed,
      _MemberAssignmentAction.checkIn ||
      _MemberAssignmentAction.refreshGps => null,
    };

String _actionLabel(_MemberAssignmentAction action) => switch (action) {
      _MemberAssignmentAction.accept => 'Accept',
      _MemberAssignmentAction.decline => 'Decline',
      _MemberAssignmentAction.enRoute => 'En route',
      _MemberAssignmentAction.checkIn => 'Check in',
      _MemberAssignmentAction.start => 'Start assignment',
      _MemberAssignmentAction.refreshGps => 'Refresh GPS',
      _MemberAssignmentAction.complete => 'Complete',
    };

IconData _actionIcon(_MemberAssignmentAction action) => switch (action) {
      _MemberAssignmentAction.accept => Icons.check_circle_outline_rounded,
      _MemberAssignmentAction.decline => Icons.close_rounded,
      _MemberAssignmentAction.enRoute => Icons.directions_car_outlined,
      _MemberAssignmentAction.checkIn => Icons.my_location_rounded,
      _MemberAssignmentAction.start => Icons.play_arrow_rounded,
      _MemberAssignmentAction.refreshGps => Icons.gps_fixed_rounded,
      _MemberAssignmentAction.complete => Icons.task_alt_rounded,
    };

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.memberId,
    required this.pvcVin,
    required this.phone,
    required this.email,
    required this.emailVerified,
    required this.location,
  });

  final String memberId;
  final String? pvcVin;
  final String phone;
  final String? email;
  final bool emailVerified;
  final String location;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Member identity',
        child: Column(
          children: [
            _Detail(label: 'Member ID', value: memberId),
            _Detail(label: 'PVC / VIN', value: pvcVin ?? 'Not available'),
            _Detail(
              label: 'Phone',
              value: phone.trim().isEmpty ? 'Not provided' : phone,
            ),
            _Detail(
              label: 'Email',
              value: email == null
                  ? 'Not provided'
                  : '$email${emailVerified ? ' • VERIFIED' : ' • NOT VERIFIED'}',
            ),
            _Detail(label: 'Registered scope', value: location),
          ],
        ),
      );
}

class _HomePollingUnitCard extends StatelessWidget {
  const _HomePollingUnitCard({required this.unit});

  final CanonicalPollingUnit? unit;

  @override
  Widget build(BuildContext context) {
    final item = unit;
    if (item == null) {
      return const TgcgSectionCard(
        title: 'Home polling unit',
        child: TgcgEmptyState(
          icon: Icons.location_off_outlined,
          title: 'Polling unit not linked',
          message:
              'The member record needs a canonical home polling-unit relationship.',
        ),
      );
    }

    final latitude = item.operationalLatitude;
    final longitude = item.operationalLongitude;
    return TgcgSectionCard(
      title: 'Home polling unit',
      trailing: TgcgStatusPill(
        label: _coordinateLabel(item.coordinateStatus),
        color: _coordinateColor(item.coordinateStatus),
        compact: true,
      ),
      child: Column(
        children: [
          _Detail(label: 'PU code', value: item.displayCode),
          _Detail(label: 'Polling unit', value: item.scope.pollingUnitName ?? '—'),
          _Detail(label: 'Ward', value: item.scope.wardName ?? '—'),
          _Detail(label: 'LGA', value: item.scope.lgaName ?? '—'),
          _Detail(
            label: 'Coordinate',
            value: latitude == null || longitude == null
                ? 'Pending'
                : '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
          ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 108,
              child: Text(
                label,
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
}

String _memberAssignmentTargetLabel(
  MemberAssignment assignment,
  GroupAssignment? group,
) {
  if (group == null ||
      group.distribution != GroupAssignmentDistribution.together ||
      group.targetScopes.isEmpty) {
    return assignment.targetScope.label;
  }
  final shown =
      group.targetScopes.take(2).map((scope) => scope.label).join(' • ');
  final remaining = group.targetScopes.length - 2;
  return remaining > 0 ? '$shown • +$remaining' : shown;
}

String _assignmentStatusLabel(AssignmentStatus status) => switch (status) {
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

Color _assignmentStatusColor(AssignmentStatus status) => switch (status) {
      AssignmentStatus.completed => TgcgColors.success,
      AssignmentStatus.checkedIn || AssignmentStatus.active =>
        TgcgColors.success,
      AssignmentStatus.enRoute || AssignmentStatus.accepted =>
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

String _coordinateLabel(PollingUnitCoordinateStatus status) => switch (status) {
      PollingUnitCoordinateStatus.missing => 'GPS PENDING',
      PollingUnitCoordinateStatus.referenceOnly => 'REFERENCE GPS',
      PollingUnitCoordinateStatus.fieldVerified => 'FIELD VERIFIED',
      PollingUnitCoordinateStatus.needsReview => 'GPS REVIEW',
    };

Color _coordinateColor(PollingUnitCoordinateStatus status) => switch (status) {
      PollingUnitCoordinateStatus.missing => TgcgColors.muted,
      PollingUnitCoordinateStatus.referenceOnly => TgcgColors.info,
      PollingUnitCoordinateStatus.fieldVerified => TgcgColors.success,
      PollingUnitCoordinateStatus.needsReview => TgcgColors.warning,
    };
