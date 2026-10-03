import 'package:flutter/material.dart';

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
    final member = membership.memberById(session.accessId);

    if (member == null) {
      return Scaffold(
        backgroundColor: TgcgColors.canvas,
        appBar: AppBar(
          title: const Text('Member Access'),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              onPressed: session.signOut,
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
            onPressed: session.signOut,
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
          const TgcgSectionCard(
            title: 'Assignment centre',
            subtitle:
                'Personal operational assignments will appear here when issued by an authorized coordinator.',
            child: TgcgEmptyState(
              icon: Icons.assignment_outlined,
              title: 'No active assignment',
              message:
                  'The assignment engine will keep your home polling unit separate from any temporary duty location.',
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
                            : 'Home polling unit coordinate is available for future assignment geofencing.',
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
