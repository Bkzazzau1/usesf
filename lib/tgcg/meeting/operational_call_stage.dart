import 'package:flutter/material.dart';

import '../media/local_camera_view.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'operational_call_store.dart';

class OperationalCallOverlay extends StatelessWidget {
  const OperationalCallOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (session.role != TgcgRole.member || session.accessId.isEmpty) {
      return child;
    }
    final membership = MembershipOperations.of(context);
    final member = membership.memberById(session.accessId);
    if (member == null || member.isBlocked) return child;
    final calls = OperationalCalls.of(context);
    if (calls.incomingForMember(member.id).isEmpty) return child;

    return Stack(
      children: [
        child,
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Material(
                  color: Colors.transparent,
                  child: IncomingOperationalCallCard(memberId: member.id),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class OperationalCallStage extends StatefulWidget {
  const OperationalCallStage({
    super.key,
    required this.callId,
  });

  final String callId;

  @override
  State<OperationalCallStage> createState() => _OperationalCallStageState();
}

class _OperationalCallStageState extends State<OperationalCallStage> {
  bool micOn = true;
  bool cameraOn = true;
  bool speakerOn = true;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final calls = OperationalCalls.of(context);
    final call = calls.callById(widget.callId);
    final session = TgcgSession.of(context, listen: false);
    final membership = MembershipOperations.of(context);

    if (call == null) {
      return const Scaffold(
        body: Center(child: Text('Call unavailable')),
      );
    }

    final isVideo = call.kind != OperationalCallKind.audio;
    final recipients = call.recipientMemberIds
        .map((id) => membership.memberById(id)?.fullName ?? id)
        .toList(growable: false);
    final status = _statusLabel(call.status);

    return Scaffold(
      backgroundColor: TgcgColors.navy950,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Row(
                children: [
                  const TgcgLogo(size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      recipients.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  TgcgStatusPill(
                    label:
                        'GPS ${call.gpsRecipientCount}/${call.recipientMemberIds.length}',
                    color: call.hasGpsForAllRecipients
                        ? TgcgColors.success
                        : TgcgColors.warning,
                    icon: Icons.gps_fixed_rounded,
                    compact: true,
                  ),
                  const SizedBox(width: 7),
                  TgcgStatusPill(
                    label: status,
                    color: call.status == OperationalCallStatus.active
                        ? TgcgColors.success
                        : call.isOpen
                            ? TgcgColors.info
                            : TgcgColors.muted,
                    compact: true,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: TgcgColors.navy900,
                    borderRadius: BorderRadius.circular(TgcgRadius.lg),
                    border: Border.all(color: Colors.white12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: isVideo && cameraOn
                      ? const LocalCameraView()
                      : Center(
                          child: CircleAvatar(
                            radius: 58,
                            backgroundColor:
                                TgcgColors.primary.withValues(alpha: .22),
                            child: const Icon(
                              Icons.person_rounded,
                              color: Colors.white70,
                              size: 58,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  _CallButton(
                    icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    onTap: () => setState(() => micOn = !micOn),
                  ),
                  if (isVideo)
                    _CallButton(
                      icon: cameraOn
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      onTap: () => setState(() => cameraOn = !cameraOn),
                    ),
                  _CallButton(
                    icon: speakerOn
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    onTap: () => setState(() => speakerOn = !speakerOn),
                  ),
                  _CallButton(
                    icon: Icons.call_end_rounded,
                    danger: true,
                    onTap: busy || !call.isOpen
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              await calls.endCall(
                                callId: call.id,
                                actorId: session.accessId.isEmpty
                                    ? session.operatorName
                                    : session.accessId,
                              );
                              if (context.mounted) Navigator.pop(context);
                            } on StateError catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.message)),
                              );
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IncomingOperationalCallCard extends StatelessWidget {
  const IncomingOperationalCallCard({
    super.key,
    required this.memberId,
  });

  final String memberId;

  @override
  Widget build(BuildContext context) {
    final calls = OperationalCalls.of(context);
    final incoming = calls.incomingForMember(memberId);
    if (incoming.isEmpty) return const SizedBox.shrink();

    final call = incoming.first;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TgcgColors.navy950,
        borderRadius: BorderRadius.circular(TgcgRadius.lg),
        border: Border.all(color: TgcgColors.primary.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: TgcgColors.primary.withValues(alpha: .18),
            child: Icon(
              call.kind == OperationalCallKind.audio
                  ? Icons.call_rounded
                  : Icons.videocam_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  call.callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  call.gpsForMember(memberId) == null
                      ? 'GPS unavailable'
                      : 'GPS active • location attached',
                  style: TextStyle(
                    color: call.gpsForMember(memberId) == null
                        ? TgcgColors.warning
                        : TgcgColors.gold200,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Decline',
            onPressed: () async {
              await calls.declineCall(
                callId: call.id,
                memberId: memberId,
              );
            },
            icon: const Icon(Icons.call_end_rounded),
          ),
          const SizedBox(width: 7),
          IconButton.filled(
            tooltip: 'Answer',
            onPressed: () async {
              try {
                await calls.answerCall(
                  callId: call.id,
                  memberId: memberId,
                );
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OperationalCallStage(callId: call.id),
                  ),
                );
              } on StateError catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error.message)),
                );
              }
            },
            icon: Icon(
              call.kind == OperationalCallKind.audio
                  ? Icons.call_rounded
                  : Icons.videocam_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 54,
        height: 54,
        child: FilledButton(
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor:
                danger ? TgcgColors.danger : Colors.white.withValues(alpha: .12),
            foregroundColor: Colors.white,
          ),
          onPressed: onTap,
          child: Icon(icon),
        ),
      );
}

String _statusLabel(OperationalCallStatus status) => switch (status) {
      OperationalCallStatus.ringing => 'RINGING',
      OperationalCallStatus.active => 'LIVE',
      OperationalCallStatus.ended => 'ENDED',
      OperationalCallStatus.declined => 'DECLINED',
      OperationalCallStatus.cancelled => 'CANCELLED',
      OperationalCallStatus.missed => 'MISSED',
    };
