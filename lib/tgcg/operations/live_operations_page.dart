import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../field/field_operations_store.dart';
import '../geography/geography_registry.dart';
import '../geography/kaduna_map.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../security/emergency_response_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

class LiveOperationsPage extends StatefulWidget {
  const LiveOperationsPage({super.key});

  @override
  State<LiveOperationsPage> createState() => _LiveOperationsPageState();
}

class _LiveOperationsPageState extends State<LiveOperationsPage> {
  String? selectedLgaId;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final field = FieldOperations.of(context);
    final membership = MembershipOperations.of(context);
    final results = ResultOperations.of(context);
    final emergency = EmergencyResponse.of(context);
    final geography = membership.geography;

    final snapshots = geography.lgas
        .where((lga) => _lgaVisibleToScope(session.scope, lga))
        .map(
          (lga) => _LgaSnapshot.build(
            lga: lga,
            field: field,
            membership: membership,
            results: results,
            emergency: emergency,
          ),
        )
        .toList(growable: false);

    if (snapshots.isNotEmpty &&
        (selectedLgaId == null ||
            !snapshots.any((item) => item.lga.id == selectedLgaId))) {
      selectedLgaId = _preferredLga(snapshots).lga.id;
    }

    final selected = _snapshotById(snapshots, selectedLgaId);
    final openIncidents = snapshots.fold<int>(
      0,
      (total, item) => total + item.openIncidents.length,
    );
    final activeResponses = snapshots.fold<int>(
      0,
      (total, item) => total + item.activeDispatches.length,
    );
    final resultSubmissions = snapshots.fold<int>(
      0,
      (total, item) => total + item.results.length,
    );
    final approvedAgents = snapshots.fold<int>(
      0,
      (total, item) => total + item.approvedAgents,
    );
    final attentionLgas = snapshots
        .where(
          (item) => item.condition.index >= _SituationCondition.elevated.index,
        )
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'KADUNA STATE OPERATIONAL PICTURE',
          title: 'Kaduna Situation Map',
          subtitle:
              '${session.scope.label}: LGA-by-LGA incidents, emergency response, field activity and submission status.',
          trailing: const TgcgStatusPill(
            label: 'CURRENT VIEW',
            color: TgcgColors.success,
            icon: Icons.public_rounded,
          ),
        ),
        const SizedBox(height: 18),
        _TopMetrics(
          lgas: snapshots.length,
          attentionLgas: attentionLgas,
          openIncidents: openIncidents,
          activeResponses: activeResponses,
          resultSubmissions: resultSubmissions,
          approvedAgents: approvedAgents,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final map = _KadunaLgaMap(
              allLgas: geography.lgas,
              snapshots: snapshots,
              selectedLgaId: selectedLgaId,
              onSelect: (value) => setState(() => selectedLgaId = value),
            );
            final detail = _LgaInspector(
              snapshot: selected,
              emergency: emergency,
            );

            if (constraints.maxWidth < 1050) {
              return Column(
                children: [map, const SizedBox(height: 16), detail],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: map),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: detail),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _ZoneOverview(
          geography: geography,
          snapshots: snapshots,
          selectedLgaId: selectedLgaId,
          onSelectLga: (lgaId) => setState(() => selectedLgaId = lgaId),
        ),
        const SizedBox(height: 16),
        _OperationalActivity(snapshots: snapshots, emergency: emergency),
      ],
    );
  }
}

bool _lgaVisibleToScope(GeographicScope scope, CanonicalLga lga) =>
    GeographyRegistry.scopeContains(scope, lga.scope) || scope.lgaId == lga.id;

_LgaSnapshot? _snapshotById(List<_LgaSnapshot> snapshots, String? lgaId) {
  if (lgaId == null) return null;
  for (final item in snapshots) {
    if (item.lga.id == lgaId) return item;
  }
  return null;
}

_LgaSnapshot _preferredLga(List<_LgaSnapshot> snapshots) {
  var selected = snapshots.first;
  for (final item in snapshots.skip(1)) {
    if (item.condition.index > selected.condition.index) {
      selected = item;
      continue;
    }
    if (item.condition == selected.condition &&
        item.openIncidents.length > selected.openIncidents.length) {
      selected = item;
    }
  }
  return selected;
}

enum _SituationCondition { noData, normal, elevated, serious, critical }

class _LgaSnapshot {
  const _LgaSnapshot({
    required this.lga,
    required this.members,
    required this.agents,
    required this.approvedAgents,
    required this.incidents,
    required this.reports,
    required this.results,
    required this.dispatches,
    required this.condition,
  });

  final CanonicalLga lga;
  final int members;
  final int agents;
  final int approvedAgents;
  final List<FieldIncident> incidents;
  final List<FieldReport> reports;
  final List<ElectionResultSubmission> results;
  final List<EmergencyDispatch> dispatches;
  final _SituationCondition condition;

  List<FieldIncident> get openIncidents => incidents
      .where(
        (item) =>
            item.status != IncidentStatus.resolved &&
            item.status != IncidentStatus.closed,
      )
      .toList(growable: false);

  List<EmergencyDispatch> get activeDispatches => dispatches
      .where(
        (item) =>
            item.status != EmergencyDispatchStatus.resolved &&
            item.status != EmergencyDispatchStatus.closed,
      )
      .toList(growable: false);

  int get criticalIncidents => openIncidents
      .where((item) => item.severity == IncidentSeverity.critical)
      .length;

  int get highIncidents => openIncidents
      .where((item) => item.severity == IncidentSeverity.high)
      .length;

  int get awaitingResponse => activeDispatches
      .where((item) => item.status == EmergencyDispatchStatus.assigned)
      .length;

  factory _LgaSnapshot.build({
    required CanonicalLga lga,
    required FieldOperationsController field,
    required MembershipOperationsController membership,
    required ResultOperationsController results,
    required EmergencyResponseController emergency,
  }) {
    final incidents = field.incidentsForScope(lga.scope);
    final reports = field.reportsForScope(lga.scope);
    final submissions = results.submissionsForScope(lga.scope);
    final dispatches = emergency.dispatchesForScope(lga.scope);
    final agents = membership.agentsForScope(lga.scope);
    final members = membership.memberCountForScope(lga.scope);
    final open = incidents
        .where(
          (item) =>
              item.status != IncidentStatus.resolved &&
              item.status != IncidentStatus.closed,
        )
        .toList(growable: false);
    final activeDispatches = dispatches
        .where(
          (item) =>
              item.status != EmergencyDispatchStatus.resolved &&
              item.status != EmergencyDispatchStatus.closed,
        )
        .toList(growable: false);

    var condition = _SituationCondition.noData;
    final hasCriticalIncident = open.any(
      (item) => item.severity == IncidentSeverity.critical,
    );
    final hasCriticalDispatch = activeDispatches.any(
      (item) => item.priority == EmergencyDispatchPriority.critical,
    );
    final hasHighIncident = open.any(
      (item) => item.severity == IncidentSeverity.high,
    );
    final hasUrgentDispatch = activeDispatches.any(
      (item) => item.priority == EmergencyDispatchPriority.urgent,
    );

    if (hasCriticalIncident || hasCriticalDispatch) {
      condition = _SituationCondition.critical;
    } else if (hasHighIncident || hasUrgentDispatch) {
      condition = _SituationCondition.serious;
    } else if (open.isNotEmpty || activeDispatches.isNotEmpty) {
      condition = _SituationCondition.elevated;
    } else if (members > 0 ||
        agents.isNotEmpty ||
        reports.isNotEmpty ||
        submissions.isNotEmpty ||
        dispatches.isNotEmpty) {
      condition = _SituationCondition.normal;
    }

    return _LgaSnapshot(
      lga: lga,
      members: members,
      agents: agents.length,
      approvedAgents: agents
          .where((item) => item.status == AccreditationStatus.approved)
          .length,
      incidents: incidents,
      reports: reports,
      results: submissions,
      dispatches: dispatches,
      condition: condition,
    );
  }
}

class _TopMetrics extends StatelessWidget {
  const _TopMetrics({
    required this.lgas,
    required this.attentionLgas,
    required this.openIncidents,
    required this.activeResponses,
    required this.resultSubmissions,
    required this.approvedAgents,
  });

  final int lgas;
  final int attentionLgas;
  final int openIncidents;
  final int activeResponses;
  final int resultSubmissions;
  final int approvedAgents;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1160
          ? 6
          : constraints.maxWidth >= 760
          ? 3
          : constraints.maxWidth >= 500
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
            label: 'LGAs in view',
            value: '$lgas',
            detail: 'Based on current access scope',
            icon: Icons.map_outlined,
            tone: TgcgMetricTone.info,
          ),
          TgcgMetricCard(
            width: width,
            label: 'Need attention',
            value: '$attentionLgas',
            detail: 'Elevated, serious or critical',
            icon: Icons.crisis_alert_outlined,
            tone: attentionLgas == 0
                ? TgcgMetricTone.success
                : TgcgMetricTone.warning,
          ),
          TgcgMetricCard(
            width: width,
            label: 'Open incidents',
            value: '$openIncidents',
            detail: 'Unresolved operational issues',
            icon: Icons.warning_amber_rounded,
            tone: TgcgMetricTone.warning,
          ),
          TgcgMetricCard(
            width: width,
            label: 'Active response',
            value: '$activeResponses',
            detail: 'Agency dispatches still open',
            icon: Icons.emergency_share_outlined,
            tone: activeResponses == 0
                ? TgcgMetricTone.neutral
                : TgcgMetricTone.danger,
          ),
          TgcgMetricCard(
            width: width,
            label: 'Result submissions',
            value: '$resultSubmissions',
            detail: 'Unofficial field submissions',
            icon: Icons.ballot_outlined,
            tone: TgcgMetricTone.ai,
          ),
          TgcgMetricCard(
            width: width,
            label: 'Approved agents',
            value: '$approvedAgents',
            detail: 'Accredited in current scope',
            icon: Icons.badge_outlined,
            tone: TgcgMetricTone.success,
          ),
        ],
      );
    },
  );
}

class _KadunaLgaMap extends StatelessWidget {
  const _KadunaLgaMap({
    required this.allLgas,
    required this.snapshots,
    required this.selectedLgaId,
    required this.onSelect,
  });

  final List<CanonicalLga> allLgas;
  final List<_LgaSnapshot> snapshots;
  final String? selectedLgaId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final snapshotById = <String, _LgaSnapshot>{
      for (final snapshot in snapshots) snapshot.lga.id: snapshot,
    };

    return TgcgSectionCard(
      title: 'Kaduna LGA situation map',
      subtitle:
          'Select an LGA to inspect current operational issues, response activity and field data.',
      trailing: TgcgStatusPill(
        label: '${snapshots.length} IN SCOPE',
        color: TgcgColors.primary,
        icon: Icons.location_on_outlined,
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 560,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TgcgColors.navy50,
                  TgcgColors.surface,
                  TgcgColors.gold100,
                ],
              ),
              borderRadius: BorderRadius.circular(TgcgRadius.lg),
              border: Border.all(color: TgcgColors.gold200),
            ),
            padding: const EdgeInsets.all(16),
            child: Center(
              child: KadunaMap(
                selectedLgaId: selectedLgaId,
                fillColor: (lgaId) {
                  final snapshot = snapshotById[lgaId];
                  return snapshot == null
                      ? const Color(0xFFE4E9F0)
                      : _conditionColor(snapshot.condition);
                },
                labelColor: (lgaId) {
                  final condition = snapshotById[lgaId]?.condition;
                  return condition == null ||
                          condition == _SituationCondition.noData
                      ? TgcgColors.muted
                      : Colors.white;
                },
                badge: (lgaId) {
                  final open = snapshotById[lgaId]?.openIncidents.length ?? 0;
                  return open == 0 ? null : '$open OPEN';
                },
                onLgaTap: (lgaId) {
                  if (snapshotById.containsKey(lgaId)) onSelect(lgaId);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _MapLegend(),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: const [
      _LegendItem(condition: _SituationCondition.normal, label: 'Normal'),
      _LegendItem(condition: _SituationCondition.elevated, label: 'Elevated'),
      _LegendItem(condition: _SituationCondition.serious, label: 'Serious'),
      _LegendItem(condition: _SituationCondition.critical, label: 'Critical'),
      _LegendItem(
        condition: _SituationCondition.noData,
        label: 'No current data',
      ),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.condition, required this.label});
  final _SituationCondition condition;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: _conditionColor(condition),
          borderRadius: BorderRadius.circular(3),
          border: condition == _SituationCondition.noData
              ? Border.all(color: TgcgColors.muted.withValues(alpha: .3))
              : null,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(
          color: TgcgColors.muted,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _LgaInspector extends StatelessWidget {
  const _LgaInspector({required this.snapshot, required this.emergency});

  final _LgaSnapshot? snapshot;
  final EmergencyResponseController emergency;

  @override
  Widget build(BuildContext context) {
    final item = snapshot;
    if (item == null) {
      return const TgcgSectionCard(
        child: TgcgEmptyState(
          icon: Icons.touch_app_outlined,
          title: 'Select an LGA',
          message:
              'Choose an LGA on the map to inspect its operational picture.',
        ),
      );
    }

    final openIncidents = [...item.openIncidents]
      ..sort(
        (a, b) =>
            _severityRank(b.severity).compareTo(_severityRank(a.severity)),
      );
    final dispatches = [...item.activeDispatches]
      ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

    return TgcgSectionCard(
      title: '${item.lga.name} LGA',
      subtitle: '${item.lga.senatorialDistrictName} Senatorial Zone',
      trailing: TgcgStatusPill(
        label: _conditionLabel(item.condition).toUpperCase(),
        color: _conditionColor(item.condition),
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InspectorMetrics(snapshot: item),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          const Text(
            'Active issues',
            style: TextStyle(
              color: TgcgColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (openIncidents.isEmpty)
            const _QuietLine(
              icon: Icons.check_circle_outline_rounded,
              text: 'No unresolved incident in current data.',
              color: TgcgColors.success,
            )
          else
            ...openIncidents
                .take(4)
                .map((incident) => _IncidentLine(incident: incident)),
          const SizedBox(height: 14),
          const Text(
            'Emergency response',
            style: TextStyle(
              color: TgcgColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (dispatches.isEmpty)
            const _QuietLine(
              icon: Icons.shield_outlined,
              text: 'No active agency dispatch.',
              color: TgcgColors.muted,
            )
          else
            ...dispatches
                .take(4)
                .map(
                  (dispatch) => _DispatchLine(
                    dispatch: dispatch,
                    agency: emergency.agencyById(dispatch.agencyId),
                  ),
                ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [TgcgColors.gold100, TgcgColors.navy50],
              ),
              borderRadius: BorderRadius.circular(TgcgRadius.sm),
              border: Border.all(color: TgcgColors.gold200),
            ),
            child: Text(
              '${item.results.length} unofficial field result submission${item.results.length == 1 ? '' : 's'} • '
              '${item.reports.length} field report${item.reports.length == 1 ? '' : 's'} • '
              '${item.members} registered member${item.members == 1 ? '' : 's'}',
              style: const TextStyle(
                color: TgcgColors.primaryDark,
                fontSize: 9.5,
                height: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorMetrics extends StatelessWidget {
  const _InspectorMetrics({required this.snapshot});
  final _LgaSnapshot snapshot;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MiniMetric(
            width: width,
            label: 'Open incidents',
            value: '${snapshot.openIncidents.length}',
            icon: Icons.warning_amber_rounded,
            color: TgcgColors.warning,
          ),
          _MiniMetric(
            width: width,
            label: 'Active response',
            value: '${snapshot.activeDispatches.length}',
            icon: Icons.emergency_share_outlined,
            color: TgcgColors.danger,
          ),
          _MiniMetric(
            width: width,
            label: 'Approved agents',
            value: '${snapshot.approvedAgents}',
            icon: Icons.badge_outlined,
            color: TgcgColors.success,
          ),
          _MiniMetric(
            width: width,
            label: 'Field submissions',
            value: '${snapshot.results.length}',
            icon: Icons.ballot_outlined,
            color: TgcgColors.ai,
          ),
        ],
      );
    },
  );
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [TgcgColors.surface, color.withValues(alpha: .035)],
      ),
      borderRadius: BorderRadius.circular(TgcgRadius.sm),
      border: Border.all(color: color.withValues(alpha: .14)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _IncidentLine extends StatelessWidget {
  const _IncidentLine({required this.incident});
  final FieldIncident incident;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(incident.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 17, color: color),
          const SizedBox(width: 8),
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
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${incident.id} • ${incident.scope.lgaName ?? incident.scope.label}',
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 8.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TgcgStatusPill(
            label: incident.severity.name.toUpperCase(),
            color: color,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _DispatchLine extends StatelessWidget {
  const _DispatchLine({required this.dispatch, required this.agency});
  final EmergencyDispatch dispatch;
  final EmergencyAgency? agency;

  @override
  Widget build(BuildContext context) {
    final color = _dispatchStatusColor(dispatch.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.local_police_outlined, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agency?.shortName ?? 'Response agency',
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${dispatch.incidentId} • ${_priorityLabel(dispatch.priority)} priority',
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 8.3,
                  ),
                ),
              ],
            ),
          ),
          TgcgStatusPill(
            label: _dispatchStatusLabel(dispatch.status).toUpperCase(),
            color: color,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _QuietLine extends StatelessWidget {
  const _QuietLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: TgcgColors.surfaceSoft,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: TgcgColors.border),
    ),
    child: Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ZoneOverview extends StatelessWidget {
  const _ZoneOverview({
    required this.geography,
    required this.snapshots,
    required this.selectedLgaId,
    required this.onSelectLga,
  });

  final GeographyRegistry geography;
  final List<_LgaSnapshot> snapshots;
  final String? selectedLgaId;
  final ValueChanged<String> onSelectLga;

  @override
  Widget build(BuildContext context) {
    final visibleZones = geography.senatorialDistricts
        .where(
          (zone) =>
              snapshots.any((item) => item.lga.senatorialDistrictId == zone.id),
        )
        .toList(growable: false);

    return TgcgSectionCard(
      title: 'Senatorial zone overview',
      subtitle:
          'Operational summary across the senatorial zones in your scope.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 680
              ? 3
              : constraints.maxWidth >= 440
              ? 2
              : 1;
          const gap = 10.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: visibleZones.map((zone) {
              final items = snapshots
                  .where((item) => item.lga.senatorialDistrictId == zone.id)
                  .toList(growable: false);
              final selected = items.any(
                (item) => item.lga.id == selectedLgaId,
              );
              final focus = _preferredLga(items);
              final incidents = items.fold<int>(
                0,
                (total, item) => total + item.openIncidents.length,
              );
              final responses = items.fold<int>(
                0,
                (total, item) => total + item.activeDispatches.length,
              );
              final agents = items.fold<int>(
                0,
                (total, item) => total + item.approvedAgents,
              );
              final condition = items.fold<_SituationCondition>(
                _SituationCondition.noData,
                (current, item) => item.condition.index > current.index
                    ? item.condition
                    : current,
              );
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelectLga(focus.lga.id),
                child: Container(
                  width: width,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected
                        ? TgcgColors.primarySoft
                        : TgcgColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? TgcgColors.primary : TgcgColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: _conditionColor(condition),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            zone.id.replaceAll('/', ' / '),
                            style: const TextStyle(
                              color: TgcgColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        zone.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '${items.length} LGAs • $incidents incidents',
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 8.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$responses response • $agents approved agents',
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 8.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _OperationalActivity extends StatelessWidget {
  const _OperationalActivity({
    required this.snapshots,
    required this.emergency,
  });

  final List<_LgaSnapshot> snapshots;
  final EmergencyResponseController emergency;

  @override
  Widget build(BuildContext context) {
    final records = <_ActivityRecord>[];
    for (final snapshot in snapshots) {
      for (final incident in snapshot.incidents) {
        records.add(
          _ActivityRecord(
            at: incident.reportedAt,
            icon: Icons.warning_amber_rounded,
            color: _severityColor(incident.severity),
            title: incident.title,
            location: incident.scope.label,
            tag: 'INCIDENT',
          ),
        );
      }
      for (final report in snapshot.reports) {
        records.add(
          _ActivityRecord(
            at: report.reportedAt,
            icon: Icons.feed_outlined,
            color: TgcgColors.info,
            title: report.category,
            location: report.scope.label,
            tag: 'FIELD REPORT',
          ),
        );
      }
      for (final result in snapshot.results) {
        records.add(
          _ActivityRecord(
            at: result.submittedAt,
            icon: Icons.ballot_outlined,
            color: TgcgColors.ai,
            title: 'Unofficial result submission received',
            location: result.pollingUnitScope.label,
            tag: 'RESULT',
          ),
        );
      }
      for (final dispatch in snapshot.dispatches) {
        final agency = emergency.agencyById(dispatch.agencyId);
        records.add(
          _ActivityRecord(
            at: dispatch.assignedAt,
            icon: Icons.emergency_share_outlined,
            color: _priorityColor(dispatch.priority),
            title:
                '${agency?.shortName ?? 'Response agency'} assigned to ${dispatch.incidentId}',
            location: dispatch.scope.label,
            tag: 'RESPONSE',
          ),
        );
      }
    }
    records.sort((a, b) => b.at.compareTo(a.at));

    return TgcgSectionCard(
      title: 'Operational activity',
      subtitle:
          'Most recent incidents, field reports, response assignments and result submissions.',
      trailing: TgcgStatusPill(
        label: '${records.length} EVENTS',
        color: TgcgColors.info,
        compact: true,
      ),
      child: records.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.timeline_outlined,
              title: 'No activity in scope',
              message:
                  'Operational events will appear here as they are recorded.',
            )
          : Column(
              children: records.take(10).map((record) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: TgcgColors.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: record.color.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(record.icon, size: 19, color: record.color),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.title,
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
                              record.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: TgcgColors.muted,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      TgcgStatusPill(
                        label: record.tag,
                        color: record.color,
                        compact: true,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _shortTime(record.at),
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
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

class _ActivityRecord {
  const _ActivityRecord({
    required this.at,
    required this.icon,
    required this.color,
    required this.title,
    required this.location,
    required this.tag,
  });

  final DateTime at;
  final IconData icon;
  final Color color;
  final String title;
  final String location;
  final String tag;
}

Color _conditionColor(_SituationCondition condition) => switch (condition) {
  _SituationCondition.noData => const Color(0xFFCACED6),
  _SituationCondition.normal => TgcgColors.success,
  _SituationCondition.elevated => TgcgColors.warning,
  _SituationCondition.serious => TgcgColors.danger,
  _SituationCondition.critical => const Color(0xFF7F1D1D),
};

String _conditionLabel(_SituationCondition condition) => switch (condition) {
  _SituationCondition.noData => 'No current data',
  _SituationCondition.normal => 'Normal',
  _SituationCondition.elevated => 'Elevated',
  _SituationCondition.serious => 'Serious',
  _SituationCondition.critical => 'Critical',
};

int _severityRank(IncidentSeverity severity) => switch (severity) {
  IncidentSeverity.info => 0,
  IncidentSeverity.low => 1,
  IncidentSeverity.medium => 2,
  IncidentSeverity.high => 3,
  IncidentSeverity.critical => 4,
};

Color _severityColor(IncidentSeverity severity) => switch (severity) {
  IncidentSeverity.info => TgcgColors.info,
  IncidentSeverity.low => TgcgColors.success,
  IncidentSeverity.medium => TgcgColors.warning,
  IncidentSeverity.high => TgcgColors.danger,
  IncidentSeverity.critical => const Color(0xFF7F1D1D),
};

Color _priorityColor(EmergencyDispatchPriority priority) => switch (priority) {
  EmergencyDispatchPriority.routine => TgcgColors.info,
  EmergencyDispatchPriority.urgent => TgcgColors.warning,
  EmergencyDispatchPriority.critical => TgcgColors.danger,
};

String _priorityLabel(EmergencyDispatchPriority priority) => switch (priority) {
  EmergencyDispatchPriority.routine => 'Routine',
  EmergencyDispatchPriority.urgent => 'Urgent',
  EmergencyDispatchPriority.critical => 'Critical',
};

Color _dispatchStatusColor(EmergencyDispatchStatus status) => switch (status) {
  EmergencyDispatchStatus.assigned => TgcgColors.warning,
  EmergencyDispatchStatus.acknowledged => TgcgColors.info,
  EmergencyDispatchStatus.responding => TgcgColors.info,
  EmergencyDispatchStatus.onScene => TgcgColors.ai,
  EmergencyDispatchStatus.resolved => TgcgColors.success,
  EmergencyDispatchStatus.closed => TgcgColors.muted,
};

String _dispatchStatusLabel(EmergencyDispatchStatus status) => switch (status) {
  EmergencyDispatchStatus.assigned => 'Assigned',
  EmergencyDispatchStatus.acknowledged => 'Acknowledged',
  EmergencyDispatchStatus.responding => 'Responding',
  EmergencyDispatchStatus.onScene => 'On Scene',
  EmergencyDispatchStatus.resolved => 'Resolved',
  EmergencyDispatchStatus.closed => 'Closed',
};

String _shortTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
