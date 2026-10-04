import 'package:flutter/material.dart';

import '../assignments/assignment_location_service.dart';
import '../assignments/assignment_store.dart';
import '../assignments/assignment_tracking_store.dart';
import '../devices/managed_device_store.dart';
import '../evidence/device_evidence_service.dart';
import '../geography/geography_registry.dart';
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
                phone: member.phoneNumber,
                email: member.email,
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
                'GPS is activated only for authorized assignment workflows on managed devices.',
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
    final actions = _actionsFor(current.status);

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
                      current.targetScope.label,
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
                          label: _assignmentStatusLabel(current.status),
                          color: _assignmentStatusColor(current.status),
                          compact: true,
                        ),
                        TgcgStatusPill(
                          label: _presenceLabel(presence),
                          color: _presenceColor(presence),
                          compact: true,
                        ),
                        if (device != null)
                          TgcgStatusPill(
                            label: device.id,
                            color: TgcgColors.info,
                            icon: Icons.phone_android_outlined,
                            compact: true,
                          ),
                        if (tracking.isTrackingAssignment(current.id))
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
          if (current.lastLocation != null) ...[
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
          if ((current.status == AssignmentStatus.checkedIn ||
                  current.status == AssignmentStatus.active) &&
              device != null) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
          if (device == null &&
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

  Future<void> _captureEvidence(
    MemberAssignment assignment,
    EvidenceType type,
  ) async {
    final device = widget.managedDevice;
    if (device == null) return;
    setState(() => _busy = true);
    try {
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
      final message = updated.status == AssignmentStatus.checkedIn
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

List<_MemberAssignmentAction> _actionsFor(AssignmentStatus status) =>
    switch (status) {
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
    required this.phone,
    required this.email,
    required this.location,
  });

  final String memberId;
  final String phone;
  final String? email;
  final String location;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Member identity',
        child: Column(
          children: [
            _Detail(label: 'Member ID', value: memberId),
            _Detail(label: 'Phone', value: phone),
            _Detail(label: 'Email', value: email ?? 'Not provided'),
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
