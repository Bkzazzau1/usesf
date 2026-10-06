import 'package:flutter/material.dart';

import '../access/access_policy.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../geography/kaduna_map.dart';
import '../membership/membership_store.dart';
import '../ui/tgcg_design.dart';
import 'field_operations_store.dart';

class SituationRoomPage extends StatefulWidget {
  const SituationRoomPage({super.key});

  @override
  State<SituationRoomPage> createState() => _SituationRoomPageState();
}

class _SituationRoomPageState extends State<SituationRoomPage> {
  String? selectedIncidentId;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = FieldOperations.of(context);
    final situationScopes = TgcgAccessPolicy.scopesForAny(
      context,
      const [
        TgcgCapability.viewSituationRoom,
        TgcgCapability.viewIncidents,
      ],
    );
    final effectiveScopes = situationScopes.isEmpty
        ? <GeographicScope>[session.scope]
        : situationScopes;
    final incidents = store.incidents
        .where(
          (item) => effectiveScopes.any(
            (scope) => TgcgPermissionPolicy.scopeAllows(scope, item.scope),
          ),
        )
        .toList(growable: false);
    final reports = store.reports
        .where(
          (item) => effectiveScopes.any(
            (scope) => TgcgPermissionPolicy.scopeAllows(scope, item.scope),
          ),
        )
        .toList(growable: false);
    final commandScope = effectiveScopes.length == 1
        ? effectiveScopes.first
        : GeographicScope.kaduna;
    final open =
        incidents
            .where(
              (item) =>
                  item.status != IncidentStatus.resolved &&
                  item.status != IncidentStatus.closed,
            )
            .toList(growable: false)
          ..sort((a, b) {
            final severity = _severityRank(
              b.severity,
            ).compareTo(_severityRank(a.severity));
            if (severity != 0) return severity;
            return b.reportedAt.compareTo(a.reportedAt);
          });

    if (selectedIncidentId == null ||
        !incidents.any((item) => item.id == selectedIncidentId)) {
      selectedIncidentId = open.isNotEmpty
          ? open.first.id
          : incidents.isNotEmpty
          ? incidents.first.id
          : null;
    }

    final selected = selectedIncidentId == null
        ? null
        : incidents.where((item) => item.id == selectedIncidentId).firstOrNull;
    final critical = open
        .where((item) => item.severity == IncidentSeverity.critical)
        .length;
    final high = open
        .where((item) => item.severity == IncidentSeverity.high)
        .length;
    final unassigned = open
        .where(
          (item) =>
              store.currentOwnershipForIncident(item.id) == null &&
              item.assignedTeam == null,
        )
        .length;
    final evidence = incidents.fold<int>(
      0,
      (total, item) => total + item.evidence.length,
    );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TgcgPageHeader(
          eyebrow: 'Live command centre',
          title: 'Situation Room',
          subtitle:
              '${effectiveScopes.length} authorized scope${effectiveScopes.length == 1 ? '' : 's'}: real-time incident command, evidence review and field coordination.',
          trailing: const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TgcgStatusPill(
                label: 'LIVE COMMAND',
                color: TgcgColors.success,
                icon: Icons.circle,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _MetricsStrip(
          open: open.length,
          critical: critical,
          high: high,
          unassigned: unassigned,
          reports: reports.length,
          evidence: evidence,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final priorityRail = _PriorityRail(
              incidents: open,
              selectedIncidentId: selectedIncidentId,
              onSelect: (id) => setState(() => selectedIncidentId = id),
            );
            final map = _CommandMap(
              scope: commandScope,
              incidents: open,
              selectedIncidentId: selectedIncidentId,
              onSelect: (id) => setState(() => selectedIncidentId = id),
            );
            final inspector = _IncidentInspector(
              incident: selected,
            );

            if (constraints.maxWidth < 1180) {
              return Column(
                children: [
                  map,
                  const SizedBox(height: 14),
                  if (constraints.maxWidth >= 760)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: priorityRail),
                        const SizedBox(width: 14),
                        Expanded(child: inspector),
                      ],
                    )
                  else ...[
                    priorityRail,
                    const SizedBox(height: 14),
                    inspector,
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 310, child: priorityRail),
                const SizedBox(width: 14),
                Expanded(child: map),
                const SizedBox(width: 14),
                SizedBox(width: 350, child: inspector),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final timeline = _ActivityTimeline(
              incidents: incidents,
              reports: reports,
              onIncidentSelected: (id) =>
                  setState(() => selectedIncidentId = id),
            );
            final ownership = _ResponseOwnership(incidents: open);
            if (constraints.maxWidth < 900) {
              return Column(
                children: [timeline, const SizedBox(height: 14), ownership],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: timeline),
                const SizedBox(width: 14),
                Expanded(flex: 4, child: ownership),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MetricsStrip extends StatelessWidget {
  const _MetricsStrip({
    required this.open,
    required this.critical,
    required this.high,
    required this.unassigned,
    required this.reports,
    required this.evidence,
  });

  final int open;
  final int critical;
  final int high;
  final int unassigned;
  final int reports;
  final int evidence;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1180
          ? 6
          : constraints.maxWidth >= 760
          ? 3
          : constraints.maxWidth >= 480
          ? 2
          : 1;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          TgcgMetricCard(
            width: width,
            label: 'Open incidents',
            value: '$open',
            detail: 'Unresolved events in scope',
            icon: Icons.warning_amber_rounded,
            tone: TgcgMetricTone.warning,
          ),
          TgcgMetricCard(
            width: width,
            label: 'Critical',
            value: '$critical',
            detail: 'Immediate command attention',
            icon: Icons.crisis_alert_rounded,
            tone: TgcgMetricTone.danger,
          ),
          TgcgMetricCard(
            width: width,
            label: 'High priority',
            value: '$high',
            detail: 'High-severity active incidents',
            icon: Icons.priority_high_rounded,
            tone: TgcgMetricTone.danger,
          ),
          TgcgMetricCard(
            width: width,
            label: 'Unassigned',
            value: '$unassigned',
            detail: 'Awaiting response ownership',
            icon: Icons.person_off_outlined,
            tone: TgcgMetricTone.warning,
          ),
          TgcgMetricCard(
            width: width,
            label: 'Field reports',
            value: '$reports',
            detail: 'Structured operational updates',
            icon: Icons.feed_outlined,
            tone: TgcgMetricTone.info,
          ),
          TgcgMetricCard(
            width: width,
            label: 'Evidence retained',
            value: '$evidence',
            detail: 'Linked media/provenance records',
            icon: Icons.perm_media_outlined,
            tone: TgcgMetricTone.success,
          ),
        ],
      );
    },
  );
}

class _PriorityRail extends StatelessWidget {
  const _PriorityRail({
    required this.incidents,
    required this.selectedIncidentId,
    required this.onSelect,
  });

  final List<FieldIncident> incidents;
  final String? selectedIncidentId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    title: 'Priority queue',
    subtitle: 'Severity first, then most recent.',
    child: incidents.isEmpty
        ? const TgcgEmptyState(
            icon: Icons.task_alt_rounded,
            title: 'No active incidents',
            message: 'There are no unresolved incidents in this scope.',
          )
        : Column(
            children: incidents
                .map(
                  (incident) => _PriorityItem(
                    incident: incident,
                    selected: incident.id == selectedIncidentId,
                    onTap: () => onSelect(incident.id),
                  ),
                )
                .toList(),
          ),
  );
}

class _PriorityItem extends StatelessWidget {
  const _PriorityItem({
    required this.incident,
    required this.selected,
    required this.onTap,
  });

  final FieldIncident incident;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(incident.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: selected ? color.withValues(alpha: .07) : TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TgcgRadius.md),
              border: Border.all(
                color: selected
                    ? color.withValues(alpha: .55)
                    : TgcgColors.border,
                width: selected ? 1.4 : 1,
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x0D06162D),
                        blurRadius: 14,
                        offset: Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(TgcgRadius.sm),
                    border: Border.all(color: color.withValues(alpha: .12)),
                  ),
                  child: Icon(
                    Icons.crisis_alert_outlined,
                    color: color,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        incident.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        incident.scope.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          TgcgStatusPill(
                            label: _label(incident.severity.name),
                            color: color,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label: _label(incident.status.name),
                            color: TgcgColors.primaryMid,
                            compact: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandMap extends StatelessWidget {
  const _CommandMap({
    required this.scope,
    required this.incidents,
    required this.selectedIncidentId,
    required this.onSelect,
  });

  final GeographicScope scope;
  final List<FieldIncident> incidents;
  final String? selectedIncidentId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    title: 'Live operational map',
    subtitle:
        'Open incidents plotted on Kaduna State LGA boundaries. Select a marker or an LGA to inspect it.',
    trailing: const TgcgStatusPill(
      label: 'LGA VIEW',
      color: TgcgColors.info,
      icon: Icons.map_outlined,
      compact: true,
    ),
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
    child: Column(
      children: [
        Container(
          height: 540,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: TgcgGradients.navigation,
            borderRadius: BorderRadius.circular(TgcgRadius.lg),
            border: Border.all(color: TgcgColors.accent.withValues(alpha: .18)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1606162D),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 56, 20, 40),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: kadunaMapAspectRatio,
                          child: _IncidentMapLayer(
                            incidents: incidents,
                            selectedIncidentId: selectedIncidentId,
                            onSelect: onSelect,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    top: 16,
                    child: TgcgStatusPill(
                      label: scope.label.toUpperCase(),
                      color: TgcgColors.accent,
                      icon: Icons.location_on_outlined,
                      compact: true,
                    ),
                  ),
                  Positioned(
                    right: 18,
                    top: 16,
                    child: Wrap(
                      spacing: 10,
                      children: const [
                        _MapLegend(
                          label: 'Critical / high',
                          color: TgcgColors.danger,
                        ),
                        _MapLegend(label: 'Medium', color: TgcgColors.warning),
                        _MapLegend(label: 'Low / info', color: TgcgColors.info),
                      ],
                    ),
                  ),
                  if (incidents.isEmpty)
                    const Center(
                      child: Text(
                        'No active incident markers in this scope',
                        style: TextStyle(
                          color: Color(0xFFB6BED0),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const Positioned(
                    left: 18,
                    right: 18,
                    bottom: 14,
                    child: Row(
                      children: [
                        Icon(
                          Icons.layers_outlined,
                          color: Color(0xFFB6BED0),
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Incidents by LGA  •  23 LGAs  •  3 senatorial zones',
                          style: TextStyle(
                            color: Color(0xFFB6BED0),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: TgcgColors.muted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${incidents.length} active incident marker${incidents.length == 1 ? '' : 's'} in the authorized scope, placed at each incident\'s LGA. Polling-unit precision follows once GIS coordinates are captured.',
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Kaduna LGA map in the command palette, with an incident pin per open
/// incident at its LGA (several incidents in one LGA fan out sideways).
class _IncidentMapLayer extends StatelessWidget {
  const _IncidentMapLayer({
    required this.incidents,
    required this.selectedIncidentId,
    required this.onSelect,
  });

  final List<FieldIncident> incidents;
  final String? selectedIncidentId;
  final ValueChanged<String> onSelect;

  static const _land = Color(0xFF173A68);

  @override
  Widget build(BuildContext context) {
    final byLga = <String, List<FieldIncident>>{};
    for (final incident in incidents) {
      final lgaId = incident.scope.lgaId;
      if (lgaId != null) byLga.putIfAbsent(lgaId, () => []).add(incident);
    }
    for (final list in byLga.values) {
      list.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    }
    String? selectedLga;
    for (final incident in incidents) {
      if (incident.id == selectedIncidentId) selectedLga = incident.scope.lgaId;
    }

    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final pins = <Widget>[];
        byLga.forEach((lgaId, list) {
          final anchor = kadunaLgaLabelPosition(lgaId, size);
          if (anchor == null) return;
          // Kaduna South's leader label sits just under Kaduna North's, so its
          // pins go below the label instead of above it.
          final below = lgaId == 'KD-KADUNA-SOUTH';
          for (var i = 0; i < list.length; i++) {
            final incident = list[i];
            pins.add(
              Positioned(
                left: anchor.dx - 21,
                top: below ? anchor.dy + 14 + i * 46 : anchor.dy - 50 - i * 46,
                child: _MapIncidentNode(
                  incident: incident,
                  color: _severityColor(incident.severity),
                  selected: incident.id == selectedIncidentId,
                  onTap: () => onSelect(incident.id),
                ),
              ),
            );
          }
        });
        // Draw the selected pin last so its expanded label sits on top.
        pins.sort((a, b) {
          bool sel(Widget w) =>
              ((w as Positioned).child as _MapIncidentNode).selected;
          return (sel(a) ? 1 : 0).compareTo(sel(b) ? 1 : 0);
        });

        return Stack(
          clipBehavior: Clip.none,
          children: [
            KadunaMap(
              selectedLgaId: selectedLga,
              fillColor: (lgaId) {
                final list = byLga[lgaId];
                if (list == null) return _land;
                return Color.lerp(
                  _land,
                  _severityColor(list.first.severity),
                  .55,
                )!;
              },
              labelColor: (_) => Colors.white.withValues(alpha: .78),
              onLgaTap: (lgaId) {
                final list = byLga[lgaId];
                if (list != null) onSelect(list.first.id);
              },
            ),
            ...pins,
          ],
        );
      },
    );
  }
}

class _MapIncidentNode extends StatelessWidget {
  const _MapIncidentNode({
    required this.incident,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final FieldIncident incident;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(13),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: selected ? 142 : 42,
      height: 42,
      padding: EdgeInsets.symmetric(horizontal: selected ? 9 : 0),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF111F41) : color,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: selected ? color : Colors.white.withValues(alpha: .3),
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .25),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: selected
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_on_rounded, color: Colors.white, size: 19),
          if (selected) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                incident.scope.lgaName ?? incident.scope.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 9.5,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(color: Color(0xFFB6BED0), fontSize: 9.5),
      ),
    ],
  );
}

class _IncidentInspector extends StatelessWidget {
  const _IncidentInspector({required this.incident});

  final FieldIncident? incident;

  @override
  Widget build(BuildContext context) {
    final item = incident;
    if (item == null) {
      return const TgcgSectionCard(
        title: 'Incident inspector',
        subtitle: 'Select an incident from the queue or map.',
        child: TgcgEmptyState(
          icon: Icons.touch_app_outlined,
          title: 'Nothing selected',
          message:
              'Select an incident to inspect evidence and command actions.',
        ),
      );
    }

    final color = _severityColor(item.severity);
    final store = FieldOperations.of(context);
    final currentOwnership = store.currentOwnershipForIncident(item.id);
    final ownershipHistory = store.ownershipHistoryForIncident(item.id);
    final canAcknowledge = TgcgAccessPolicy.allows(
      context,
      TgcgCapability.acknowledgeIncident,
      targetScope: item.scope,
    );
    final canAssign = TgcgAccessPolicy.allows(
      context,
      TgcgCapability.assignIncident,
      targetScope: item.scope,
    );
    final canClose = TgcgAccessPolicy.allows(
      context,
      TgcgCapability.closeIncident,
      targetScope: item.scope,
    );

    return TgcgSectionCard(
      title: 'Incident inspector',
      subtitle: item.id,
      trailing: TgcgStatusPill(
        label: _label(item.severity.name),
        color: color,
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontSize: 15,
              height: 1.3,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.summary ?? 'No additional incident summary was supplied.',
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          _InspectorLine(
            icon: Icons.category_outlined,
            label: 'Category',
            value: item.category,
          ),
          _InspectorLine(
            icon: Icons.location_on_outlined,
            label: 'Location',
            value: item.scope.label,
          ),
          _InspectorLine(
            icon: Icons.person_outline_rounded,
            label: 'Reporter',
            value: item.reporterId,
          ),
          _InspectorLine(
            icon: Icons.groups_2_outlined,
            label: 'Response owner',
            value: store.ownershipLabelForIncident(item),
          ),
          if (currentOwnership != null)
            _InspectorLine(
              icon: Icons.schedule_outlined,
              label: 'Assigned',
              value: _timeLabel(currentOwnership.changedAt),
            ),
          _InspectorLine(
            icon: Icons.schedule_rounded,
            label: 'Reported',
            value: _timeLabel(item.reportedAt),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TgcgStatusPill(
                label: _label(item.status.name),
                color: TgcgColors.primaryMid,
                compact: true,
              ),
              const Spacer(),
              Text(
                '${item.evidence.length} evidence',
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (item.evidence.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: TgcgColors.surfaceSoft,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: TgcgColors.border),
              ),
              child: const Text(
                'No linked media evidence for this incident.',
                style: TextStyle(color: TgcgColors.muted, fontSize: 10.5),
              ),
            )
          else
            ...item.evidence.map(
              (evidence) => _EvidenceTile(evidence: evidence),
            ),
          if (ownershipHistory.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              'Ownership history',
              style: TextStyle(
                color: TgcgColors.ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            ...ownershipHistory.reversed.take(4).map(
              (event) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TgcgColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: TgcgColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.action == IncidentOwnershipAction.cleared
                          ? 'Ownership cleared'
                          : event.ownerLabel,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_label(event.action.name)} by ${event.actorId} • ${_timeLabel(event.changedAt)}',
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 9.5,
                      ),
                    ),
                    if (event.note != null && event.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.note!,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (canAcknowledge || canAssign || canClose) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            const Text(
              'Command actions',
              style: TextStyle(
                color: TgcgColors.ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canAssign &&
                    item.status != IncidentStatus.resolved &&
                    item.status != IncidentStatus.closed)
                  FilledButton.icon(
                    onPressed: () => _assignIncidentOwner(context, item),
                    icon: Icon(
                      currentOwnership == null
                          ? Icons.person_add_alt_1_outlined
                          : Icons.manage_accounts_outlined,
                      size: 17,
                    ),
                    label: Text(
                      currentOwnership == null && item.assignedTeam == null
                          ? 'Assign owner'
                          : 'Reassign owner',
                    ),
                  ),
                if (canAssign &&
                    (currentOwnership != null || item.assignedTeam != null) &&
                    item.status != IncidentStatus.resolved &&
                    item.status != IncidentStatus.closed)
                  OutlinedButton.icon(
                    onPressed: () => _clearIncidentOwner(context, item),
                    icon: const Icon(Icons.person_off_outlined, size: 17),
                    label: const Text('Clear owner'),
                  ),
                if (canAcknowledge && item.status == IncidentStatus.reported)
                  FilledButton.icon(
                    onPressed: () => _changeIncidentStatus(
                      context,
                      item,
                      IncidentStatus.acknowledged,
                    ),
                    icon: const Icon(Icons.done_rounded, size: 17),
                    label: const Text('Acknowledge'),
                  ),
                if (canAssign &&
                    item.status != IncidentStatus.investigating &&
                    item.status != IncidentStatus.resolved &&
                    item.status != IncidentStatus.closed)
                  OutlinedButton.icon(
                    onPressed: () => _changeIncidentStatus(
                      context,
                      item,
                      IncidentStatus.investigating,
                    ),
                    icon: const Icon(Icons.manage_search_rounded, size: 17),
                    label: const Text('Investigate'),
                  ),
                if (canAssign &&
                    (item.severity == IncidentSeverity.high ||
                        item.severity == IncidentSeverity.critical) &&
                    item.status != IncidentStatus.escalated)
                  OutlinedButton.icon(
                    onPressed: () => _changeIncidentStatus(
                      context,
                      item,
                      IncidentStatus.escalated,
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                    label: const Text('Escalate'),
                  ),
                if (canClose &&
                    item.status != IncidentStatus.resolved &&
                    item.status != IncidentStatus.closed)
                  OutlinedButton.icon(
                    onPressed: () => _changeIncidentStatus(
                      context,
                      item,
                      IncidentStatus.resolved,
                    ),
                    icon: const Icon(Icons.task_alt_rounded, size: 17),
                    label: const Text('Resolve'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _assignIncidentOwner(
  BuildContext context,
  FieldIncident item,
) async {
  final session = TgcgSession.of(context, listen: false);
  final actorRole = TgcgAccessPolicy.roleFor(
    context,
    TgcgCapability.assignIncident,
    targetScope: item.scope,
    listen: false,
  );
  final authorizedScope = TgcgAccessPolicy.authorizingScope(
    context,
    TgcgCapability.assignIncident,
    targetScope: item.scope,
    listen: false,
  );
  if (actorRole == null || authorizedScope == null) return;

  final store = FieldOperations.of(context, listen: false);
  final membership = MembershipOperations.of(context, listen: false);
  final current = store.currentOwnershipForIncident(item.id);
  final candidates = membership.members.where((member) {
    if (member.isBlocked) return false;
    final memberScope = membership.registrationScopeForMember(member.id);
    return memberScope != null &&
        TgcgPermissionPolicy.scopeAllows(memberScope, item.scope);
  }).toList(growable: false)
    ..sort((a, b) => a.fullName.compareTo(b.fullName));

  var selectedMemberId = current?.responsibleMemberId;
  if (selectedMemberId != null &&
      !candidates.any((member) => member.id == selectedMemberId)) {
    selectedMemberId = null;
  }
  final teamController = TextEditingController(text: current?.teamName ?? '');
  final noteController = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(
          current == null ? 'Assign incident owner' : 'Reassign incident owner',
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String?>(
                value: selectedMemberId,
                decoration: const InputDecoration(
                  labelText: 'Responsible officer',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Team only / no specific officer'),
                  ),
                  ...candidates.map(
                    (member) => DropdownMenuItem<String?>(
                      value: member.id,
                      child: Text(
                        member.fullName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => selectedMemberId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: teamController,
                decoration: const InputDecoration(
                  labelText: 'Response team / desk',
                  prefixIcon: Icon(Icons.groups_2_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Assignment note (optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
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
          FilledButton(
            onPressed: () {
              if (selectedMemberId == null &&
                  teamController.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Select a responsible officer or enter a response team.',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: Text(current == null ? 'Assign' : 'Reassign'),
          ),
        ],
      ),
    ),
  );

  try {
    if (confirmed == true) {
      await store.assignIncidentOwnership(
        item.id,
        responsibleMemberId: selectedMemberId,
        teamName: teamController.text,
        note: noteController.text,
        actorId:
            session.accessId.isEmpty ? session.operatorName : session.accessId,
        actorRole: actorRole,
        authorizedScope: authorizedScope,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incident ownership updated.')),
        );
      }
    }
  } on StateError catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  } finally {
    teamController.dispose();
    noteController.dispose();
  }
}

Future<void> _clearIncidentOwner(
  BuildContext context,
  FieldIncident item,
) async {
  final session = TgcgSession.of(context, listen: false);
  final actorRole = TgcgAccessPolicy.roleFor(
    context,
    TgcgCapability.assignIncident,
    targetScope: item.scope,
    listen: false,
  );
  final authorizedScope = TgcgAccessPolicy.authorizingScope(
    context,
    TgcgCapability.assignIncident,
    targetScope: item.scope,
    listen: false,
  );
  if (actorRole == null || authorizedScope == null) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Clear incident ownership?'),
      content: const Text(
        'The incident will remain open, but it will return to the unassigned command queue.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Clear ownership'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await FieldOperations.of(context, listen: false).clearIncidentOwnership(
      item.id,
      actorId:
          session.accessId.isEmpty ? session.operatorName : session.accessId,
      actorRole: actorRole,
      authorizedScope: authorizedScope,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incident returned to unassigned queue.')),
      );
    }
  } on StateError catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }
}

/// Changes an incident's status with the role and scope that authorize that
/// specific transition for the signed-in member (same rule as Field
/// Monitoring), surfacing any refusal from the durable store.
Future<void> _changeIncidentStatus(
  BuildContext context,
  FieldIncident item,
  IncidentStatus status,
) async {
  final session = TgcgSession.of(context, listen: false);
  final capability = incidentStatusMutationCapability(status);
  final actorRole = TgcgAccessPolicy.roleFor(
    context,
    capability,
    targetScope: item.scope,
    listen: false,
  );
  final authorizedScope = TgcgAccessPolicy.authorizingScope(
    context,
    capability,
    targetScope: item.scope,
    listen: false,
  );
  if (actorRole == null || authorizedScope == null) return;
  try {
    await FieldOperations.of(context, listen: false).updateIncidentStatus(
      item.id,
      status,
      actorId: session.accessId.isEmpty ? session.operatorName : session.accessId,
      actorRole: actorRole,
      authorizedScope: authorizedScope,
    );
  } on StateError catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.message)),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.evidence});

  final EvidenceAttachment evidence;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: TgcgColors.surfaceSoft,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: TgcgColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: TgcgColors.primaryDark,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            _evidenceIcon(evidence.type),
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                evidence.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _label(evidence.type.name),
                style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
              ),
              if (evidence.contentHash != null) ...[
                const SizedBox(height: 4),
                Text(
                  evidence.contentHash!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TgcgColors.success,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _InspectorLine extends StatelessWidget {
  const _InspectorLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: TgcgColors.muted),
        const SizedBox(width: 8),
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
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

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({
    required this.incidents,
    required this.reports,
    required this.onIncidentSelected,
  });

  final List<FieldIncident> incidents;
  final List<FieldReport> reports;
  final ValueChanged<String> onIncidentSelected;

  @override
  Widget build(BuildContext context) {
    final events = <_ActivityEvent>[
      ...incidents.map(
        (incident) => _ActivityEvent(
          title: incident.title,
          subtitle: '${incident.scope.label} • ${_label(incident.status.name)}',
          timestamp: incident.reportedAt,
          icon: Icons.crisis_alert_outlined,
          color: _severityColor(incident.severity),
          incidentId: incident.id,
        ),
      ),
      ...reports.map(
        (report) => _ActivityEvent(
          title: report.category,
          subtitle: '${report.scope.label} • ${report.summary}',
          timestamp: report.reportedAt,
          icon: Icons.feed_outlined,
          color: TgcgColors.info,
          incidentId: report.incidentId,
        ),
      ),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return TgcgSectionCard(
      title: 'Live event stream',
      subtitle: 'Latest incidents and structured field reports in this scope.',
      child: events.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.timeline_outlined,
              title: 'No activity yet',
              message: 'New incidents and field reports will appear here.',
            )
          : Column(
              children: events.take(8).map((event) {
                return InkWell(
                  onTap: event.incidentId == null
                      ? null
                      : () => onIncidentSelected(event.incidentId!),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: event.color.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(event.icon, color: event.color, size: 17),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: TgcgColors.ink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                event.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 9.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeLabel(event.timestamp),
                          style: const TextStyle(
                            color: TgcgColors.muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _ResponseOwnership extends StatelessWidget {
  const _ResponseOwnership({required this.incidents});

  final List<FieldIncident> incidents;

  @override
  Widget build(BuildContext context) {
    final groups = <String, int>{};
    final store = FieldOperations.of(context);
    for (final incident in incidents) {
      final key = store.ownershipLabelForIncident(incident);
      groups[key] = (groups[key] ?? 0) + 1;
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return TgcgSectionCard(
      title: 'Response ownership',
      subtitle: 'Open incidents by current response desk.',
      child: entries.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.groups_2_outlined,
              title: 'No active ownership',
              message: 'There are no open incidents assigned in this scope.',
            )
          : Column(
              children: entries.map((entry) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TgcgColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: TgcgColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 35,
                        height: 35,
                        decoration: BoxDecoration(
                          color: TgcgColors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.groups_2_outlined,
                          color: TgcgColors.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          entry.key,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: entry.key == 'Unassigned'
                              ? TgcgColors.warning.withValues(alpha: .09)
                              : TgcgColors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${entry.value}',
                          style: TextStyle(
                            color: entry.key == 'Unassigned'
                                ? TgcgColors.warning
                                : TgcgColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
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

class _ActivityEvent {
  const _ActivityEvent({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.icon,
    required this.color,
    this.incidentId,
  });

  final String title;
  final String subtitle;
  final DateTime timestamp;
  final IconData icon;
  final Color color;
  final String? incidentId;
}

int _severityRank(IncidentSeverity severity) => switch (severity) {
  IncidentSeverity.critical => 5,
  IncidentSeverity.high => 4,
  IncidentSeverity.medium => 3,
  IncidentSeverity.low => 2,
  IncidentSeverity.info => 1,
};

Color _severityColor(IncidentSeverity severity) => switch (severity) {
  IncidentSeverity.critical => TgcgColors.danger,
  IncidentSeverity.high => const Color(0xFFD92D20),
  IncidentSeverity.medium => TgcgColors.warning,
  IncidentSeverity.low => TgcgColors.info,
  IncidentSeverity.info => TgcgColors.muted,
};

IconData _evidenceIcon(EvidenceType type) => switch (type) {
  EvidenceType.photo => Icons.image_outlined,
  EvidenceType.video => Icons.videocam_outlined,
  EvidenceType.audio => Icons.mic_none_rounded,
  EvidenceType.document => Icons.attach_file_rounded,
  EvidenceType.resultForm => Icons.description_outlined,
  EvidenceType.location => Icons.location_on_outlined,
};

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
