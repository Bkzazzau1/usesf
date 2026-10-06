import 'package:flutter/material.dart';

import '../devices/managed_device_store.dart';
import '../geography/geography_registry.dart';
import '../membership/membership_store.dart';
import '../meeting/operational_call_stage.dart';
import '../meeting/operational_call_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

Future<void> startStateCoordinatorMemberCall(
  BuildContext context, {
  required OperationalCallController calls,
  required TgcgSessionController session,
  required GeographicScope stateScope,
  required TgcgMember member,
  required OperationalCallKind kind,
  String? assignmentId,
  String? groupAssignmentId,
}) async {
  final call = await calls.startDirectCall(
    recipientMemberId: member.id,
    kind: kind,
    callerId: session.accessId.isEmpty
        ? session.operatorName
        : session.accessId,
    callerName: session.operatorName,
    callerRole: TgcgRole.stateCoordinator,
    authorizedScope: stateScope,
    assignmentId: assignmentId,
    groupAssignmentId: groupAssignmentId,
  );
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OperationalCallStage(callId: call.id),
    ),
  );
}

Future<void> startStateCoordinatorGroupCall(
  BuildContext context, {
  required OperationalCallController calls,
  required TgcgSessionController session,
  required GeographicScope stateScope,
  required List<String> memberIds,
  required String groupAssignmentId,
}) async {
  final call = await calls.startConference(
    recipientMemberIds: memberIds,
    callerId: session.accessId.isEmpty
        ? session.operatorName
        : session.accessId,
    callerName: session.operatorName,
    callerRole: TgcgRole.stateCoordinator,
    authorizedScope: stateScope,
    groupAssignmentId: groupAssignmentId,
  );
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OperationalCallStage(callId: call.id),
    ),
  );
}

Future<void> showStateCoordinatorCallMemberDialog(
  BuildContext context, {
  required OperationalCallController calls,
  required MembershipOperationsController membership,
  required TgcgSessionController session,
  required GeographicScope stateScope,
}) async {
  final members = membership.members
      .where(
        (member) =>
            !member.isBlocked &&
            (session.accessId.isEmpty || member.id != session.accessId),
      )
      .toList(growable: false);
  if (members.isEmpty) return;

  final search = TextEditingController();
  var kind = OperationalCallKind.video;
  String? selectedMemberId = members
      .where((member) => calls.gpsActiveForMember(member.id))
      .map((member) => member.id)
      .firstOrNull;

  final selected = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        ManagedDevices.of(context);
        final needle = search.text.trim().toLowerCase();
        final visible = members
            .where((member) {
              if (needle.isEmpty) return true;
              return member.fullName.toLowerCase().contains(needle) ||
                  (member.membershipNumber ?? '').toLowerCase().contains(
                    needle,
                  ) ||
                  member.phoneNumber.toLowerCase().contains(needle);
            })
            .toList(growable: false);

        if (selectedMemberId != null &&
            !visible.any(
              (member) =>
                  member.id == selectedMemberId &&
                  calls.gpsActiveForMember(member.id),
            )) {
          selectedMemberId = null;
        }
        selectedMemberId ??= visible
              .where((member) => calls.gpsActiveForMember(member.id))
              .map((member) => member.id)
              .firstOrNull;

        return AlertDialog(
          title: const Text('Call member'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: search,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search members',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<OperationalCallKind>(
                  segments: const [
                    ButtonSegment(
                      value: OperationalCallKind.audio,
                      icon: Icon(Icons.call_outlined),
                      label: Text('Audio'),
                    ),
                    ButtonSegment(
                      value: OperationalCallKind.video,
                      icon: Icon(Icons.videocam_outlined),
                      label: Text('Video'),
                    ),
                  ],
                  selected: {kind},
                  onSelectionChanged: (values) =>
                      setDialogState(() => kind = values.first),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 300,
                  child: RadioGroup<String>(
                    groupValue: selectedMemberId,
                    onChanged: (value) => setDialogState(() {
                      if (value != null) selectedMemberId = value;
                    }),
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final member = visible[index];
                        final gps =
                            calls.gpsSnapshotForMember(member.id);
                        return RadioListTile<String>(
                          value: member.id,
                          enabled: gps != null,
                          title: Text(member.fullName),
                          subtitle: Text(
                            gps == null
                                ? 'GPS inactive'
                                : 'GPS active • ${_callGpsAge(gps.capturedAt)}',
                          ),
                          secondary: Icon(
                            gps == null
                                ? Icons.gps_off_rounded
                                : Icons.gps_fixed_rounded,
                            color: gps == null
                                ? TgcgColors.warning
                                : TgcgColors.success,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: selectedMemberId == null
                  ? null
                  : () => Navigator.pop(dialogContext, selectedMemberId),
              icon: Icon(
                kind == OperationalCallKind.audio
                    ? Icons.call_rounded
                    : Icons.videocam_rounded,
              ),
              label: const Text('Call'),
            ),
          ],
        );
      },
    ),
  );

  search.dispose();
  if (selected == null || !context.mounted) return;
  final member = membership.memberById(selected);
  if (member == null) return;
  try {
    await startStateCoordinatorMemberCall(
      context,
      calls: calls,
      session: session,
      stateScope: stateScope,
      member: member,
      kind: kind,
    );
  } on StateError catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
  }
}

Future<bool> showPollingUnitCoordinateDialog(
  BuildContext context, {
  required MembershipOperationsController membership,
  required CanonicalPollingUnit unit,
  required String actorId,
  required GeographicScope stateScope,
}) async {
  final current = membership.geography.pollingUnit(unit.code) ?? unit;
  final ready =
      current.operationalLatitude != null &&
      current.operationalLongitude != null;
  final latitude = TextEditingController(
    text: ready ? current.operationalLatitude!.toStringAsFixed(6) : '',
  );
  final longitude = TextEditingController(
    text: ready ? current.operationalLongitude!.toStringAsFixed(6) : '',
  );

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(current.displayCode),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: latitude,
              readOnly: ready,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Latitude',
                prefixIcon: Icon(Icons.north_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: longitude,
              readOnly: ready,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Longitude',
                prefixIcon: Icon(Icons.east_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TgcgStatusPill(
                label: ready
                    ? _coordinateStatusLabel(current.coordinateStatus)
                    : 'GPS MISSING',
                color: ready ? TgcgColors.success : TgcgColors.warning,
                compact: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(ready ? 'Close' : 'Cancel'),
        ),
        if (!ready)
          FilledButton.icon(
            onPressed: () async {
              final lat = double.tryParse(latitude.text.trim());
              final lng = double.tryParse(longitude.text.trim());
              if (lat == null || lng == null) return;
              try {
                await membership.addManualPollingUnitCoordinate(
                  pollingUnitId: current.code,
                  latitude: lat,
                  longitude: lng,
                  recordedBy: actorId,
                  recordedByRole: TgcgRole.stateCoordinator,
                  authorizedScope: stateScope,
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } on ArgumentError catch (error) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text(error.message.toString())),
                );
              } on StateError catch (error) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(
                  dialogContext,
                ).showSnackBar(SnackBar(content: Text(error.message)));
              }
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save GPS'),
          ),
      ],
    ),
  );

  latitude.dispose();
  longitude.dispose();
  return saved == true;
}

String _callGpsAge(DateTime capturedAt) {
  final age = DateTime.now().toUtc().difference(capturedAt.toUtc()).abs();
  if (age.inSeconds < 60) return '${age.inSeconds}s ago';
  return '${age.inMinutes}m ago';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String _coordinateStatusLabel(PollingUnitCoordinateStatus status) =>
    switch (status) {
      PollingUnitCoordinateStatus.missing => 'GPS MISSING',
      PollingUnitCoordinateStatus.referenceOnly => 'REFERENCE GPS',
      PollingUnitCoordinateStatus.fieldVerified => 'FIELD VERIFIED',
      PollingUnitCoordinateStatus.needsReview => 'GPS REVIEW',
    };
