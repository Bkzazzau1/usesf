import 'dart:async';

import 'package:flutter/material.dart';

import '../geography/geography_registry.dart';
import '../geography/kaduna_map.dart';
import '../membership/membership_store.dart';
import '../ui/tgcg_design.dart';
import 'assignment_store.dart';

/// Kaduna map for Assignment Control: LGAs are coloured by polling-unit
/// staffing readiness, and every open assignment is plotted live: members
/// at their latest GPS fix (coloured by geofence presence), and members
/// without a fix yet as a hollow pin at their target polling unit.
///
/// Markers move as soon as new GPS heartbeats reach [controller]; staleness is
/// also re-evaluated on a timer so a silent phone turns grey without new data.
class LiveDeploymentMap extends StatefulWidget {
  const LiveDeploymentMap({
    super.key,
    required this.assignments,
    required this.controller,
    required this.membership,
    required this.snapshots,
    required this.authorizedUnits,
  });

  final List<MemberAssignment> assignments;
  final AssignmentController controller;
  final MembershipOperationsController membership;
  final List<PollingUnitCoverageSnapshot> snapshots;
  final List<CanonicalPollingUnit> authorizedUnits;

  @override
  State<LiveDeploymentMap> createState() => _LiveDeploymentMapState();
}

class _LiveDeploymentMapState extends State<LiveDeploymentMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Re-evaluate GPS staleness even when no new location arrives.
    _clock = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.assignments
        .where((item) => !item.isTerminal)
        .toList(growable: false);
    final markers = <_DeploymentMarker>[];
    var awaitingGps = 0;
    DateTime? latestPing;

    for (final assignment in open) {
      final member = widget.membership.memberById(assignment.memberId);
      final name = member?.fullName ?? assignment.memberId;
      final ping = assignment.lastLocation;
      if (ping != null) {
        final presence = widget.controller.presenceFor(assignment);
        markers.add(
          _DeploymentMarker(
            longitude: ping.longitude,
            latitude: ping.latitude,
            kind: switch (presence) {
              AssignmentPresence.insideGeofence => _MarkerKind.inside,
              AssignmentPresence.outsideGeofence => _MarkerKind.outside,
              AssignmentPresence.liveNoGeofence => _MarkerKind.flexible,
              AssignmentPresence.stale ||
              AssignmentPresence.unknown => _MarkerKind.stale,
            },
            tooltip:
                '$name • ${assignment.title}\n${_presenceLabel(presence)} • last seen ${_time(ping.capturedAt)}',
          ),
        );
        if (latestPing == null || ping.capturedAt.isAfter(latestPing)) {
          latestPing = ping.capturedAt;
        }
        continue;
      }
      awaitingGps++;
      final unitId = assignment.targetPollingUnitId;
      final unit = unitId == null
          ? null
          : widget.membership.geography.pollingUnit(unitId);
      final lat = unit?.operationalLatitude;
      final lon = unit?.operationalLongitude;
      if (lat != null && lon != null) {
        markers.add(
          _DeploymentMarker(
            longitude: lon,
            latitude: lat,
            kind: _MarkerKind.target,
            tooltip:
                '$name • ${assignment.title}\nAwaiting first GPS • target ${unit!.displayCode}',
          ),
        );
      }
    }

    final live = markers
        .where((item) => item.kind != _MarkerKind.target)
        .length;

    return TgcgSectionCard(
      title: 'Live Deployment Map',
      subtitle:
          'Staffing readiness by LGA, with members plotted at their latest GPS position as their phones report in.',
      trailing: _LivePill(
        pulse: _pulse,
        label: latestPing == null
            ? 'LIVE • waiting for GPS'
            : 'LIVE • last fix ${_time(latestPing)}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CountChip(
                icon: Icons.gps_fixed_rounded,
                label: '$live on map',
                color: TgcgColors.success,
              ),
              _CountChip(
                icon: Icons.gps_not_fixed_rounded,
                label: '$awaitingGps awaiting first GPS',
                color: TgcgColors.muted,
              ),
              _CountChip(
                icon: Icons.assignment_turned_in_outlined,
                label: '${open.length} open assignments',
                color: TgcgColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 600),
            child: Center(
              child: AspectRatio(
                aspectRatio: kadunaMapAspectRatio,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final size = box.biggest;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: KadunaMap(
                            fillColor: _readinessFill,
                            badge: _readinessBadge,
                          ),
                        ),
                        for (final marker in markers) _positioned(marker, size),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _Legend.dot(TgcgColors.success, 'Inside geofence'),
              _Legend.dot(TgcgColors.warning, 'Outside geofence'),
              _Legend.dot(TgcgColors.info, 'Live, no geofence to check'),
              _Legend.dot(Color(0xFF98A2B3), 'Stale GPS (over 7 min)'),
              _Legend.ring(TgcgColors.primary, 'Target, awaiting GPS'),
              _Legend.area(TgcgColors.success, 'LGA ready'),
              _Legend.area(TgcgColors.warning, 'Staffing gap'),
              _Legend.area(TgcgColors.danger, 'Critical / GPS alert'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _positioned(_DeploymentMarker marker, Size size) {
    final point = kadunaMapProject(marker.longitude, marker.latitude, size);
    if (point.dx < 0 ||
        point.dy < 0 ||
        point.dx > size.width ||
        point.dy > size.height) {
      return const SizedBox.shrink();
    }
    const extent = 30.0;
    return Positioned(
      left: point.dx - extent / 2,
      top: point.dy - extent / 2,
      width: extent,
      height: extent,
      child: Tooltip(
        message: marker.tooltip,
        child: _MarkerDot(kind: marker.kind, pulse: _pulse),
      ),
    );
  }

  // --- LGA readiness colouring ---------------------------------------------

  Set<String> get _authorizedLgas => widget.authorizedUnits
      .map((unit) => unit.scope.lgaId)
      .whereType<String>()
      .toSet();

  Map<String, List<PollingUnitCoverageSnapshot>> get _byLga {
    final byLga = <String, List<PollingUnitCoverageSnapshot>>{};
    for (final snapshot in widget.snapshots) {
      final lgaId = snapshot.unit.scope.lgaId;
      if (lgaId != null) byLga.putIfAbsent(lgaId, () => []).add(snapshot);
    }
    return byLga;
  }

  Color _readinessFill(String lgaId) {
    if (!_authorizedLgas.contains(lgaId)) return TgcgColors.navy100;
    final items = _byLga[lgaId] ?? const <PollingUnitCoverageSnapshot>[];
    if (items.isEmpty) return TgcgColors.navy700;
    if (items.any((item) => item.isUnstaffed || item.hasGpsAlert)) {
      return TgcgColors.danger;
    }
    if (items.any((item) => item.needsAttention)) return TgcgColors.warning;
    return TgcgColors.success;
  }

  String? _readinessBadge(String lgaId) {
    final items = _byLga[lgaId];
    if (items == null || items.isEmpty) return null;
    final present = items.fold<int>(
      0,
      (total, item) => total + item.atLocation,
    );
    final required = items.fold<int>(
      0,
      (total, item) => total + item.minimumStaffing,
    );
    return '$present/$required present';
  }
}

enum _MarkerKind { inside, outside, flexible, stale, target }

class _DeploymentMarker {
  const _DeploymentMarker({
    required this.longitude,
    required this.latitude,
    required this.kind,
    required this.tooltip,
  });

  final double longitude;
  final double latitude;
  final _MarkerKind kind;
  final String tooltip;
}

class _MarkerDot extends StatelessWidget {
  const _MarkerDot({required this.kind, required this.pulse});

  final _MarkerKind kind;
  final Animation<double> pulse;

  Color get _color => switch (kind) {
    _MarkerKind.inside => TgcgColors.success,
    _MarkerKind.outside => TgcgColors.warning,
    _MarkerKind.flexible => TgcgColors.info,
    _MarkerKind.stale => const Color(0xFF98A2B3),
    _MarkerKind.target => TgcgColors.primary,
  };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final core = kind == _MarkerKind.target
        ? Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
            ),
          )
        : Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: .45), blurRadius: 6),
              ],
            ),
          );
    // Only fresh positions pulse; stale and pending markers stay still.
    if (kind == _MarkerKind.stale || kind == _MarkerKind.target) {
      return Center(child: core);
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 14 + 16 * pulse.value,
            height: 14 + 16 * pulse.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: .35 * (1 - pulse.value)),
            ),
          ),
          child!,
        ],
      ),
      child: core,
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.pulse, required this.label});

  final Animation<double> pulse;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: TgcgColors.success.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(TgcgRadius.sm),
      border: Border.all(color: TgcgColors.success.withValues(alpha: .3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween<double>(begin: 1, end: .25).animate(pulse),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: TgcgColors.success,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: TgcgColors.success,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: .3,
          ),
        ),
      ],
    ),
  );
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: TgcgColors.surfaceSoft,
      borderRadius: BorderRadius.circular(TgcgRadius.sm),
      border: Border.all(color: TgcgColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: TgcgColors.ink,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend.dot(this.color, this.label) : shape = _LegendShape.dot;
  const _Legend.ring(this.color, this.label) : shape = _LegendShape.ring;
  const _Legend.area(this.color, this.label) : shape = _LegendShape.area;

  final Color color;
  final String label;
  final _LegendShape shape;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: shape == _LegendShape.ring ? Colors.white : color,
          shape: shape == _LegendShape.area
              ? BoxShape.rectangle
              : BoxShape.circle,
          borderRadius: shape == _LegendShape.area
              ? BorderRadius.circular(3)
              : null,
          border: shape == _LegendShape.ring
              ? Border.all(color: color, width: 2.5)
              : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          color: TgcgColors.muted,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

enum _LegendShape { dot, ring, area }

String _presenceLabel(AssignmentPresence presence) => switch (presence) {
  AssignmentPresence.insideGeofence => 'Inside geofence',
  AssignmentPresence.outsideGeofence => 'Outside geofence',
  AssignmentPresence.stale => 'GPS stale',
  AssignmentPresence.liveNoGeofence => 'Live, no geofence',
  AssignmentPresence.unknown => 'Location unknown',
};


String _time(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
