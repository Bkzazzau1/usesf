import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/access_policy.dart';
import '../domain/permissions.dart';
import '../field/field_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'emergency_response_store.dart';

class SecurityResponsePortalPage extends StatefulWidget {
  const SecurityResponsePortalPage({super.key});

  @override
  State<SecurityResponsePortalPage> createState() =>
      _SecurityResponsePortalPageState();
}

class _SecurityResponsePortalPageState extends State<SecurityResponsePortalPage> {
  String? selectedDispatchId;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final emergency = EmergencyResponse.of(context);
    final field = FieldOperations.of(context);
    final isAgencyOfficer = session.role == TgcgRole.securityOfficer;
    final agencyId = isAgencyOfficer ? session.agencyId : null;
    final agency = agencyId == null ? null : emergency.agencyById(agencyId);
    final dispatches = isAgencyOfficer
        ? agencyId == null
            ? <EmergencyDispatch>[]
            : emergency.dispatchesForAgency(
                scope: session.scope,
                agencyId: agencyId,
              )
        : emergency.dispatchesForScope(session.scope);
    final incidents = field.incidentsForScope(session.scope);
    final agencies = isAgencyOfficer
        ? agency == null
            ? <EmergencyAgency>[]
            : <EmergencyAgency>[agency]
        : emergency.agenciesForScope(session.scope);
    final incidentCount = dispatches.map((item) => item.incidentId).toSet().length;
    final active = dispatches
        .where((item) =>
            item.status != EmergencyDispatchStatus.resolved &&
            item.status != EmergencyDispatchStatus.closed)
        .toList(growable: false);
    final critical = active
        .where((item) => item.priority == EmergencyDispatchPriority.critical)
        .length;
    final awaiting = active
        .where((item) => item.status == EmergencyDispatchStatus.assigned)
        .length;
    final responding = active
        .where((item) =>
            item.status == EmergencyDispatchStatus.responding ||
            item.status == EmergencyDispatchStatus.onScene)
        .length;

    if (selectedDispatchId == null ||
        !dispatches.any((item) => item.id == selectedDispatchId)) {
      selectedDispatchId = active.isNotEmpty
          ? active.first.id
          : dispatches.isNotEmpty
              ? dispatches.first.id
              : null;
    }

    EmergencyDispatch? selected;
    if (selectedDispatchId != null) {
      for (final item in dispatches) {
        if (item.id == selectedDispatchId) {
          selected = item;
          break;
        }
      }
    }

    final canAssign = TgcgPermissionPolicy.may(
      session.role!,
      session.scope,
      TgcgCapability.assignIncident,
    );
    final canRespond = TgcgPermissionPolicy.may(
      session.role!,
      session.scope,
      TgcgCapability.respondToDispatch,
    );
    final actorId = session.accessId.isEmpty
        ? session.operatorName
        : session.accessId;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TgcgPageHeader(
          eyebrow: isAgencyOfficer ? 'AUTHORIZED AGENCY RESPONSE' : 'EMERGENCY COORDINATION',
          title: isAgencyOfficer
              ? '${agency?.shortName ?? 'Security'} Response Desk'
              : 'Security & Emergency Response',
          subtitle: isAgencyOfficer
              ? '${session.scope.label}: only incidents assigned to your agency are visible. Review evidence, coordinates and update the response stage.'
              : '${session.scope.label}: dispatch verified incidents to authorized response agencies and track response status.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TgcgStatusPill(
                label: isAgencyOfficer ? 'AGENCY-ONLY ACCESS' : 'RESPONSE DESK',
                color: isAgencyOfficer ? TgcgColors.accentStrong : TgcgColors.success,
                icon: isAgencyOfficer
                    ? Icons.verified_user_outlined
                    : Icons.shield_outlined,
              ),
              if (canAssign)
                FilledButton.icon(
                  onPressed: incidents.isEmpty || agencies.isEmpty
                      ? null
                      : () => _showAssignDialog(
                            context,
                            incidents: incidents,
                            agencies: agencies,
                          ),
                  icon: const Icon(Icons.add_alert_rounded, size: 18),
                  label: const Text('Assign Response'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(
          active: active.length,
          critical: critical,
          awaiting: awaiting,
          responding: responding,
          agencies: agencies.length,
          incidents: incidentCount,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final board = _DispatchBoard(
              dispatches: dispatches,
              emergency: emergency,
              selectedId: selectedDispatchId,
              agencyRestricted: isAgencyOfficer,
              onSelected: (id) {
                if (id != selectedDispatchId) {
                  emergency.recordDispatchAudit(
                    dispatchId: id,
                    actorId: actorId,
                    action: 'security_dispatch_viewed',
                    detail: isAgencyOfficer
                        ? 'Assigned incident intelligence package opened by agency responder.'
                        : 'Security dispatch opened from the response portal.',
                    actingAgencyId: isAgencyOfficer ? agencyId : null,
                  );
                }
                setState(() => selectedDispatchId = id);
              },
            );
            final detail = _DispatchDetail(
              dispatch: selected,
              emergency: emergency,
              incident: selected == null
                  ? null
                  : _incidentById(incidents, selected.incidentId),
              actorId: actorId,
              canRespond: canRespond,
              actingAgencyId: agencyId,
              agencyRestricted: isAgencyOfficer,
            );
            if (constraints.maxWidth < 1020) {
              return Column(
                children: [
                  board,
                  const SizedBox(height: 14),
                  detail,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: board),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: detail),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _AgencyDirectory(agencies: agencies),
      ],
    );
  }

  Future<void> _showAssignDialog(
    BuildContext context, {
    required List<FieldIncident> incidents,
    required List<EmergencyAgency> agencies,
  }) async {
    final openIncidents = incidents
        .where((item) =>
            item.status != IncidentStatus.resolved &&
            item.status != IncidentStatus.closed)
        .toList(growable: false);
    if (openIncidents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no open incidents to dispatch.')),
      );
      return;
    }

    String incidentId = openIncidents.first.id;
    String agencyId = agencies.first.id;
    EmergencyDispatchPriority priority = EmergencyDispatchPriority.urgent;
    final instructions = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Assign emergency response'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: incidentId,
                    decoration: const InputDecoration(
                      labelText: 'Incident',
                      prefixIcon: Icon(Icons.crisis_alert_outlined),
                    ),
                    items: openIncidents
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(
                              '${item.id} • ${item.title}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setLocalState(() => incidentId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: agencyId,
                    decoration: const InputDecoration(
                      labelText: 'Response agency',
                      prefixIcon: Icon(Icons.local_police_outlined),
                    ),
                    items: agencies
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setLocalState(() => agencyId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<EmergencyDispatchPriority>(
                    initialValue: priority,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      prefixIcon: Icon(Icons.priority_high_rounded),
                    ),
                    items: EmergencyDispatchPriority.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(_priorityLabel(item)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setLocalState(() => priority = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: instructions,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Response instructions',
                      hintText: 'Add the action required from the response desk',
                      alignLabelWithHint: true,
                    ),
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
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Assign'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) {
      instructions.dispose();
      return;
    }

    final incident = _incidentById(openIncidents, incidentId);
    if (incident == null) {
      instructions.dispose();
      return;
    }
    final session = TgcgSession.of(context, listen: false);
    final emergency = EmergencyResponse.of(context, listen: false);
    final field = FieldOperations.of(context, listen: false);
    final actor = session.accessId.isEmpty ? session.operatorName : session.accessId;
    // Dispatching moves the incident to "assigned", so the same authority
    // must hold before an agency is dispatched at all.
    final assignCapability =
        incidentStatusMutationCapability(IncidentStatus.assigned);
    final actorRole = TgcgAccessPolicy.roleFor(
      context,
      assignCapability,
      targetScope: incident.scope,
      listen: false,
    );
    final authorizedScope = TgcgAccessPolicy.authorizingScope(
      context,
      assignCapability,
      targetScope: incident.scope,
      listen: false,
    );
    if (actorRole == null || authorizedScope == null) {
      instructions.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your access does not allow assigning this incident.'),
        ),
      );
      return;
    }
    final dispatch = emergency.assign(
      incidentId: incident.id,
      agencyId: agencyId,
      scope: incident.scope,
      priority: priority,
      actorId: actor,
      instructions: instructions.text,
    );
    instructions.dispose();
    try {
      await field.updateIncidentStatus(
        incident.id,
        IncidentStatus.assigned,
        actorId: actor,
        actorRole: actorRole,
        authorizedScope: authorizedScope,
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
    if (!context.mounted) return;
    setState(() => selectedDispatchId = dispatch.id);
    final agency = emergency.agencyById(agencyId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${agency?.shortName ?? 'Response agency'} assigned to ${incident.id}.',
        ),
      ),
    );
  }

  static FieldIncident? _incidentById(
    List<FieldIncident> incidents,
    String id,
  ) {
    for (final item in incidents) {
      if (item.id == id) return item;
    }
    return null;
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.active,
    required this.critical,
    required this.awaiting,
    required this.responding,
    required this.agencies,
    required this.incidents,
  });

  final int active;
  final int critical;
  final int awaiting;
  final int responding;
  final int agencies;
  final int incidents;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1120
              ? 6
              : constraints.maxWidth >= 720
                  ? 3
                  : constraints.maxWidth >= 460
                      ? 2
                      : 1;
          const gap = 12.0;
          final itemWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: itemWidth,
                label: 'Active dispatches',
                value: '$active',
                detail: 'Open agency response assignments',
                icon: Icons.emergency_share_outlined,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: itemWidth,
                label: 'Critical',
                value: '$critical',
                detail: 'Critical response priority',
                icon: Icons.crisis_alert_rounded,
                tone: TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: itemWidth,
                label: 'Awaiting ACK',
                value: '$awaiting',
                detail: 'Assigned but not acknowledged',
                icon: Icons.schedule_rounded,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: itemWidth,
                label: 'Responding',
                value: '$responding',
                detail: 'En route or on scene',
                icon: Icons.directions_car_filled_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: itemWidth,
                label: 'Agency desks',
                value: '$agencies',
                detail: 'Authorized response desks',
                icon: Icons.shield_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: itemWidth,
                label: 'Incidents in scope',
                value: '$incidents',
                detail: 'Available for command review',
                icon: Icons.warning_amber_rounded,
                tone: TgcgMetricTone.neutral,
              ),
            ],
          );
        },
      );
}

class _DispatchBoard extends StatelessWidget {
  const _DispatchBoard({
    required this.dispatches,
    required this.emergency,
    required this.selectedId,
    required this.agencyRestricted,
    required this.onSelected,
  });

  final List<EmergencyDispatch> dispatches;
  final EmergencyResponseController emergency;
  final String? selectedId;
  final bool agencyRestricted;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Live response assignments',
        subtitle: 'Agency assignments and current response stage.',
        child: dispatches.isEmpty
            ? TgcgEmptyState(
                icon: Icons.shield_outlined,
                title: 'No response assignments',
                message: agencyRestricted
                    ? 'There is currently no incident assigned to your response agency.'
                    : 'Assign an open incident to an authorized response agency.',
              )
            : Column(
                children: [
                  for (final item in dispatches) ...[
                    _DispatchRow(
                      dispatch: item,
                      agency: emergency.agencyById(item.agencyId),
                      selected: item.id == selectedId,
                      onTap: () => onSelected(item.id),
                    ),
                    if (item != dispatches.last)
                      const Divider(height: 1),
                  ],
                ],
              ),
      );
}

class _DispatchRow extends StatelessWidget {
  const _DispatchRow({
    required this.dispatch,
    required this.agency,
    required this.selected,
    required this.onTap,
  });

  final EmergencyDispatch dispatch;
  final EmergencyAgency? agency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? TgcgColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(TgcgRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _priorityColor(dispatch.priority).withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    _agencyIcon(agency?.type),
                    color: _priorityColor(dispatch.priority),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${dispatch.incidentId} • ${agency?.shortName ?? 'Agency'}',
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dispatch.scope.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TgcgStatusPill(
                      label: _statusLabel(dispatch.status).toUpperCase(),
                      color: _statusColor(dispatch.status),
                      compact: true,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _priorityLabel(dispatch.priority),
                      style: TextStyle(
                        color: _priorityColor(dispatch.priority),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _DispatchDetail extends StatelessWidget {
  const _DispatchDetail({
    required this.dispatch,
    required this.emergency,
    required this.incident,
    required this.actorId,
    required this.canRespond,
    required this.actingAgencyId,
    required this.agencyRestricted,
  });

  final EmergencyDispatch? dispatch;
  final EmergencyResponseController emergency;
  final FieldIncident? incident;
  final String actorId;
  final bool canRespond;
  final String? actingAgencyId;
  final bool agencyRestricted;

  @override
  Widget build(BuildContext context) {
    final item = dispatch;
    if (item == null) {
      return const TgcgSectionCard(
        title: 'Incident intelligence package',
        child: TgcgEmptyState(
          icon: Icons.emergency_outlined,
          title: 'Select a response assignment',
          message:
              'Choose an assignment to review its evidence, coordinates and responder status.',
        ),
      );
    }

    final agency = emergency.agencyById(item.agencyId);
    final incidentItem = incident;
    final responseAllowed = canRespond &&
        (!agencyRestricted ||
            (actingAgencyId != null && actingAgencyId == item.agencyId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TgcgSectionCard(
          title: 'Incident intelligence package',
          subtitle: '${item.id} • ${agency?.name ?? item.agencyId}',
          trailing: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              TgcgStatusPill(
                label: _priorityLabel(item.priority).toUpperCase(),
                color: _priorityColor(item.priority),
                compact: true,
              ),
              TgcgStatusPill(
                label: _statusLabel(item.status).toUpperCase(),
                color: _statusColor(item.status),
                compact: true,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailLine(label: 'Incident', value: item.incidentId),
              _DetailLine(label: 'Location', value: item.scope.label),
              _DetailLine(
                label: 'Command desk',
                value: agency?.commandDesk ?? '—',
              ),
              _DetailLine(
                label: 'Agency contact',
                value: agency?.contactPhone ?? '—',
              ),
              _DetailLine(
                label: 'Assigned',
                value: _formatTimestamp(item.assignedAt),
              ),
              if (incidentItem != null) ...[
                const Divider(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        incidentItem.title,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (incidentItem.origin == RecordOrigin.systemDerived)
                      const TgcgStatusPill(
                        label: 'PROTOTYPE DATA',
                        color: TgcgColors.muted,
                        compact: true,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    TgcgStatusPill(
                      label: incidentItem.category.toUpperCase(),
                      color: TgcgColors.primary,
                      compact: true,
                    ),
                    TgcgStatusPill(
                      label:
                          _incidentSeverityLabel(incidentItem.severity).toUpperCase(),
                      color: _incidentSeverityColor(incidentItem.severity),
                      compact: true,
                    ),
                    TgcgStatusPill(
                      label: '${incidentItem.evidence.length} EVIDENCE',
                      color: TgcgColors.info,
                      icon: Icons.attachment_rounded,
                      compact: true,
                    ),
                    if (incidentItem.latitude != null &&
                        incidentItem.longitude != null)
                      const TgcgStatusPill(
                        label: 'GPS AVAILABLE',
                        color: TgcgColors.success,
                        icon: Icons.location_on_outlined,
                        compact: true,
                      ),
                  ],
                ),
                if (incidentItem.summary != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    incidentItem.summary!,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 10.8,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _DetailLine(
                  label: 'Reported by',
                  value: incidentItem.reporterId,
                ),
                if (incidentItem.assignmentId != null)
                  _DetailLine(
                    label: 'Field assignment',
                    value: incidentItem.assignmentId!,
                  ),
                if (incidentItem.deviceId != null)
                  _DetailLine(
                    label: 'Managed device',
                    value: incidentItem.deviceId!,
                  ),
                _DetailLine(
                  label: 'Reported at',
                  value: _formatTimestamp(incidentItem.reportedAt),
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () {
                    emergency.recordDispatchAudit(
                      dispatchId: item.id,
                      actorId: actorId,
                      action: 'security_incident_brief_shared',
                      detail:
                          'Incident brief copied for authorized operational sharing.',
                      actingAgencyId:
                          agencyRestricted ? actingAgencyId : null,
                    );
                    _copyIncidentBrief(
                      context,
                      dispatch: item,
                      agency: agency,
                      incident: incidentItem,
                    );
                  },
                  icon: const Icon(Icons.copy_all_outlined, size: 17),
                  label: const Text('Copy incident brief'),
                ),
              ],
              if (item.instructions != null) ...[
                const Divider(height: 24),
                const Text(
                  'Response instruction',
                  style: TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.instructions!,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 10.8,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (incidentItem != null) ...[
          const SizedBox(height: 14),
          _CoordinatePanel(
            incident: incidentItem,
            scope: item.scope,
          ),
          const SizedBox(height: 14),
          _EvidenceIntelligence(
            evidence: incidentItem.evidence,
          ),
        ],
        const SizedBox(height: 14),
        _ResponseTimeline(dispatch: item),
        const SizedBox(height: 14),
        TgcgSectionCard(
          title: 'Responder controls',
          subtitle: agencyRestricted
              ? 'Only your agency can update this assigned response.'
              : 'Update the authorized response stage in sequence.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!responseAllowed && agencyRestricted)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: TgcgColors.warning.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(TgcgRadius.sm),
                    border: Border.all(
                      color: TgcgColors.warning.withValues(alpha: .20),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        color: TgcgColors.warning,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This assignment cannot be updated from the current agency session.',
                          style: TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _nextActions(item.status)
                    .map(
                      (status) => FilledButton.tonalIcon(
                        onPressed: responseAllowed
                            ? () {
                                try {
                                  emergency.updateStatus(
                                    dispatchId: item.id,
                                    status: status,
                                    actorId: actorId,
                                    actingAgencyId:
                                        agencyRestricted ? actingAgencyId : null,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Response updated to ${_statusLabel(status)}.',
                                      ),
                                    ),
                                  );
                                } on StateError catch (error) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(error.message)),
                                  );
                                }
                              }
                            : null,
                        icon: Icon(_statusIcon(status), size: 17),
                        label: Text(_statusLabel(status)),
                      ),
                    )
                    .toList(),
              ),
              if (_nextActions(item.status).isEmpty)
                const TgcgStatusPill(
                  label: 'RESPONSE WORKFLOW COMPLETE',
                  color: TgcgColors.success,
                  icon: Icons.task_alt_rounded,
                ),
            ],
          ),
        ),
      ],
    );
  }

  static Future<void> _copyIncidentBrief(
    BuildContext context, {
    required EmergencyDispatch dispatch,
    required EmergencyAgency? agency,
    required FieldIncident incident,
  }) async {
    final coordinates = incident.latitude != null && incident.longitude != null
        ? '${incident.latitude!.toStringAsFixed(6)}, ${incident.longitude!.toStringAsFixed(6)}'
        : 'Not available';
    final evidence = incident.evidence.isEmpty
        ? 'None attached'
        : incident.evidence
            .map(
              (item) =>
                  '${_evidenceLabel(item.type)}: ${item.fileName} (${item.id})'
                  '${item.sourceReference == null ? '' : ' • ${item.sourceReference}'}',
            )
            .join('\n');

    final brief = '''
USESF SECURITY INCIDENT BRIEF
Dispatch: ${dispatch.id}
Incident: ${incident.id}
Agency: ${agency?.name ?? dispatch.agencyId}
Priority: ${_priorityLabel(dispatch.priority)}
Status: ${_statusLabel(dispatch.status)}
Location: ${dispatch.scope.label}
Coordinates: $coordinates
Reported: ${_formatTimestamp(incident.reportedAt)}
Reported by: ${incident.reporterId}
Field assignment: ${incident.assignmentId ?? 'Not linked'}
Managed device: ${incident.deviceId ?? 'Not linked'}
Summary: ${incident.summary ?? 'No summary'}

Evidence:
$evidence
''';

    await Clipboard.setData(ClipboardData(text: brief.trim()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Incident brief copied for sharing.')),
    );
  }
}

class _CoordinatePanel extends StatelessWidget {
  const _CoordinatePanel({
    required this.incident,
    required this.scope,
  });

  final FieldIncident incident;
  final GeographicScope scope;

  @override
  Widget build(BuildContext context) {
    final latitude = incident.latitude;
    final longitude = incident.longitude;
    return TgcgSectionCard(
      title: 'Location intelligence',
      subtitle:
          'Exact incident coordinates and operational geography for responder navigation.',
      trailing: latitude != null && longitude != null
          ? const TgcgStatusPill(
              label: 'MAP-READY GPS',
              color: TgcgColors.success,
              icon: Icons.gps_fixed_rounded,
              compact: true,
            )
          : const TgcgStatusPill(
              label: 'GPS PENDING',
              color: TgcgColors.warning,
              icon: Icons.location_searching_rounded,
              compact: true,
            ),
      child: latitude == null || longitude == null
          ? const TgcgEmptyState(
              icon: Icons.location_off_outlined,
              title: 'Exact coordinates not attached',
              message:
                  'The geographic scope remains visible, but responders should wait for verified GPS coordinates before relying on navigation.',
            )
          : Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: TgcgGradients.navigation,
                borderRadius: BorderRadius.circular(TgcgRadius.md),
                border: Border.all(
                  color: TgcgColors.accent.withValues(alpha: .18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: TgcgColors.accent.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(TgcgRadius.md),
                          border: Border.all(
                            color: TgcgColors.accent.withValues(alpha: .18),
                          ),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: TgcgColors.gold400,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              scope.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                              style: const TextStyle(
                                color: TgcgColors.gold200,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final coordinates =
                          '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
                      await Clipboard.setData(
                        ClipboardData(text: coordinates),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Coordinates copied for navigation.'),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: TgcgColors.accent.withValues(alpha: .35),
                      ),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    label: const Text('Copy coordinates'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _EvidenceIntelligence extends StatelessWidget {
  const _EvidenceIntelligence({required this.evidence});

  final List<EvidenceAttachment> evidence;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Evidence intelligence',
        subtitle:
            'Video, photos, audio and documents attached to this incident with provenance and integrity metadata.',
        trailing: TgcgStatusPill(
          label: '${evidence.length} ITEMS',
          color: evidence.isEmpty ? TgcgColors.muted : TgcgColors.info,
          icon: Icons.inventory_2_outlined,
          compact: true,
        ),
        child: evidence.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.perm_media_outlined,
                title: 'No media attached',
                message:
                    'Security personnel will see verified incident media here when field evidence is available.',
              )
            : Column(
                children: evidence
                    .map(
                      (item) => Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 9),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              TgcgColors.surface,
                              item.type == EvidenceType.video
                                  ? TgcgColors.gold100
                                  : TgcgColors.navy50,
                            ],
                          ),
                          borderRadius:
                              BorderRadius.circular(TgcgRadius.md),
                          border: Border.all(
                            color: item.type == EvidenceType.video
                                ? TgcgColors.gold200
                                : TgcgColors.border,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: item.type == EvidenceType.video
                                    ? TgcgColors.accent.withValues(alpha: .12)
                                    : TgcgColors.primarySoft,
                                borderRadius:
                                    BorderRadius.circular(TgcgRadius.sm),
                              ),
                              child: Icon(
                                _evidenceIcon(item.type),
                                color: item.type == EvidenceType.video
                                    ? TgcgColors.accentStrong
                                    : TgcgColors.primary,
                                size: 23,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.fileName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: TgcgColors.ink,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      TgcgStatusPill(
                                        label: _evidenceLabel(item.type)
                                            .toUpperCase(),
                                        color: item.type == EvidenceType.video
                                            ? TgcgColors.accentStrong
                                            : TgcgColors.info,
                                        compact: true,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'Uploaded by ${item.uploaderId} • ${_formatTimestamp(item.createdAt)}',
                                    style: const TextStyle(
                                      color: TgcgColors.muted,
                                      fontSize: 9.5,
                                    ),
                                  ),
                                  if (item.caption != null) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      item.caption!,
                                      style: const TextStyle(
                                        color: TgcgColors.muted,
                                        fontSize: 9.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 7),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      TgcgStatusPill(
                                        label: item.contentHash == null
                                            ? 'HASH PENDING'
                                            : 'HASH VERIFIED',
                                        color: item.contentHash == null
                                            ? TgcgColors.warning
                                            : TgcgColors.success,
                                        icon: item.contentHash == null
                                            ? Icons.pending_outlined
                                            : Icons.verified_outlined,
                                        compact: true,
                                      ),
                                      TgcgStatusPill(
                                        label: item.sourceReference == null
                                            ? 'UPLOAD PENDING'
                                            : 'MEDIA REFERENCE',
                                        color: item.sourceReference == null
                                            ? TgcgColors.warning
                                            : TgcgColors.info,
                                        icon: item.sourceReference == null
                                            ? Icons.cloud_upload_outlined
                                            : Icons.cloud_done_outlined,
                                        compact: true,
                                      ),
                                      if (item.latitude != null &&
                                          item.longitude != null)
                                        const TgcgStatusPill(
                                          label: 'MEDIA GPS',
                                          color: TgcgColors.success,
                                          icon: Icons.gps_fixed_rounded,
                                          compact: true,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy evidence reference',
                              onPressed: () async {
                                final reference = [
                                  item.id,
                                  item.fileName,
                                  item.contentHash ?? 'hash-pending',
                                  if (item.sourceReference != null)
                                    item.sourceReference!,
                                ].join(' • ');
                                await Clipboard.setData(
                                  ClipboardData(text: reference),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Evidence reference copied.'),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.copy_all_outlined,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
      );
}

class _ResponseTimeline extends StatelessWidget {
  const _ResponseTimeline({required this.dispatch});

  final EmergencyDispatch dispatch;

  @override
  Widget build(BuildContext context) {
    final events = <(String, DateTime?, IconData)>[
      ('Assigned', dispatch.assignedAt, Icons.assignment_ind_outlined),
      ('Acknowledged', dispatch.acknowledgedAt, Icons.check_circle_outline),
      ('Responding', dispatch.respondingAt, Icons.directions_car_outlined),
      ('On scene', dispatch.onSceneAt, Icons.location_on_outlined),
      ('Resolved', dispatch.resolvedAt, Icons.task_alt_rounded),
      ('Closed', dispatch.closedAt, Icons.lock_outline_rounded),
    ];
    return TgcgSectionCard(
      title: 'Response timeline',
      subtitle:
          'Auditable timestamps from dispatch through arrival and closure.',
      child: Column(
        children: events
            .map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: event.$2 == null
                            ? TgcgColors.surfaceSoft
                            : TgcgColors.success.withValues(alpha: .08),
                        borderRadius:
                            BorderRadius.circular(TgcgRadius.sm),
                        border: Border.all(
                          color: event.$2 == null
                              ? TgcgColors.border
                              : TgcgColors.success.withValues(alpha: .16),
                        ),
                      ),
                      child: Icon(
                        event.$3,
                        size: 17,
                        color: event.$2 == null
                            ? TgcgColors.muted
                            : TgcgColors.success,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        event.$1,
                        style: TextStyle(
                          color: event.$2 == null
                              ? TgcgColors.muted
                              : TgcgColors.ink,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      event.$2 == null ? 'Pending' : _formatTimestamp(event.$2!),
                      style: TextStyle(
                        color: event.$2 == null
                            ? TgcgColors.muted
                            : TgcgColors.primary,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _AgencyDirectory extends StatelessWidget {
  const _AgencyDirectory({required this.agencies});
  final List<EmergencyAgency> agencies;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Authorized response agencies',
        subtitle: 'Response desks configured for incident sharing and dispatch.',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 3
                : constraints.maxWidth >= 620
                    ? 2
                    : 1;
            const gap = 10.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: agencies
                  .map(
                    (agency) => Container(
                      width: width,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: TgcgColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: TgcgColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: TgcgColors.primarySoft,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              _agencyIcon(agency.type),
                              color: TgcgColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  agency.name,
                                  style: const TextStyle(
                                    color: TgcgColors.ink,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${agency.commandDesk} • ${agency.coverage.label}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: TgcgColors.muted,
                                    fontSize: 9.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const TgcgStatusPill(
                            label: 'ACTIVE',
                            color: TgcgColors.success,
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}

String _evidenceLabel(EvidenceType type) => switch (type) {
      EvidenceType.photo => 'Photo',
      EvidenceType.video => 'Video',
      EvidenceType.audio => 'Audio',
      EvidenceType.document => 'Document',
      EvidenceType.resultForm => 'Result form',
      EvidenceType.location => 'Location',
    };

IconData _evidenceIcon(EvidenceType type) => switch (type) {
      EvidenceType.photo => Icons.photo_outlined,
      EvidenceType.video => Icons.play_circle_outline_rounded,
      EvidenceType.audio => Icons.graphic_eq_rounded,
      EvidenceType.document => Icons.description_outlined,
      EvidenceType.resultForm => Icons.fact_check_outlined,
      EvidenceType.location => Icons.location_on_outlined,
    };

String _incidentSeverityLabel(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.info => 'Information',
      IncidentSeverity.low => 'Low',
      IncidentSeverity.medium => 'Medium',
      IncidentSeverity.high => 'High',
      IncidentSeverity.critical => 'Critical',
    };

Color _incidentSeverityColor(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.info => TgcgColors.info,
      IncidentSeverity.low => TgcgColors.success,
      IncidentSeverity.medium => TgcgColors.warning,
      IncidentSeverity.high => TgcgColors.warning,
      IncidentSeverity.critical => TgcgColors.danger,
    };

List<EmergencyDispatchStatus> _nextActions(EmergencyDispatchStatus status) =>
    switch (status) {
      EmergencyDispatchStatus.assigned => const [
          EmergencyDispatchStatus.acknowledged,
        ],
      EmergencyDispatchStatus.acknowledged => const [
          EmergencyDispatchStatus.responding,
        ],
      EmergencyDispatchStatus.responding => const [
          EmergencyDispatchStatus.onScene,
        ],
      EmergencyDispatchStatus.onScene => const [
          EmergencyDispatchStatus.resolved,
        ],
      EmergencyDispatchStatus.resolved => const [
          EmergencyDispatchStatus.closed,
        ],
      EmergencyDispatchStatus.closed => const [],
    };

String _priorityLabel(EmergencyDispatchPriority value) => switch (value) {
      EmergencyDispatchPriority.routine => 'Routine',
      EmergencyDispatchPriority.urgent => 'Urgent',
      EmergencyDispatchPriority.critical => 'Critical',
    };

Color _priorityColor(EmergencyDispatchPriority value) => switch (value) {
      EmergencyDispatchPriority.routine => TgcgColors.info,
      EmergencyDispatchPriority.urgent => TgcgColors.warning,
      EmergencyDispatchPriority.critical => TgcgColors.danger,
    };

String _statusLabel(EmergencyDispatchStatus value) => switch (value) {
      EmergencyDispatchStatus.assigned => 'Assigned',
      EmergencyDispatchStatus.acknowledged => 'Acknowledged',
      EmergencyDispatchStatus.responding => 'Responding',
      EmergencyDispatchStatus.onScene => 'On Scene',
      EmergencyDispatchStatus.resolved => 'Resolved',
      EmergencyDispatchStatus.closed => 'Closed',
    };

Color _statusColor(EmergencyDispatchStatus value) => switch (value) {
      EmergencyDispatchStatus.assigned => TgcgColors.warning,
      EmergencyDispatchStatus.acknowledged => TgcgColors.info,
      EmergencyDispatchStatus.responding => TgcgColors.info,
      EmergencyDispatchStatus.onScene => TgcgColors.ai,
      EmergencyDispatchStatus.resolved => TgcgColors.success,
      EmergencyDispatchStatus.closed => TgcgColors.muted,
    };

IconData _statusIcon(EmergencyDispatchStatus value) => switch (value) {
      EmergencyDispatchStatus.assigned => Icons.assignment_ind_outlined,
      EmergencyDispatchStatus.acknowledged => Icons.check_circle_outline_rounded,
      EmergencyDispatchStatus.responding => Icons.directions_car_outlined,
      EmergencyDispatchStatus.onScene => Icons.location_on_outlined,
      EmergencyDispatchStatus.resolved => Icons.task_alt_rounded,
      EmergencyDispatchStatus.closed => Icons.lock_outline_rounded,
    };

IconData _agencyIcon(EmergencyAgencyType? type) => switch (type) {
      EmergencyAgencyType.police => Icons.local_police_outlined,
      EmergencyAgencyType.civilDefence => Icons.shield_outlined,
      EmergencyAgencyType.roadSafety => Icons.traffic_outlined,
      EmergencyAgencyType.fireRescue => Icons.local_fire_department_outlined,
      EmergencyAgencyType.medical => Icons.medical_services_outlined,
      EmergencyAgencyType.other || null => Icons.emergency_outlined,
    };
