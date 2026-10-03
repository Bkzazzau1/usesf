import 'package:flutter/material.dart';

import '../field/field_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'emergency_response_store.dart';
import 'security_portal_login_page.dart';

/// Workspace for a signed-in Security Officer: dispatches assigned to the
/// officer's agency within their command area, and the response workflow
/// (acknowledge → en route → on scene → resolved) that the Situation Room
/// tracks live.
class SecurityAgencyShell extends StatelessWidget {
  const SecurityAgencyShell({super.key});

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final emergency = EmergencyResponse.of(context);
    final field = FieldOperations.of(context);
    final agency = session.agencyId == null ? null : emergency.agencyById(session.agencyId!);

    final dispatches = agency == null
        ? const <EmergencyDispatch>[]
        : emergency
            .dispatchesForScope(session.scope)
            .where((item) => item.agencyId == agency.id)
            .toList(growable: false);
    final active = dispatches.where((item) => !_isFinished(item.status)).toList()
      ..sort(_byUrgency);
    final finished = dispatches.where((item) => _isFinished(item.status)).toList();

    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: TgcgGradients.commandBar,
            border: Border(bottom: BorderSide(color: TgcgColors.gold200)),
          ),
        ),
        titleSpacing: 14,
        title: Row(
          children: [
            const TgcgLogo(size: 34),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SECURITY PORTAL',
                    style: TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${agency?.name ?? 'Agency'} • ${session.scope.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: session.signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: agency == null
          ? const Center(
              child: TgcgEmptyState(
                icon: Icons.gpp_bad_outlined,
                title: 'Agency not recognised',
                message: 'Sign out and sign in again through the Security Portal.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _OfficerHero(
                          session: session,
                          agency: agency,
                          dispatches: dispatches,
                        ),
                        const SizedBox(height: 18),
                        TgcgSectionCard(
                          title: 'Active dispatches',
                          subtitle:
                              'Assigned by the Situation Room. Update your status at each stage so command can track the response.',
                          trailing: TgcgStatusPill(
                            label: '${active.length} ACTIVE',
                            color: active.isEmpty ? TgcgColors.success : TgcgColors.danger,
                            compact: true,
                          ),
                          child: active.isEmpty
                              ? const TgcgEmptyState(
                                  icon: Icons.verified_user_outlined,
                                  title: 'No active dispatch',
                                  message: 'New assignments for your agency will appear here immediately.',
                                )
                              : Column(
                                  children: active
                                      .map(
                                        (dispatch) => _DispatchCard(
                                          dispatch: dispatch,
                                          incident: _incident(field, dispatch.incidentId),
                                          onAdvance: (next) => emergency.updateStatus(
                                            dispatchId: dispatch.id,
                                            status: next,
                                            actorId: session.accessId,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                        ),
                        if (finished.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          TgcgSectionCard(
                            title: 'Completed',
                            subtitle: 'Resolved and closed dispatches for this shift.',
                            child: Column(
                              children: finished
                                  .map(
                                    (dispatch) => _DispatchCard(
                                      dispatch: dispatch,
                                      incident: _incident(field, dispatch.incidentId),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static FieldIncident? _incident(FieldOperationsController field, String id) {
    for (final item in field.incidents) {
      if (item.id == id) return item;
    }
    return null;
  }

  static int _byUrgency(EmergencyDispatch a, EmergencyDispatch b) {
    final priority = b.priority.index.compareTo(a.priority.index);
    return priority != 0 ? priority : b.assignedAt.compareTo(a.assignedAt);
  }
}

bool _isFinished(EmergencyDispatchStatus status) =>
    status == EmergencyDispatchStatus.resolved || status == EmergencyDispatchStatus.closed;

class _OfficerHero extends StatelessWidget {
  const _OfficerHero({
    required this.session,
    required this.agency,
    required this.dispatches,
  });

  final TgcgSessionController session;
  final EmergencyAgency agency;
  final List<EmergencyDispatch> dispatches;

  int _count(EmergencyDispatchStatus status) =>
      dispatches.where((item) => item.status == status).length;

  @override
  Widget build(BuildContext context) {
    final awaiting = _count(EmergencyDispatchStatus.assigned);
    final enRoute = _count(EmergencyDispatchStatus.acknowledged) +
        _count(EmergencyDispatchStatus.responding);
    final onScene = _count(EmergencyDispatchStatus.onScene);
    final resolved = dispatches.where((item) => _isFinished(item.status)).length;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: TgcgGradients.brand,
        borderRadius: BorderRadius.circular(TgcgRadius.xl),
        boxShadow: TgcgShadows.elevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: TgcgColors.accent.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(TgcgRadius.md),
                  border: Border.all(color: TgcgColors.accent.withValues(alpha: .5)),
                ),
                child: Icon(agencyIcon(agency.type), color: TgcgColors.accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.operatorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${agency.shortName} • ${session.accessId} • ${session.scope.label}',
                      style: const TextStyle(color: TgcgColors.gold400, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (awaiting > 0)
                TgcgStatusPill(
                  label: '$awaiting AWAITING',
                  color: TgcgColors.danger,
                  icon: Icons.notifications_active_rounded,
                ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 620 ? 4 : 2;
              const gap = 10.0;
              final width = (box.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _HeroStat(width, '$awaiting', 'Awaiting acknowledgement'),
                  _HeroStat(width, '$enRoute', 'Acknowledged / en route'),
                  _HeroStat(width, '$onScene', 'On scene'),
                  _HeroStat(width, '$resolved', 'Resolved'),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Command desk: ${agency.commandDesk} • ${agency.contactPhone}',
            style: const TextStyle(color: Colors.white60, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(this.width, this.value, this.label);

  final double width;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      );
}

class _DispatchCard extends StatelessWidget {
  const _DispatchCard({
    required this.dispatch,
    required this.incident,
    this.onAdvance,
  });

  final EmergencyDispatch dispatch;
  final FieldIncident? incident;
  final ValueChanged<EmergencyDispatchStatus>? onAdvance;

  @override
  Widget build(BuildContext context) {
    final priority = _priorityColor(dispatch.priority);
    final next = _nextStep(dispatch.status);

    // Rounded corners need a uniform border colour, so the priority stripe is
    // drawn as its own strip inside the clipped card.
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: TgcgColors.surface,
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        border: Border.all(color: TgcgColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: priority),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _body(next),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(_Step? next) {
    final priority = _priorityColor(dispatch.priority);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TgcgStatusPill(
                label: dispatch.priority.name.toUpperCase(),
                color: priority,
                compact: true,
              ),
              TgcgStatusPill(
                label: _statusLabel(dispatch.status).toUpperCase(),
                color: _statusColor(dispatch.status),
                compact: true,
              ),
              Text(
                '${dispatch.id} • ${dispatch.incidentId} • assigned ${_time(dispatch.assignedAt)}',
                style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            incident?.title ?? 'Incident ${dispatch.incidentId}',
            style: const TextStyle(
              color: TgcgColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 15, color: TgcgColors.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  dispatch.scope.label,
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 11.5),
                ),
              ),
            ],
          ),
          if (incident?.summary != null) ...[
            const SizedBox(height: 8),
            Text(
              incident!.summary!,
              style: const TextStyle(color: TgcgColors.ink, fontSize: 12, height: 1.4),
            ),
          ],
          if (dispatch.instructions != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: TgcgColors.accentSoft,
                borderRadius: BorderRadius.circular(TgcgRadius.sm),
                border: Border.all(color: TgcgColors.gold200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.campaign_outlined, size: 16, color: TgcgColors.gold700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Situation Room: ${dispatch.instructions}',
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _Timeline(dispatch: dispatch),
          if (onAdvance != null && next != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => onAdvance!(next.status),
                icon: Icon(next.icon, size: 18),
                label: Text(next.label),
                style: dispatch.status == EmergencyDispatchStatus.assigned
                    ? FilledButton.styleFrom(
                        backgroundColor: TgcgColors.accent,
                        foregroundColor: TgcgColors.primaryDark,
                      )
                    : null,
              ),
            ),
          ],
        ],
      );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.dispatch});

  final EmergencyDispatch dispatch;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, DateTime?)>[
      ('Assigned', dispatch.assignedAt),
      ('Acknowledged', dispatch.acknowledgedAt),
      ('En route', dispatch.respondingAt),
      ('On scene', dispatch.onSceneAt),
      ('Resolved', dispatch.resolvedAt),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: steps.map((step) {
        final done = step.$2 != null;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: done ? TgcgColors.primarySoft : TgcgColors.surfaceSoft,
            borderRadius: BorderRadius.circular(TgcgRadius.sm),
            border: Border.all(color: done ? TgcgColors.navy700.withValues(alpha: .3) : TgcgColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 13,
                color: done ? TgcgColors.primary : TgcgColors.muted,
              ),
              const SizedBox(width: 5),
              Text(
                done ? '${step.$1} ${_time(step.$2!)}' : step.$1,
                style: TextStyle(
                  color: done ? TgcgColors.primary : TgcgColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

typedef _Step = ({EmergencyDispatchStatus status, String label, IconData icon});

_Step? _nextStep(EmergencyDispatchStatus status) => switch (status) {
      EmergencyDispatchStatus.assigned => (
          status: EmergencyDispatchStatus.acknowledged,
          label: 'Acknowledge dispatch',
          icon: Icons.notifications_active_outlined,
        ),
      EmergencyDispatchStatus.acknowledged => (
          status: EmergencyDispatchStatus.responding,
          label: 'Mark en route',
          icon: Icons.directions_car_filled_outlined,
        ),
      EmergencyDispatchStatus.responding => (
          status: EmergencyDispatchStatus.onScene,
          label: 'Arrived on scene',
          icon: Icons.place_rounded,
        ),
      EmergencyDispatchStatus.onScene => (
          status: EmergencyDispatchStatus.resolved,
          label: 'Mark resolved',
          icon: Icons.verified_rounded,
        ),
      EmergencyDispatchStatus.resolved || EmergencyDispatchStatus.closed => null,
    };

String _statusLabel(EmergencyDispatchStatus status) => switch (status) {
      EmergencyDispatchStatus.assigned => 'Awaiting acknowledgement',
      EmergencyDispatchStatus.acknowledged => 'Acknowledged',
      EmergencyDispatchStatus.responding => 'En route',
      EmergencyDispatchStatus.onScene => 'On scene',
      EmergencyDispatchStatus.resolved => 'Resolved',
      EmergencyDispatchStatus.closed => 'Closed',
    };

Color _statusColor(EmergencyDispatchStatus status) => switch (status) {
      EmergencyDispatchStatus.assigned => TgcgColors.danger,
      EmergencyDispatchStatus.acknowledged => TgcgColors.info,
      EmergencyDispatchStatus.responding => TgcgColors.info,
      EmergencyDispatchStatus.onScene => TgcgColors.ai,
      EmergencyDispatchStatus.resolved => TgcgColors.success,
      EmergencyDispatchStatus.closed => TgcgColors.muted,
    };

Color _priorityColor(EmergencyDispatchPriority priority) => switch (priority) {
      EmergencyDispatchPriority.routine => TgcgColors.info,
      EmergencyDispatchPriority.urgent => TgcgColors.warning,
      EmergencyDispatchPriority.critical => TgcgColors.danger,
    };

String _time(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
