import 'package:flutter/material.dart';

import '../assignments/assignment_store.dart';
import '../devices/managed_device_store.dart';
import '../domain/permissions.dart';
import '../evidence/device_evidence_service.dart';
import '../geography/geography_registry.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'field_operations_store.dart';

class FieldMonitoringPage extends StatefulWidget {
  const FieldMonitoringPage({super.key});

  @override
  State<FieldMonitoringPage> createState() => _FieldMonitoringPageState();
}

class _FieldMonitoringPageState extends State<FieldMonitoringPage> {
  String? selectedIncidentId;
  IncidentStatus? statusFilter;
  IncidentSeverity? severityFilter;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = FieldOperations.of(context);
    var incidents = store.incidentsForScope(session.scope);
    final reports = store.reportsForScope(session.scope);
    final permissions = session.role!;
    final canCreateIncident = TgcgPermissionPolicy.allows(
      permissions,
      TgcgCapability.createIncident,
    );
    final canSubmitFieldReport = TgcgPermissionPolicy.allows(
      permissions,
      TgcgCapability.submitFieldReport,
    );
    final canAcknowledge = TgcgPermissionPolicy.allows(
      permissions,
      TgcgCapability.acknowledgeIncident,
    );
    final canAssign = TgcgPermissionPolicy.allows(
      permissions,
      TgcgCapability.assignIncident,
    );
    final canClose = TgcgPermissionPolicy.allows(
      permissions,
      TgcgCapability.closeIncident,
    );

    if (statusFilter != null) {
      incidents = incidents
          .where((item) => item.status == statusFilter)
          .toList(growable: false);
    }
    if (severityFilter != null) {
      incidents = incidents
          .where((item) => item.severity == severityFilter)
          .toList(growable: false);
    }

    incidents = List<FieldIncident>.from(incidents)
      ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    final allScoped = store.incidentsForScope(session.scope);
    final selected = selectedIncidentId == null
        ? (incidents.isEmpty ? null : incidents.first)
        : allScoped.where((item) => item.id == selectedIncidentId).firstOrNull;

    final open = allScoped
        .where(
          (item) =>
              item.status != IncidentStatus.resolved &&
              item.status != IncidentStatus.closed,
        )
        .length;
    final highPriority = allScoped
        .where(
          (item) =>
              item.severity == IncidentSeverity.high ||
              item.severity == IncidentSeverity.critical,
        )
        .length;
    final evidence = allScoped.fold<int>(
      0,
      (total, item) => total + item.evidence.length,
    );
    final geoTagged = allScoped
        .where((item) => item.latitude != null && item.longitude != null)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'FIELD OPERATIONS',
          title: 'Field Monitoring & Incident Capture',
          subtitle:
              '${session.scope.label}: structured field reporting, incident response, evidence context and operational escalation.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canSubmitFieldReport)
                OutlinedButton.icon(
                  onPressed: () => _showFieldReportDialog(context),
                  icon: const Icon(Icons.post_add_rounded),
                  label: const Text('Field report'),
                ),
              if (canCreateIncident)
                FilledButton.icon(
                  onPressed: () => _showIncidentDialog(context),
                  icon: const Icon(Icons.report_problem_outlined),
                  label: const Text('Report incident'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(
          openIncidents: open,
          highPriority: highPriority,
          fieldReports: reports.length,
          evidenceItems: evidence,
          geoTagged: geoTagged,
        ),
        const SizedBox(height: 16),
        _CaptureReadinessBanner(),
        const SizedBox(height: 16),
        _Filters(
          status: statusFilter,
          severity: severityFilter,
          onStatusChanged: (value) => setState(() => statusFilter = value),
          onSeverityChanged: (value) => setState(() => severityFilter = value),
          onClear: () => setState(() {
            statusFilter = null;
            severityFilter = null;
          }),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final queue = _IncidentQueue(
              incidents: incidents,
              selectedId: selected?.id,
              onSelect: (id) => setState(() => selectedIncidentId = id),
            );
            final inspector = _IncidentInspector(
              incident: selected,
              canAcknowledge: canAcknowledge,
              canAssign: canAssign,
              canClose: canClose,
              onStatusChanged: (status) {
                if (selected == null) return;
                store.updateIncidentStatus(selected.id, status);
              },
            );
            if (constraints.maxWidth < 1050) {
              return Column(
                children: [
                  queue,
                  const SizedBox(height: 16),
                  inspector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: queue),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: inspector),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _FieldActivityFeed(incidents: allScoped, reports: reports),
      ],
    );
  }

  Future<void> _showIncidentDialog(BuildContext context) async {
    final session = TgcgSession.of(context, listen: false);
    final membership = MembershipOperations.of(context, listen: false);
    final assignments = Assignments.of(context, listen: false);
    final devices = ManagedDevices.of(context, listen: false);
    final store = FieldOperations.of(context, listen: false);
    final evidenceService = DeviceEvidenceService();
    final title = TextEditingController();
    final summary = TextEditingController();
    final captured = <CapturedEvidence>[];
    var captureBusy = false;
    double? incidentLatitude;
    double? incidentLongitude;
    var category = _incidentCategories.first;
    var severity = IncidentSeverity.medium;

    final agent = session.role == TgcgRole.pollingUnitAgent
        ? _fieldAgentByAccessId(membership, session.accessId)
        : null;
    final memberId = session.role == TgcgRole.member
        ? session.accessId
        : agent?.memberId;
    final activeAssignments = memberId == null
        ? const <MemberAssignment>[]
        : assignments.activeAssignmentsForMember(memberId);
    MemberAssignment? selectedAssignment =
        activeAssignments.isEmpty ? null : activeAssignments.first;
    final managedDevice =
        memberId == null ? null : devices.deviceForMember(memberId);

    final scopedUnits = membership.geography.pollingUnitsWithin(session.scope);
    final unitById = <String, CanonicalPollingUnit>{
      for (final unit in scopedUnits) unit.code: unit,
    };
    for (final assignment in activeAssignments) {
      final unit =
          membership.geography.pollingUnit(assignment.targetPollingUnitId);
      if (unit != null) unitById[unit.code] = unit;
    }
    final units = unitById.values.toList(growable: false);
    GeographicScope scope = selectedAssignment?.targetScope ??
        (units.isEmpty ? session.scope : units.first.scope);

    Future<void> capture(
      StateSetter setDialogState,
      Future<CapturedEvidence?> Function() action,
    ) async {
      setDialogState(() => captureBusy = true);
      try {
        final item = await action();
        if (item == null) return;
        setDialogState(() {
          captured.add(item);
          if (item.latitude != null && item.longitude != null) {
            incidentLatitude = item.latitude;
            incidentLongitude = item.longitude;
          }
        });
      } finally {
        setDialogState(() => captureBusy = false);
      }
    }

    final created = await showDialog<FieldIncident>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report field incident'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Incident title',
                      hintText: 'Short factual description',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration: const InputDecoration(labelText: 'Category'),
                          items: _incidentCategories
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setDialogState(
                            () => category = value ?? category,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<IncidentSeverity>(
                          initialValue: severity,
                          decoration: const InputDecoration(labelText: 'Severity'),
                          items: IncidentSeverity.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_label(value.name)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setDialogState(
                            () => severity = value ?? severity,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<GeographicScope>(
                    initialValue: scope,
                    decoration: const InputDecoration(labelText: 'Field location'),
                    isExpanded: true,
                    items: (units.isEmpty
                            ? <GeographicScope>[session.scope]
                            : units.map((unit) => unit.scope).toList())
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => scope = value ?? scope,
                    ),
                  ),
                  if (activeAssignments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedAssignment?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Operational assignment',
                        prefixIcon: Icon(Icons.assignment_ind_outlined),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('No assignment linkage'),
                        ),
                        ...activeAssignments.map(
                          (assignment) => DropdownMenuItem<String>(
                            value: assignment.id,
                            child: Text(
                              '${assignment.title} • ${assignment.targetScope.label}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) => setDialogState(() {
                        selectedAssignment = value == null || value.isEmpty
                            ? null
                            : activeAssignments
                                .where((item) => item.id == value)
                                .firstOrNull;
                        if (selectedAssignment != null) {
                          scope = selectedAssignment!.targetScope;
                        }
                      }),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: summary,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'What happened?',
                      hintText: 'Record observable facts and operational impact.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DeviceCaptureIntegrationPanel(
                    captured: captured,
                    busy: captureBusy,
                    onPhoto: () => capture(
                      setDialogState,
                      evidenceService.capturePhoto,
                    ),
                    onVideo: () => capture(
                      setDialogState,
                      evidenceService.captureVideo,
                    ),
                    onGps: () => capture(
                      setDialogState,
                      () async => evidenceService.captureLocation(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                final reporterId = session.accessId.isEmpty
                    ? session.operatorName
                    : session.accessId;
                final attachments = <EvidenceAttachment>[
                  for (var index = 0; index < captured.length; index++)
                    EvidenceAttachment(
                      id:
                          'EVD-${DateTime.now().microsecondsSinceEpoch}-$index',
                      type: captured[index].type,
                      fileName: captured[index].fileName,
                      createdAt: captured[index].createdAt,
                      uploaderId: reporterId,
                      contentHash: captured[index].contentHash,
                      mimeType: captured[index].mimeType,
                      sourceReference: captured[index].path,
                      latitude: captured[index].latitude,
                      longitude: captured[index].longitude,
                      caption:
                          'Captured with the incident report and queued for secure media synchronization.',
                      origin: RecordOrigin.localEntry,
                    ),
                ];
                final incident = await store.createIncident(
                  title: title.text,
                  category: category,
                  severity: severity,
                  scope: scope,
                  reporterId: reporterId,
                  summary: summary.text,
                  assignmentId: selectedAssignment?.id,
                  deviceId: managedDevice?.id,
                  latitude: incidentLatitude ??
                      selectedAssignment?.lastLocation?.latitude,
                  longitude: incidentLongitude ??
                      selectedAssignment?.lastLocation?.longitude,
                  evidence: attachments,
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, incident);
                }
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('Save incident'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    summary.dispose();
    await evidenceService.dispose();
    if (created != null && context.mounted) {
      setState(() => selectedIncidentId = created.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${created.id} encrypted locally and queued for sync with ${created.evidence.length} evidence item(s)${created.latitude != null ? ' and GPS coordinates' : ''}.',
          ),
        ),
      );
    }
  }

  Future<void> _showFieldReportDialog(BuildContext context) async {
    final session = TgcgSession.of(context, listen: false);
    final membership = MembershipOperations.of(context, listen: false);
    final store = FieldOperations.of(context, listen: false);
    final summary = TextEditingController();
    var category = _reportCategories.first;
    final units = membership.geography.pollingUnitsWithin(session.scope);
    GeographicScope scope = units.isEmpty ? session.scope : units.first.scope;
    String? incidentId;
    final availableIncidents = store
        .incidentsForScope(session.scope)
        .where(
          (item) =>
              item.status != IncidentStatus.closed &&
              item.status != IncidentStatus.resolved,
        )
        .toList(growable: false);

    final created = await showDialog<FieldReport>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Submit field report'),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Report category'),
                    items: _reportCategories
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => category = value ?? category,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<GeographicScope>(
                    initialValue: scope,
                    decoration: const InputDecoration(labelText: 'Field location'),
                    isExpanded: true,
                    items: (units.isEmpty
                            ? <GeographicScope>[session.scope]
                            : units.map((unit) => unit.scope).toList())
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => scope = value ?? scope,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: incidentId,
                    decoration: const InputDecoration(
                      labelText: 'Related incident (optional)',
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No linked incident'),
                      ),
                      ...availableIncidents.map(
                        (incident) => DropdownMenuItem<String?>(
                          value: incident.id,
                          child: Text(
                            '${incident.id} • ${incident.title}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() => incidentId = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: summary,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Field update',
                      hintText: 'Record the current operational situation.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (summary.text.trim().isEmpty) return;
                final report = await store.submitFieldReport(
                  category: category,
                  summary: summary.text,
                  scope: scope,
                  reporterId: session.accessId.isEmpty
                      ? session.operatorName
                      : session.accessId,
                  incidentId: incidentId,
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, report);
                }
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('Submit report'),
            ),
          ],
        ),
      ),
    );
    summary.dispose();
    if (created != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${created.id} encrypted locally and queued for sync.'),
        ),
      );
    }
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.openIncidents,
    required this.highPriority,
    required this.fieldReports,
    required this.evidenceItems,
    required this.geoTagged,
  });

  final int openIncidents;
  final int highPriority;
  final int fieldReports;
  final int evidenceItems;
  final int geoTagged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1050
              ? 5
              : constraints.maxWidth >= 650
                  ? 3
                  : constraints.maxWidth >= 430
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
                value: '$openIncidents',
                detail: 'Requires response or closure',
                icon: Icons.warning_amber_rounded,
                tone: openIncidents > 0
                    ? TgcgMetricTone.warning
                    : TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'High priority',
                value: '$highPriority',
                detail: 'High + critical severity',
                icon: Icons.priority_high_rounded,
                tone: highPriority > 0
                    ? TgcgMetricTone.danger
                    : TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Field reports',
                value: '$fieldReports',
                detail: 'Structured operational updates',
                icon: Icons.feed_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Evidence items',
                value: '$evidenceItems',
                detail: 'Media/provenance references',
                icon: Icons.inventory_2_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'GPS tagged',
                value: '$geoTagged',
                detail: 'Stored coordinates only',
                icon: Icons.location_on_outlined,
                tone: TgcgMetricTone.neutral,
              ),
            ],
          );
        },
      );
}

class _CaptureReadinessBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: TgcgGradients.navigation,
          borderRadius: BorderRadius.circular(TgcgRadius.lg),
          border: Border.all(
            color: TgcgColors.accent.withValues(alpha: .18),
          ),
          boxShadow: TgcgShadows.soft,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final text = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'FIELD CAPTURE READINESS',
                  style: TextStyle(
                    color: TgcgColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.05,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Native photo, video and GPS capture are connected to incident and assignment workflows.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Captured media keeps its hash, source reference and assignment/device context; missing data remains explicit.',
                  style: TextStyle(
                    color: TgcgColors.gold200,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                ),
              ],
            );
            final chips = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _DarkPill('TEXT RECORDS', Icons.check_circle_outline_rounded),
                _DarkPill('PHOTO READY', Icons.photo_camera_outlined),
                _DarkPill('VIDEO READY', Icons.videocam_outlined),
                _DarkPill('AUDIO READY', Icons.mic_none_rounded),
                _DarkPill('GPS READY', Icons.my_location_rounded),
              ],
            );
            if (constraints.maxWidth < 820) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [text, const SizedBox(height: 14), chips],
              );
            }
            return Row(
              children: [
                Expanded(flex: 6, child: text),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: chips),
              ],
            );
          },
        ),
      );
}

class _DarkPill extends StatelessWidget {
  const _DarkPill(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: TgcgColors.gold200, size: 15),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: TgcgColors.gold200,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.status,
    required this.severity,
    required this.onStatusChanged,
    required this.onSeverityChanged,
    required this.onClear,
  });

  final IncidentStatus? status;
  final IncidentSeverity? severity;
  final ValueChanged<IncidentStatus?> onStatusChanged;
  final ValueChanged<IncidentSeverity?> onSeverityChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Incident filters',
        subtitle: 'Filter by workflow state or operational severity.',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<IncidentStatus?>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All statuses')),
                  ...IncidentStatus.values.map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_label(value.name)),
                    ),
                  ),
                ],
                onChanged: onStatusChanged,
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<IncidentSeverity?>(
                initialValue: severity,
                decoration: const InputDecoration(labelText: 'Severity'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All severities')),
                  ...IncidentSeverity.values.map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_label(value.name)),
                    ),
                  ),
                ],
                onChanged: onSeverityChanged,
              ),
            ),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear_rounded),
              label: const Text('Clear'),
            ),
          ],
        ),
      );
}

class _IncidentQueue extends StatelessWidget {
  const _IncidentQueue({
    required this.incidents,
    required this.selectedId,
    required this.onSelect,
  });

  final List<FieldIncident> incidents;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Incident queue',
        subtitle: 'Newest scoped incidents first.',
        child: incidents.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'No incident in this view',
                message: 'Change the filters or report a new field incident.',
              )
            : Column(
                children: incidents
                    .map(
                      (incident) => _IncidentRow(
                        incident: incident,
                        selected: incident.id == selectedId,
                        onTap: () => onSelect(incident.id),
                      ),
                    )
                    .toList(),
              ),
      );
}

class _IncidentRow extends StatelessWidget {
  const _IncidentRow({
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: .055)
                : TgcgColors.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: .22)
                  : TgcgColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.warning_amber_rounded, color: color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      incident.title,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${incident.id} • ${incident.category} • ${incident.scope.label}',
                      maxLines: 2,
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
                    label: _label(incident.severity.name).toUpperCase(),
                    color: color,
                    compact: true,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _shortTime(incident.reportedAt),
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9,
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
}

class _IncidentInspector extends StatelessWidget {
  const _IncidentInspector({
    required this.incident,
    required this.canAcknowledge,
    required this.canAssign,
    required this.canClose,
    required this.onStatusChanged,
  });

  final FieldIncident? incident;
  final bool canAcknowledge;
  final bool canAssign;
  final bool canClose;
  final ValueChanged<IncidentStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final current = incident;
    if (current == null) {
      return const TgcgSectionCard(
        title: 'Incident inspector',
        subtitle: 'Select an incident to inspect its operational record.',
        child: TgcgEmptyState(
          icon: Icons.manage_search_rounded,
          title: 'No incident selected',
          message: 'Choose an incident from the queue.',
        ),
      );
    }

    final severityColor = _severityColor(current.severity);
    return TgcgSectionCard(
      title: 'Incident inspector',
      subtitle: 'Field evidence and response workflow remain traceable to the source record.',
      trailing: TgcgStatusPill(
        label: _label(current.status.name).toUpperCase(),
        color: _statusColor(current.status),
        icon: Icons.flag_outlined,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: severityColor.withValues(alpha: .18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.title,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${current.id} • ${current.category}',
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Detail('Severity', _label(current.severity.name)),
          _Detail('Scope', current.scope.label),
          _Detail('Reporter', current.reporterId),
          if (current.assignmentId != null)
            _Detail('Assignment', current.assignmentId!),
          if (current.deviceId != null)
            _Detail('Managed device', current.deviceId!),
          _Detail('Reported', _fullTime(current.reportedAt)),
          _Detail('Response owner', current.assignedTeam ?? 'Unassigned'),
          _Detail(
            'GPS',
            current.latitude != null && current.longitude != null
                ? '${current.latitude}, ${current.longitude}'
                : 'Not captured',
          ),
          if (current.summary != null) ...[
            const SizedBox(height: 12),
            const Text(
              'Summary',
              style: TextStyle(
                color: TgcgColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              current.summary!,
              style: const TextStyle(
                color: TgcgColors.muted,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _EvidencePanel(evidence: current.evidence),
          const SizedBox(height: 14),
          _ResponseTimeline(incident: current),
          if (canAcknowledge || canAssign || canClose) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canAcknowledge && current.status == IncidentStatus.reported)
                  OutlinedButton.icon(
                    onPressed: () => onStatusChanged(IncidentStatus.acknowledged),
                    icon: const Icon(Icons.done_rounded),
                    label: const Text('Acknowledge'),
                  ),
                if (canAssign &&
                    current.status != IncidentStatus.resolved &&
                    current.status != IncidentStatus.closed)
                  OutlinedButton.icon(
                    onPressed: () => onStatusChanged(IncidentStatus.investigating),
                    icon: const Icon(Icons.manage_search_rounded),
                    label: const Text('Investigate'),
                  ),
                if (canAssign &&
                    current.status != IncidentStatus.resolved &&
                    current.status != IncidentStatus.closed)
                  OutlinedButton.icon(
                    onPressed: () => onStatusChanged(IncidentStatus.escalated),
                    icon: const Icon(Icons.north_east_rounded),
                    label: const Text('Escalate'),
                  ),
                if (canClose &&
                    current.status != IncidentStatus.resolved &&
                    current.status != IncidentStatus.closed)
                  FilledButton.icon(
                    onPressed: () => onStatusChanged(IncidentStatus.resolved),
                    icon: const Icon(Icons.check_circle_outline_rounded),
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

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({required this.evidence});

  final List<EvidenceAttachment> evidence;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evidence',
            style: TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          if (evidence.isEmpty)
            const Text(
              'No evidence attachment stored with this incident.',
              style: TextStyle(color: TgcgColors.muted, fontSize: 10.5),
            )
          else
            ...evidence.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TgcgColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: TgcgColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      _evidenceIcon(item.type),
                      color: TgcgColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.fileName,
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.contentHash ?? 'Hash unavailable',
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
                  ],
                ),
              ),
            ),
        ],
      );
}

class _ResponseTimeline extends StatelessWidget {
  const _ResponseTimeline({required this.incident});

  final FieldIncident incident;

  @override
  Widget build(BuildContext context) {
    final steps = <({String title, String detail, bool active})>[
      (
        title: 'Reported',
        detail: _fullTime(incident.reportedAt),
        active: true,
      ),
      (
        title: 'Acknowledged',
        detail: 'Response workflow entered',
        active: incident.status != IncidentStatus.reported,
      ),
      (
        title: 'Response ownership',
        detail: incident.assignedTeam ?? 'Awaiting assignment',
        active: incident.assignedTeam != null,
      ),
      (
        title: 'Resolved',
        detail: incident.status == IncidentStatus.closed
            ? 'Closed after resolution'
            : 'Operational closure pending',
        active: incident.status == IncidentStatus.resolved ||
            incident.status == IncidentStatus.closed,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Response timeline',
          style: TextStyle(
            color: TgcgColors.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 9),
        ...steps.map(
          (step) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  step.active
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: step.active ? TgcgColors.success : TgcgColors.muted,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        step.detail,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldActivityFeed extends StatelessWidget {
  const _FieldActivityFeed({required this.incidents, required this.reports});

  final List<FieldIncident> incidents;
  final List<FieldReport> reports;

  @override
  Widget build(BuildContext context) {
    final events = <_FeedEvent>[
      ...incidents.map(
        (item) => _FeedEvent(
          at: item.reportedAt,
          title: item.title,
          detail: 'Incident • ${item.id} • ${_label(item.status.name)}',
          icon: Icons.warning_amber_rounded,
          color: _severityColor(item.severity),
        ),
      ),
      ...reports.map(
        (item) => _FeedEvent(
          at: item.reportedAt,
          title: item.category,
          detail: 'Field report • ${item.id} • ${_label(item.status.name)}',
          icon: Icons.feed_outlined,
          color: TgcgColors.info,
        ),
      ),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return TgcgSectionCard(
      title: 'Live field activity',
      subtitle: 'Combined incident and structured-report feed for the current scope.',
      child: events.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.sensors_off_outlined,
              title: 'No field activity in scope',
              message: 'Incident and field-report activity will appear here.',
            )
          : Column(
              children: events
                  .take(20)
                  .map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: event.color.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(event.icon, color: event.color, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  style: const TextStyle(
                                    color: TgcgColors.ink,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  event.detail,
                                  style: const TextStyle(
                                    color: TgcgColors.muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _shortTime(event.at),
                            style: const TextStyle(
                              color: TgcgColors.muted,
                              fontSize: 9,
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

class _FeedEvent {
  const _FeedEvent({
    required this.at,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final DateTime at;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
}

class _DeviceCaptureIntegrationPanel extends StatelessWidget {
  const _DeviceCaptureIntegrationPanel({
    required this.captured,
    required this.busy,
    required this.onPhoto,
    required this.onVideo,
    required this.onGps,
  });

  final List<CapturedEvidence> captured;
  final bool busy;
  final VoidCallback onPhoto;
  final VoidCallback onVideo;
  final VoidCallback onGps;

  @override
  Widget build(BuildContext context) {
    final photos =
        captured.where((item) => item.type == EvidenceType.photo).length;
    final videos =
        captured.where((item) => item.type == EvidenceType.video).length;
    final locations =
        captured.where((item) => item.type == EvidenceType.location).length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [TgcgColors.surface, TgcgColors.navy50],
        ),
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: TgcgColors.accentStrong,
                size: 19,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Security evidence package',
                  style: TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Capture field media and exact GPS before saving. Attached evidence is hashed and follows the incident into the Security Response Portal.',
            style: TextStyle(
              color: TgcgColors.muted,
              fontSize: 10,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onPhoto,
                icon: const Icon(Icons.photo_camera_outlined, size: 17),
                label: Text(photos == 0 ? 'Capture photo' : 'Photo • $photos'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onVideo,
                icon: const Icon(Icons.videocam_outlined, size: 17),
                label: Text(videos == 0 ? 'Capture video' : 'Video • $videos'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onGps,
                icon: const Icon(Icons.my_location_rounded, size: 17),
                label: Text(
                  locations == 0 ? 'Capture GPS' : 'GPS • attached',
                ),
              ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          if (captured.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: captured
                  .map(
                    (item) => TgcgStatusPill(
                      label: item.type.name.toUpperCase(),
                      color: item.contentHash == null
                          ? TgcgColors.warning
                          : TgcgColors.success,
                      icon: item.type == EvidenceType.video
                          ? Icons.play_circle_outline_rounded
                          : item.type == EvidenceType.photo
                              ? Icons.photo_outlined
                              : Icons.gps_fixed_rounded,
                      compact: true,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                label,
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
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

AccreditedAgent? _fieldAgentByAccessId(
  MembershipOperationsController membership,
  String accessId,
) {
  final normalized = accessId.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final agent in membership.agents) {
    if (agent.role != TgcgRole.pollingUnitAgent) continue;
    if (agent.agentId.toLowerCase() == normalized ||
        (agent.registeredPhoneNumber ?? '').trim().toLowerCase() ==
            normalized) {
      return agent;
    }
  }
  return null;
}

const _incidentCategories = <String>[
  'Access',
  'Security',
  'Violence / threat',
  'Evidence quality',
  'Geolocation',
  'Technical',
  'Materials / logistics',
  'Process irregularity',
  'Other',
];

const _reportCategories = <String>[
  'Opening status',
  'Operational update',
  'Materials update',
  'Queue / turnout observation',
  'Connectivity update',
  'Closing status',
  'Other',
];

Color _severityColor(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.info => TgcgColors.info,
      IncidentSeverity.low => TgcgColors.success,
      IncidentSeverity.medium => TgcgColors.warning,
      IncidentSeverity.high => const Color(0xFFE25C2A),
      IncidentSeverity.critical => TgcgColors.danger,
    };

Color _statusColor(IncidentStatus status) => switch (status) {
      IncidentStatus.reported => TgcgColors.warning,
      IncidentStatus.acknowledged => TgcgColors.info,
      IncidentStatus.assigned => TgcgColors.ai,
      IncidentStatus.investigating => TgcgColors.ai,
      IncidentStatus.escalated => TgcgColors.danger,
      IncidentStatus.resolved => TgcgColors.success,
      IncidentStatus.closed => TgcgColors.muted,
    };

IconData _evidenceIcon(EvidenceType type) => switch (type) {
      EvidenceType.photo => Icons.image_outlined,
      EvidenceType.video => Icons.videocam_outlined,
      EvidenceType.audio => Icons.audio_file_outlined,
      EvidenceType.document => Icons.description_outlined,
      EvidenceType.resultForm => Icons.document_scanner_outlined,
      EvidenceType.location => Icons.location_on_outlined,
    };

String _shortTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _fullTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  final clean = spaced.replaceAll('_', ' ');
  return clean.isEmpty
      ? clean
      : '${clean[0].toUpperCase()}${clean.substring(1)}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
