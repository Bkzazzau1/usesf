import 'package:flutter/material.dart';

import '../access/access_policy.dart';
import '../assignments/assignment_store.dart';
import '../devices/managed_device_store.dart';
import '../domain/permissions.dart';
import '../field/field_operations_store.dart';
import '../governance/governance_store.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'geography_registry.dart';
import 'kaduna_geography.dart';
import 'polling_unit_verification_service.dart';

class GeographyPage extends StatefulWidget {
  const GeographyPage({super.key});

  @override
  State<GeographyPage> createState() => _GeographyPageState();
}

class _GeographyPageState extends State<GeographyPage> {
  final List<GeographicScope> path = [];
  final TextEditingController searchController = TextEditingController();
  final PollingUnitVerificationService verificationService =
      const PollingUnitVerificationService();
  String query = '';
  String? verifyingPollingUnitId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (path.isEmpty) {
      final scope = TgcgAccessPolicy.authorizingScope(
            context,
            TgcgCapability.viewGeography,
            listen: false,
          ) ??
          TgcgSession.of(context, listen: false).scope;
      path.add(scope);
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final assignments = Assignments.of(context);
    final devices = ManagedDevices.of(context);
    final field = FieldOperations.of(context);
    final governance = GovernanceOperations.of(context);
    final results = ResultOperations.of(context);
    final registry = membership.geography;
    final geographyScopes = TgcgAccessPolicy.scopesFor(
      context,
      TgcgCapability.viewGeography,
    );
    final canVerifyPollingUnit =
        TgcgAccessPolicy.allows(
          context,
          TgcgCapability.manageMembership,
        ) ||
        TgcgAccessPolicy.allows(
          context,
          TgcgCapability.manageAssignments,
        );
    final scope = path.last;
    final children = registry.childScopes(scope);
    final units = registry.pollingUnitsWithin(scope);
    final members = membership.membersForScope(scope);
    final activeAssignments = assignments
        .assignmentsForScope(scope)
        .where((item) => !item.isTerminal)
        .toList(growable: false);
    final activeRoles = governance
        .roleAssignmentsForScope(scope)
        .where((item) => item.active)
        .toList(growable: false);
    final incidents = field.incidentsForScope(scope);
    final openIncidents = incidents
        .where(
          (item) =>
              item.status != IncidentStatus.resolved &&
              item.status != IncidentStatus.closed,
        )
        .toList(growable: false);
    final submissions = results.submissionsForScope(scope);
    final verifiedResults = submissions
        .where((item) => item.status == RecordStatus.verified)
        .length;

    final needle = query.trim().toLowerCase();
    final visibleChildren = children.where((child) {
      if (needle.isEmpty) return true;
      return child.label.toLowerCase().contains(needle) ||
          (child.zoneName ?? '').toLowerCase().contains(needle) ||
          (child.stateName ?? '').toLowerCase().contains(needle) ||
          (child.lgaName ?? '').toLowerCase().contains(needle) ||
          (child.wardName ?? '').toLowerCase().contains(needle);
    }).toList(growable: false);

    final visibleUnits = units.where((unit) {
      if (needle.isEmpty) return true;
      return unit.code.toLowerCase().contains(needle) ||
          unit.displayCode.toLowerCase().contains(needle) ||
          unit.scope.label.toLowerCase().contains(needle);
    }).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'GEOGRAPHIC COMMAND',
          title: 'Geographic Operations',
          subtitle:
              '${scope.label}: members, assignments, incidents and result activity across the operational hierarchy.',
          trailing: TgcgStatusPill(
            label: _levelLabel(scope.level).toUpperCase(),
            color: TgcgColors.primary,
            icon: Icons.public_rounded,
          ),
        ),
        const SizedBox(height: 18),
        if (geographyScopes.length > 1) ...[
          TgcgSectionCard(
            title: 'Your authorized geographic scopes',
            subtitle:
                'Combined access can include several roles or assignments. Open any authorized scope below.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: geographyScopes
                  .map(
                    (authorized) => ActionChip(
                      avatar: const Icon(Icons.location_on_outlined, size: 16),
                      label: Text(authorized.label),
                      onPressed: () => setState(() {
                        path
                          ..clear()
                          ..add(authorized);
                        query = '';
                        searchController.clear();
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _BreadcrumbBar(
          path: path,
          onSelect: (index) => setState(() {
            path.removeRange(index + 1, path.length);
            query = '';
            searchController.clear();
          }),
        ),
        const SizedBox(height: 14),
        _MetricGrid(
          childAreas: children.length,
          members: members.length,
          assignments: activeAssignments.length,
          openIncidents: openIncidents.length,
          submissions: submissions.length,
          verifiedResults: verifiedResults,
        ),
        const SizedBox(height: 16),
        _PollingUnitRegistrySummary(
          registry: registry,
          membership: membership,
        ),
        const SizedBox(height: 16),
        _CoverageHero(
          scope: scope,
          children: children,
          membership: membership,
          assignments: assignments,
          devices: devices,
          field: field,
          results: results,
          onOpen: (child) => setState(() {
            path.add(child);
            query = '';
            searchController.clear();
          }),
        ),
        const SizedBox(height: 16),
        _DirectoryPanel(
          controller: searchController,
          query: query,
          children: visibleChildren,
          units: visibleUnits,
          membership: membership,
          assignments: assignments,
          devices: devices,
          field: field,
          results: results,
          canVerifyCoordinates: canVerifyPollingUnit,
          verifyingPollingUnitId: verifyingPollingUnitId,
          onVerifyPollingUnit: (unit) => _verifyPollingUnit(
            membership,
            session,
            unit,
          ),
          onQueryChanged: (value) => setState(() => query = value),
          onOpenChild: (child) => setState(() {
            path.add(child);
            query = '';
            searchController.clear();
          }),
        ),
        const SizedBox(height: 16),
        _RoleDeploymentPanel(
          roles: activeRoles,
          assignments: activeAssignments,
          membership: membership,
        ),
      ],
    );
  }

  Future<void> _verifyPollingUnit(
    MembershipOperationsController membership,
    TgcgSessionController session,
    CanonicalPollingUnit unit,
  ) async {
    if (verifyingPollingUnitId != null) return;
    final authorized =
        TgcgAccessPolicy.allows(
          context,
          TgcgCapability.manageMembership,
          targetScope: unit.scope,
          listen: false,
        ) ||
        TgcgAccessPolicy.allows(
          context,
          TgcgCapability.manageAssignments,
          targetScope: unit.scope,
          listen: false,
        );
    if (!authorized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This polling unit is outside your coordinate-verification authority.',
          ),
        ),
      );
      return;
    }
    setState(() => verifyingPollingUnitId = unit.code);
    try {
      final fix = await verificationService.captureCurrentFix();
      final actorId =
          session.accessId.isEmpty ? session.operatorName : session.accessId;
      final updated = await membership.verifyPollingUnitCoordinate(
        pollingUnitId: unit.code,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyMeters: fix.accuracyMeters,
        verifiedBy: actorId,
        verifiedAt: fix.capturedAt,
      );
      if (!mounted) return;

      final distance = updated.referenceToVerifiedDistanceMeters;
      final message = updated.coordinateStatus ==
              PollingUnitCoordinateStatus.needsReview
          ? 'GPS captured at ±${fix.accuracyMeters.toStringAsFixed(1)} m. '
              'Reference difference ${distance?.toStringAsFixed(0) ?? '—'} m; review required.'
          : 'Polling unit GPS verified at ±${fix.accuracyMeters.toStringAsFixed(1)} m accuracy.';
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
        SnackBar(content: Text('GPS verification failed: $error')),
      );
    } finally {
      if (mounted) setState(() => verifyingPollingUnitId = null);
    }
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.childAreas,
    required this.members,
    required this.assignments,
    required this.openIncidents,
    required this.submissions,
    required this.verifiedResults,
  });

  final int childAreas;
  final int members;
  final int assignments;
  final int openIncidents;
  final int submissions;
  final int verifiedResults;

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
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Areas',
                value: '$childAreas',
                detail: 'Direct geographic areas',
                icon: Icons.account_tree_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Members',
                value: '$members',
                detail: 'Registered in this scope',
                icon: Icons.groups_2_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Assignments',
                value: '$assignments',
                detail: 'Active operational assignments',
                icon: Icons.assignment_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Open incidents',
                value: '$openIncidents',
                detail: 'Active field incidents',
                icon: Icons.crisis_alert_outlined,
                tone: openIncidents == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Results',
                value: '$submissions',
                detail: 'Submissions received',
                icon: Icons.ballot_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Verified',
                value: '$verifiedResults',
                detail: 'Verified result records',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.success,
              ),
            ],
          );
        },
      );
}

class _PollingUnitRegistrySummary extends StatelessWidget {
  const _PollingUnitRegistrySummary({
    required this.registry,
    required this.membership,
  });

  final GeographyRegistry registry;
  final MembershipOperationsController membership;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Polling Unit Master Registry',
        subtitle:
            'Canonical polling-unit identity, coordinate readiness and member linkage. Reference and field-verified coordinates remain separate.',
        child: LayoutBuilder(
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
                  label: 'Registry loaded',
                  value: '${registry.pollingUnits.length}',
                  detail: 'of $kadunaPollingUnitCount statewide target',
                  icon: Icons.how_to_vote_outlined,
                  tone: TgcgMetricTone.info,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Coordinates ready',
                  value: '${registry.coordinateReadyCount}',
                  detail: 'Reference or field coordinate',
                  icon: Icons.gps_fixed_rounded,
                  tone: TgcgMetricTone.success,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Field verified',
                  value: '${registry.fieldVerifiedCoordinateCount}',
                  detail: 'Verified on location',
                  icon: Icons.verified_outlined,
                  tone: TgcgMetricTone.success,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Needs review',
                  value: '${registry.coordinateReviewCount}',
                  detail: 'Reference/GPS mismatch',
                  icon: Icons.rule_folder_outlined,
                  tone: registry.coordinateReviewCount == 0
                      ? TgcgMetricTone.neutral
                      : TgcgMetricTone.warning,
                ),
                TgcgMetricCard(
                  width: width,
                  label: 'Members PU-linked',
                  value: '${membership.membersWithHomePollingUnit}',
                  detail:
                      '${membership.membersWithoutHomePollingUnit} members pending',
                  icon: Icons.person_pin_circle_outlined,
                  tone: membership.membersWithoutHomePollingUnit == 0
                      ? TgcgMetricTone.success
                      : TgcgMetricTone.warning,
                ),
              ],
            );
          },
        ),
      );
}

class _CoverageHero extends StatelessWidget {
  const _CoverageHero({
    required this.scope,
    required this.children,
    required this.membership,
    required this.assignments,
    required this.devices,
    required this.field,
    required this.results,
    required this.onOpen,
  });

  final GeographicScope scope;
  final List<GeographicScope> children;
  final MembershipOperationsController membership;
  final AssignmentController assignments;
  final ManagedDeviceController devices;
  final FieldOperationsController field;
  final ResultOperationsController results;
  final ValueChanged<GeographicScope> onOpen;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: TgcgGradients.navigation,
          borderRadius: BorderRadius.circular(TgcgRadius.lg),
          border: Border.all(
            color: TgcgColors.accent.withValues(alpha: .20),
          ),
          boxShadow: TgcgShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: TgcgColors.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(TgcgRadius.sm),
                    border: Border.all(
                      color: TgcgColors.accent.withValues(alpha: .18),
                    ),
                  ),
                  child: const Icon(
                    Icons.public_rounded,
                    color: TgcgColors.accent,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scope.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _coverageSubtitle(scope.level, children.length),
                        style: const TextStyle(
                          color: TgcgColors.gold200,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1050
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
                    children: children.map((child) {
                      final members = membership.memberCountForScope(child);
                      final activeAssignments = assignments
                          .assignmentsForScope(child)
                          .where((item) => !item.isTerminal)
                          .toList(growable: false);
                      final present = activeAssignments
                          .where(
                            (item) =>
                                assignments.presenceFor(item) ==
                                AssignmentPresence.insideGeofence,
                          )
                          .length;
                      final openIncidents = field
                          .incidentsForScope(child)
                          .where(
                            (item) =>
                                item.status != IncidentStatus.resolved &&
                                item.status != IncidentStatus.closed,
                          )
                          .length;

                      return SizedBox(
                        width: width,
                        child: Material(
                          color: Colors.white.withValues(alpha: .045),
                          borderRadius: BorderRadius.circular(TgcgRadius.md),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(TgcgRadius.md),
                            onTap: () => onOpen(child),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _scopeIcon(child.level),
                                        color: TgcgColors.accent,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          _shortLabel(child),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: TgcgColors.gold200,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _DarkMetric(
                                          value: members,
                                          label: 'Members',
                                        ),
                                      ),
                                      Expanded(
                                        child: _DarkMetric(
                                          value: activeAssignments.length,
                                          label: 'Assigned',
                                        ),
                                      ),
                                      Expanded(
                                        child: _DarkMetric(
                                          value: present,
                                          label: 'Present',
                                        ),
                                      ),
                                      Expanded(
                                        child: _DarkMetric(
                                          value: openIncidents,
                                          label: 'Incidents',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ],
        ),
      );
}

class _DarkMetric extends StatelessWidget {
  const _DarkMetric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9DA5B6),
              fontSize: 8.5,
            ),
          ),
        ],
      );
}

class _DirectoryPanel extends StatelessWidget {
  const _DirectoryPanel({
    required this.controller,
    required this.query,
    required this.children,
    required this.units,
    required this.membership,
    required this.assignments,
    required this.devices,
    required this.field,
    required this.results,
    required this.canVerifyCoordinates,
    required this.verifyingPollingUnitId,
    required this.onVerifyPollingUnit,
    required this.onQueryChanged,
    required this.onOpenChild,
  });

  final TextEditingController controller;
  final String query;
  final List<GeographicScope> children;
  final List<CanonicalPollingUnit> units;
  final MembershipOperationsController membership;
  final AssignmentController assignments;
  final ManagedDeviceController devices;
  final FieldOperationsController field;
  final ResultOperationsController results;
  final bool canVerifyCoordinates;
  final String? verifyingPollingUnitId;
  final ValueChanged<CanonicalPollingUnit> onVerifyPollingUnit;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<GeographicScope> onOpenChild;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: children.isNotEmpty ? 'Geographic directory' : 'Polling units',
        subtitle: children.isNotEmpty
            ? 'Search and open the next level of the operational hierarchy.'
            : 'Polling units recorded within the selected scope.',
        child: Column(
          children: [
            TextField(
              controller: controller,
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                hintText: 'Search geographic area or polling unit',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (children.isNotEmpty)
              ...children.map((child) => _AreaRow(
                    scope: child,
                    members: membership.memberCountForScope(child),
                    assignments: assignments
                        .assignmentsForScope(child)
                        .where((item) => !item.isTerminal)
                        .length,
                    incidents: field
                        .incidentsForScope(child)
                        .where(
                          (item) =>
                              item.status != IncidentStatus.resolved &&
                              item.status != IncidentStatus.closed,
                        )
                        .length,
                    results: results.submissionsForScope(child).length,
                    onTap: () => onOpenChild(child),
                  ))
            else if (units.isNotEmpty)
              ...units.map((unit) {
                final members =
                    membership.memberCountForPollingUnit(unit.code);
                final unitAssignments = assignments
                    .assignmentsForScope(unit.scope)
                    .where((item) => !item.isTerminal)
                    .toList(growable: false);
                final atLocation = unitAssignments
                    .where(
                      (item) =>
                          assignments.presenceFor(item) ==
                          AssignmentPresence.insideGeofence,
                    )
                    .length;
                final submissions = results.submissionsForScope(unit.scope);
                final verified = submissions.any(
                  (item) => item.status == RecordStatus.verified,
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _showPollingUnitRoster(context, unit),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: TgcgColors.primarySoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      color: TgcgColors.primary,
                      size: 19,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          unit.displayCode,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (canVerifyCoordinates)
                        IconButton(
                          tooltip: unit.hasVerifiedCoordinate
                              ? 'Re-verify polling-unit GPS'
                              : 'Verify polling-unit GPS',
                          onPressed: verifyingPollingUnitId == null
                              ? () => onVerifyPollingUnit(unit)
                              : null,
                          icon: verifyingPollingUnitId == unit.code
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  unit.hasVerifiedCoordinate
                                      ? Icons.gps_fixed_rounded
                                      : Icons.add_location_alt_outlined,
                                  size: 19,
                                ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    unit.operationalLatitude == null
                        ? unit.scope.label
                        : '${unit.scope.label}\n'
                            '${unit.operationalLatitude!.toStringAsFixed(6)}, '
                            '${unit.operationalLongitude!.toStringAsFixed(6)}'
                            '${unit.verificationAccuracyMeters == null ? '' : ' • ±${unit.verificationAccuracyMeters!.toStringAsFixed(1)} m'}',
                  ),
                  isThreeLine: unit.operationalLatitude != null,
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      TgcgStatusPill(
                        label: '$members MEMBER${members == 1 ? '' : 'S'}',
                        color: TgcgColors.primary,
                        compact: true,
                      ),

                      TgcgStatusPill(
                        label: '${unitAssignments.length} ASSIGNED',
                        color: TgcgColors.primary,
                        compact: true,
                      ),
                      TgcgStatusPill(
                        label: '$atLocation AT LOCATION',
                        color: atLocation == unitAssignments.length &&
                                unitAssignments.isNotEmpty
                            ? TgcgColors.success
                            : TgcgColors.warning,
                        compact: true,
                      ),
                      TgcgStatusPill(
                        label: _coordinateStatusLabel(unit.coordinateStatus),
                        color: _coordinateStatusColor(unit.coordinateStatus),
                        compact: true,
                      ),
                      TgcgStatusPill(
                        label: verified ? 'RESULT VERIFIED' : 'RESULT AWAITING',
                        color: verified
                            ? TgcgColors.success
                            : TgcgColors.warning,
                        compact: true,
                      ),
                    ],
                  ),
                );
              })
            else
              const TgcgEmptyState(
                icon: Icons.map_outlined,
                title: 'State overview',
                message: 'Membership and assignment activity for this area is shown above.',
              ),
          ],
        ),
      );

  Future<void> _showPollingUnitRoster(
    BuildContext context,
    CanonicalPollingUnit unit,
  ) async {
    final homeMembers = membership.membersForPollingUnit(unit.code);
    final activeAssignments = assignments
        .assignmentsForScope(unit.scope)
        .where(
          (item) =>
              !item.isTerminal && item.targetPollingUnitId == unit.code,
        )
        .toList(growable: false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 880,
            maxHeight: 760,
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
                decoration: const BoxDecoration(
                  gradient: TgcgGradients.navigation,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.how_to_vote_outlined,
                      color: TgcgColors.gold400,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            unit.displayCode,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            unit.scope.label,
                            style: const TextStyle(
                              color: TgcgColors.gold200,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TgcgStatusPill(
                          label: '${homeMembers.length} HOME MEMBERS',
                          color: TgcgColors.primary,
                          compact: true,
                        ),
                        TgcgStatusPill(
                          label: '${activeAssignments.length} ASSIGNED',
                          color: TgcgColors.info,
                          compact: true,
                        ),
                        TgcgStatusPill(
                          label:
                              '${activeAssignments.where((item) => assignments.presenceFor(item) == AssignmentPresence.insideGeofence).length} AT LOCATION',
                          color: TgcgColors.success,
                          compact: true,
                        ),
                        TgcgStatusPill(
                          label: _coordinateStatusLabel(
                            unit.coordinateStatus,
                          ),
                          color: _coordinateStatusColor(
                            unit.coordinateStatus,
                          ),
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _PollingUnitCoordinateCard(unit: unit),
                    const SizedBox(height: 16),
                    const Text(
                      'DEPLOYED MEMBERS',
                      style: TextStyle(
                        color: TgcgColors.primaryMid,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .9,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (activeAssignments.isEmpty)
                      const TgcgEmptyState(
                        icon: Icons.person_off_outlined,
                        title: 'No active deployment',
                        message:
                            'No member currently has an active assignment to this polling unit.',
                      )
                    else
                      ...activeAssignments.map((assignment) {
                        final member =
                            membership.memberById(assignment.memberId);
                        final device =
                            devices.deviceForMember(assignment.memberId);
                        final presence =
                            assignments.presenceFor(assignment);
                        final ping = assignment.lastLocation;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 9),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: TgcgColors.surfaceRaised,
                            borderRadius:
                                BorderRadius.circular(TgcgRadius.md),
                            border: Border.all(color: TgcgColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: TgcgColors.primarySoft,
                                child: Text(
                                  (member?.fullName ??
                                          assignment.memberId)
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: TgcgColors.primary,
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
                                      member?.fullName ??
                                          assignment.memberId,
                                      style: const TextStyle(
                                        color: TgcgColors.ink,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      assignment.title,
                                      style: const TextStyle(
                                        color: TgcgColors.muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                    if (ping != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'GPS ${ping.latitude.toStringAsFixed(6)}, '
                                        '${ping.longitude.toStringAsFixed(6)} • '
                                        '±${ping.accuracyMeters.toStringAsFixed(1)} m'
                                        '${ping.distanceFromTargetMeters == null ? '' : ' • ${ping.distanceFromTargetMeters!.toStringAsFixed(0)} m from PU'}',
                                        style: const TextStyle(
                                          color: TgcgColors.muted,
                                          fontSize: 9.3,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 7),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        TgcgStatusPill(
                                          label: assignment.status.name
                                              .toUpperCase(),
                                          color: presence ==
                                                  AssignmentPresence
                                                      .insideGeofence
                                              ? TgcgColors.success
                                              : TgcgColors.info,
                                          compact: true,
                                        ),
                                        TgcgStatusPill(
                                          label: _presenceLabelForRoster(
                                            presence,
                                          ),
                                          color: _presenceColorForRoster(
                                            presence,
                                          ),
                                          compact: true,
                                        ),
                                        TgcgStatusPill(
                                          label: device == null
                                              ? 'NO MANAGED PHONE'
                                              : device.id,
                                          color: device == null
                                              ? TgcgColors.warning
                                              : TgcgColors.info,
                                          icon:
                                              Icons.phone_android_outlined,
                                          compact: true,
                                        ),
                                        if (assignment.evidence.isNotEmpty)
                                          TgcgStatusPill(
                                            label:
                                                '${assignment.evidence.length} EVIDENCE',
                                            color: TgcgColors.success,
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
                        );
                      }),
                    const SizedBox(height: 16),
                    const Text(
                      'HOME MEMBERS',
                      style: TextStyle(
                        color: TgcgColors.primaryMid,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .9,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (homeMembers.isEmpty)
                      const Text(
                        'No member currently has this polling unit as their home polling unit.',
                        style: TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10.5,
                        ),
                      )
                    else
                      ...homeMembers.take(30).map(
                            (member) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.person_outline_rounded,
                                color: TgcgColors.primary,
                              ),
                              title: Text(
                                member.fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                member.membershipNumber ?? member.id,
                              ),
                            ),
                          ),
                    if (homeMembers.length > 30)
                      Text(
                        '+${homeMembers.length - 30} additional home members',
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PollingUnitCoordinateCard extends StatelessWidget {
  const _PollingUnitCoordinateCard({required this.unit});

  final CanonicalPollingUnit unit;

  @override
  Widget build(BuildContext context) {
    final latitude = unit.operationalLatitude;
    final longitude = unit.operationalLongitude;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [TgcgColors.navy50, TgcgColors.gold100],
        ),
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        border: Border.all(color: TgcgColors.gold200),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.gps_fixed_rounded,
            color: TgcgColors.accentStrong,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              latitude == null || longitude == null
                  ? 'Operational coordinate pending'
                  : '${latitude.toStringAsFixed(6)}, '
                      '${longitude.toStringAsFixed(6)}'
                      '${unit.verificationAccuracyMeters == null ? '' : ' • ±${unit.verificationAccuracyMeters!.toStringAsFixed(1)} m'}',
              style: const TextStyle(
                color: TgcgColors.ink,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${unit.geofenceRadiusMeters.toStringAsFixed(0)} m geofence',
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _presenceLabelForRoster(AssignmentPresence presence) =>
    switch (presence) {
      AssignmentPresence.unknown => 'GPS UNKNOWN',
      AssignmentPresence.liveNoGeofence => 'LIVE GPS',
      AssignmentPresence.insideGeofence => 'AT LOCATION',
      AssignmentPresence.outsideGeofence => 'OUTSIDE GEOFENCE',
      AssignmentPresence.stale => 'GPS STALE',
    };

Color _presenceColorForRoster(AssignmentPresence presence) =>
    switch (presence) {
      AssignmentPresence.unknown => TgcgColors.muted,
      AssignmentPresence.liveNoGeofence => TgcgColors.info,
      AssignmentPresence.insideGeofence => TgcgColors.success,
      AssignmentPresence.outsideGeofence => TgcgColors.warning,
      AssignmentPresence.stale => TgcgColors.warning,
    };

class _AreaRow extends StatelessWidget {
  const _AreaRow({
    required this.scope,
    required this.members,
    required this.assignments,
    required this.incidents,
    required this.results,
    required this.onTap,
  });

  final GeographicScope scope;
  final int members;
  final int assignments;
  final int incidents;
  final int results;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [TgcgColors.surface, TgcgColors.navy50],
              ),
              borderRadius: BorderRadius.circular(TgcgRadius.sm),
              border: Border.all(color: TgcgColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: TgcgColors.accent.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(TgcgRadius.sm),
                    border: Border.all(color: TgcgColors.gold200),
                  ),
                  child: Icon(
                    _scopeIcon(scope.level),
                    color: TgcgColors.accentStrong,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _shortLabel(scope),
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _levelLabel(scope.level),
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                _Count(value: members, label: 'Members'),
                const SizedBox(width: 14),
                _Count(value: assignments, label: 'Assignments'),
                const SizedBox(width: 14),
                _Count(value: incidents, label: 'Incidents'),
                const SizedBox(width: 14),
                _Count(value: results, label: 'Results'),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: TgcgColors.muted,
                ),
              ],
            ),
          ),
        ),
      );
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 8.5,
            ),
          ),
        ],
      );
}

class _RoleDeploymentPanel extends StatelessWidget {
  const _RoleDeploymentPanel({
    required this.roles,
    required this.assignments,
    required this.membership,
  });

  final List<RoleAssignmentRecord> roles;
  final List<MemberAssignment> assignments;
  final MembershipOperationsController membership;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Roles & deployment',
        subtitle:
            'Active member roles and assignments within the selected geography.',
        child: roles.isEmpty && assignments.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.assignment_ind_outlined,
                title: 'No active deployment in this scope',
                message: 'Roles and assignments will appear here when activated.',
              )
            : Column(
                children: [
                  ...roles.take(8).map((record) {
                    final member = membership.memberById(record.subjectId);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        roleIcon(record.role),
                        color: TgcgColors.primary,
                      ),
                      title: Text(
                        member?.fullName ?? record.subjectName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${roleLabel(record.role)} • ${record.scope.label}',
                      ),
                      trailing: const TgcgStatusPill(
                        label: 'ROLE ACTIVE',
                        color: TgcgColors.success,
                        compact: true,
                      ),
                    );
                  }),
                  ...assignments.take(8).map((assignment) {
                    final member = membership.memberById(assignment.memberId);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.assignment_outlined,
                        color: TgcgColors.accentStrong,
                      ),
                      title: Text(
                        member?.fullName ?? assignment.memberId,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${assignment.title} • ${assignment.targetScope.label}',
                      ),
                      trailing: TgcgStatusPill(
                        label: assignment.status.name.toUpperCase(),
                        color: TgcgColors.info,
                        compact: true,
                      ),
                    );
                  }),
                ],
              ),
      );
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({required this.path, required this.onSelect});

  final List<GeographicScope> path;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(path.length, (index) {
            final scope = path[index];
            return Row(
              children: [
                TextButton.icon(
                  onPressed: index == path.length - 1
                      ? null
                      : () => onSelect(index),
                  icon: Icon(_scopeIcon(scope.level), size: 15),
                  label: Text(_shortLabel(scope)),
                ),
                if (index < path.length - 1)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: TgcgColors.muted,
                    size: 17,
                  ),
              ],
            );
          }),
        ),
      );
}

String _coordinateStatusLabel(PollingUnitCoordinateStatus status) =>
    switch (status) {
      PollingUnitCoordinateStatus.missing => 'GPS PENDING',
      PollingUnitCoordinateStatus.referenceOnly => 'REFERENCE GPS',
      PollingUnitCoordinateStatus.fieldVerified => 'FIELD VERIFIED',
      PollingUnitCoordinateStatus.needsReview => 'GPS REVIEW',
    };

Color _coordinateStatusColor(PollingUnitCoordinateStatus status) =>
    switch (status) {
      PollingUnitCoordinateStatus.missing => TgcgColors.muted,
      PollingUnitCoordinateStatus.referenceOnly => TgcgColors.info,
      PollingUnitCoordinateStatus.fieldVerified => TgcgColors.success,
      PollingUnitCoordinateStatus.needsReview => TgcgColors.warning,
    };

String _shortLabel(GeographicScope scope) => switch (scope.level) {
      GeographyLevel.country => scope.country,
      GeographyLevel.geopoliticalZone => scope.zoneName ?? scope.label,
      GeographyLevel.state => scope.stateName ?? scope.label,
      GeographyLevel.senatorialDistrict =>
        scope.senatorialDistrictName ?? scope.label,
      GeographyLevel.lga => scope.lgaName ?? scope.label,
      GeographyLevel.ward => scope.wardName ?? scope.label,
      GeographyLevel.pollingUnit => scope.pollingUnitName ?? scope.label,
    };

String _levelLabel(GeographyLevel level) => switch (level) {
      GeographyLevel.country => 'Country',
      GeographyLevel.geopoliticalZone => 'Geopolitical zone',
      GeographyLevel.state => 'Kaduna State',
      GeographyLevel.senatorialDistrict => 'Senatorial zone',
      GeographyLevel.lga => 'Local government area',
      GeographyLevel.ward => 'Ward',
      GeographyLevel.pollingUnit => 'Polling unit',
    };

String _coverageSubtitle(GeographyLevel level, int children) => switch (level) {
      GeographyLevel.country => '$children geopolitical zones',
      GeographyLevel.geopoliticalZone => '$children states / FCT',
      GeographyLevel.state => '$children senatorial zones • 23 LGAs • 255 wards • 8,012 polling units',
      GeographyLevel.senatorialDistrict => '$children local government areas',
      GeographyLevel.lga => '$children wards',
      GeographyLevel.ward => '$children polling units',
      GeographyLevel.pollingUnit => 'Polling-unit operations',
    };

IconData _scopeIcon(GeographyLevel level) => switch (level) {
      GeographyLevel.country => Icons.flag_outlined,
      GeographyLevel.geopoliticalZone => Icons.public_outlined,
      GeographyLevel.state => Icons.map_outlined,
      GeographyLevel.senatorialDistrict => Icons.hub_outlined,
      GeographyLevel.lga => Icons.location_city_outlined,
      GeographyLevel.ward => Icons.hub_outlined,
      GeographyLevel.pollingUnit => Icons.location_on_outlined,
    };
