import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/tgcg_design.dart';
import '../geography/geography_registry.dart';
import 'membership_store.dart';

class StateMembershipPage extends StatefulWidget {
  const StateMembershipPage({super.key});

  @override
  State<StateMembershipPage> createState() =>
      _StateMembershipPageState();
}

class _StateMembershipPageState extends State<StateMembershipPage> {
  String? selectedZoneId;
  String? selectedLgaId;
  String query = '';

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = MembershipOperations.of(context);
    final geography = store.geography;

    final verifiedMembers = store.members
        .where((item) => item.status == RecordStatus.verified)
        .length;
    final approvedAgents = store.agents
        .where((item) => item.status == AccreditationStatus.approved)
        .length;
    final lgasWithMembers = geography.lgas
        .where((item) => store.memberCountForScope(item.scope) > 0)
        .length;
    final zonesWithMembers = geography.senatorialDistricts
        .where((item) => store.memberCountForScope(item.scope) > 0)
        .length;

    final lgaRows = geography.lgas.where((lga) {
      if (selectedZoneId != null && lga.senatorialDistrictId != selectedZoneId) return false;
      final needle = query.trim().toLowerCase();
      return needle.isEmpty ||
          lga.name.toLowerCase().contains(needle) ||
          lga.senatorialDistrictName.toLowerCase().contains(needle);
    }).toList(growable: false);

    final selectedLga = selectedLgaId == null
        ? null
        : geography.lgas
            .where((item) => item.id == selectedLgaId)
            .firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'KADUNA STATE MEMBERSHIP NETWORK',
          title: 'Registered Members',
          subtitle:
              '${session.scope.label}: membership registration, senatorial zone coverage, LGA membership and accredited-agent visibility.',
          trailing: const TgcgStatusPill(
            label: 'STATE-WIDE',
            color: TgcgColors.primary,
            icon: Icons.location_city_rounded,
          ),
        ),
        const SizedBox(height: 18),
        _SummaryMetrics(
          members: store.members.length,
          verifiedMembers: verifiedMembers,
          agents: store.agents.length,
          approvedAgents: approvedAgents,
          zones: zonesWithMembers,
          lgas: lgasWithMembers,
        ),
        const SizedBox(height: 16),
        _ZoneCoverage(
          store: store,
          selectedZoneId: selectedZoneId,
          onSelect: (zoneId) => setState(() {
            selectedZoneId = selectedZoneId == zoneId ? null : zoneId;
            selectedLgaId = null;
          }),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final lgaDirectory = _LgaDirectory(
              store: store,
              lgas: lgaRows,
              query: query,
              selectedLgaId: selectedLgaId,
              onQueryChanged: (value) => setState(() => query = value),
              onSelect: (stateId) =>
                  setState(() => selectedLgaId = stateId),
              onClearZone: selectedZoneId == null
                  ? null
                  : () => setState(() {
                        selectedZoneId = null;
                        selectedLgaId = null;
                      }),
            );
            final inspector = _LgaInspector(
              store: store,
              lga: selectedLga,
            );

            if (constraints.maxWidth < 1040) {
              return Column(
                children: [
                  lgaDirectory,
                  const SizedBox(height: 16),
                  inspector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: lgaDirectory),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: inspector),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SummaryMetrics extends StatelessWidget {
  const _SummaryMetrics({
    required this.members,
    required this.verifiedMembers,
    required this.agents,
    required this.approvedAgents,
    required this.zones,
    required this.lgas,
  });

  final int members;
  final int verifiedMembers;
  final int agents;
  final int approvedAgents;
  final int zones;
  final int lgas;

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
                label: 'Registered members',
                value: '$members',
                detail: '$verifiedMembers verified identities',
                icon: Icons.groups_rounded,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Accredited agents',
                value: '$agents',
                detail: '$approvedAgents approved',
                icon: Icons.badge_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Senatorial zones active',
                value: '$zones / 3',
                detail: 'Zones with registered members',
                icon: Icons.hub_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'LGAs active',
                value: '$lgas / 23',
                detail: 'LGAs with registrations',
                icon: Icons.map_outlined,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Member to agent',
                value: members == 0
                    ? '0%'
                    : '${((agents / members) * 100).round()}%',
                detail: 'Members with agent accreditation',
                icon: Icons.how_to_reg_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Approval rate',
                value: agents == 0
                    ? '0%'
                    : '${((approvedAgents / agents) * 100).round()}%',
                detail: 'Approved agent records',
                icon: Icons.verified_user_outlined,
                tone: TgcgMetricTone.success,
              ),
            ],
          );
        },
      );
}

class _ZoneCoverage extends StatelessWidget {
  const _ZoneCoverage({
    required this.store,
    required this.selectedZoneId,
    required this.onSelect,
  });

  final MembershipOperationsController store;
  final String? selectedZoneId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Senatorial zones',
        subtitle: 'Select a senatorial zone to filter the LGA directory.',
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
              children: store.geography.senatorialDistricts.map((zone) {
                final members = store.membersForScope(zone.scope).length;
                final agents = store.agentsForScope(zone.scope).length;
                final active = selectedZoneId == zone.id;
                return SizedBox(
                  width: width,
                  child: InkWell(
                    onTap: () => onSelect(zone.id),
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: active
                            ? TgcgColors.primarySoft
                            : TgcgColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: active
                              ? TgcgColors.primary
                              : TgcgColors.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.hub_rounded,
                                size: 17,
                                color: TgcgColors.primary,
                              ),
                              const Spacer(),
                              Text(
                                '${zone.lgaSlugs.length} LGAs',
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Text(
                            zone.name,
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            '$members members',
                            style: const TextStyle(
                              color: TgcgColors.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '$agents agents',
                            style: const TextStyle(
                              color: TgcgColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      );
}

class _LgaDirectory extends StatelessWidget {
  const _LgaDirectory({
    required this.store,
    required this.lgas,
    required this.query,
    required this.selectedLgaId,
    required this.onQueryChanged,
    required this.onSelect,
    required this.onClearZone,
  });

  final MembershipOperationsController store;
  final List<CanonicalLga> lgas;
  final String query;
  final String? selectedLgaId;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSelect;
  final VoidCallback? onClearZone;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'LGA membership directory',
        subtitle: 'Registered-member and agent coverage across all 23 LGAs of Kaduna State.',
        trailing: onClearZone == null
            ? null
            : TextButton.icon(
                onPressed: onClearZone,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                label: const Text('All LGAs'),
              ),
        child: Column(
          children: [
            TextField(
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                hintText: 'Search LGA or senatorial zone',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            ...lgas.map((lga) {
              final members = store.membersForScope(lga.scope);
              final agents = store.agentsForScope(lga.scope);
              final approved = agents
                  .where((item) =>
                      item.status == AccreditationStatus.approved)
                  .length;
              final selected = selectedLgaId == lga.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => onSelect(lga.id),
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected
                          ? TgcgColors.primarySoft
                          : TgcgColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: selected
                            ? TgcgColors.primary
                            : TgcgColors.border,
                      ),
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
                          child: const Icon(
                            Icons.location_city_outlined,
                            color: TgcgColors.primary,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lga.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: TgcgColors.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                lga.senatorialDistrictName,
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _Count(label: 'Members', value: members.length),
                        const SizedBox(width: 16),
                        _Count(label: 'Agents', value: agents.length),
                        const SizedBox(width: 16),
                        _Count(label: 'Approved', value: approved),
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: TgcgColors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      );
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 13,
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

class _LgaInspector extends StatelessWidget {
  const _LgaInspector({required this.store, required this.lga});

  final MembershipOperationsController store;
  final CanonicalLga? lga;

  @override
  Widget build(BuildContext context) {
    final lga = this.lga;
    if (lga == null) {
      return const TgcgSectionCard(
        title: 'LGA details',
        subtitle: 'Select an LGA to inspect its membership and agents.',
        child: TgcgEmptyState(
          icon: Icons.map_outlined,
          title: 'Select an LGA',
          message: 'Member identities and agent assignments will appear here.',
        ),
      );
    }

    final members = store.membersForScope(lga.scope);
    final agents = store.agentsForScope(lga.scope);
    return Column(
      children: [
        TgcgSectionCard(
          title: '${lga.name} LGA',
          subtitle: lga.senatorialDistrictName,
          trailing: TgcgStatusPill(
            label: '${members.length} MEMBERS',
            color: TgcgColors.primary,
            icon: Icons.groups_outlined,
            compact: true,
          ),
          child: Row(
            children: [
              Expanded(
                child: _InspectorMetric(
                  label: 'Members',
                  value: '${members.length}',
                  icon: Icons.groups_rounded,
                ),
              ),
              Expanded(
                child: _InspectorMetric(
                  label: 'Agents',
                  value: '${agents.length}',
                  icon: Icons.badge_outlined,
                ),
              ),
              Expanded(
                child: _InspectorMetric(
                  label: 'Approved',
                  value:
                      '${agents.where((a) => a.status == AccreditationStatus.approved).length}',
                  icon: Icons.verified_user_outlined,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TgcgSectionCard(
          title: 'Registered members',
          subtitle: 'Members enrolled in this LGA.',
          child: members.isEmpty
              ? const TgcgEmptyState(
                  icon: Icons.person_search_outlined,
                  title: 'No members yet',
                  message: 'LGA registrations will appear here.',
                )
              : Column(
                  children: members
                      .map(
                        (member) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            child: Text(member.fullName[0].toUpperCase()),
                          ),
                          title: Text(
                            member.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${member.membershipNumber ?? member.id} • ${member.phoneNumber}',
                          ),
                          trailing: TgcgStatusPill(
                            label: member.status.name.toUpperCase(),
                            color: member.status == RecordStatus.verified
                                ? TgcgColors.success
                                : TgcgColors.info,
                            compact: true,
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 14),
        TgcgSectionCard(
          title: 'LGA agents',
          subtitle: 'Agent assignments currently visible in this LGA.',
          child: agents.isEmpty
              ? const TgcgEmptyState(
                  icon: Icons.badge_outlined,
                  title: 'No agents yet',
                  message: 'Agent assignments will appear here.',
                )
              : Column(
                  children: agents.map((agent) {
                    final member = store.memberById(agent.memberId);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        child: Icon(Icons.badge_outlined),
                      ),
                      title: Text(
                        member?.fullName ?? agent.agentId,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${agent.agentId} • ${roleLabel(agent.role)}\n${agent.scope.label}',
                      ),
                      isThreeLine: true,
                      trailing: TgcgStatusPill(
                        label: agent.status.name.toUpperCase(),
                        color: agent.status == AccreditationStatus.approved
                            ? TgcgColors.success
                            : TgcgColors.warning,
                        compact: true,
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _InspectorMetric extends StatelessWidget {
  const _InspectorMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon, color: TgcgColors.primary, size: 19),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 19,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 9.5,
            ),
          ),
        ],
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
