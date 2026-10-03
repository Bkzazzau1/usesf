import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'kaduna_geography.dart';
import 'kaduna_lga_shapes.dart';

/// Senatorial zone colours used on the Kaduna map.
const kadunaZoneColors = <String, Color>{
  'SD/052/KD': Color(0xFF1E9E5A), // Kaduna North
  'SD/053/KD': Color(0xFF1F5FD1), // Kaduna Central
  'SD/054/KD': Color(0xFFF2C230), // Kaduna South
};

/// LGA id (e.g. `KD-ZARIA`) to senatorial district code.
final Map<String, String> kadunaLgaDistrict = {
  for (final district in kadunaSenatorialDistricts)
    for (final slug in district.lgaSlugs)
      'KD-${slug.toUpperCase().replaceAll("'", '')}': district.code,
};

const _ink = Color(0xFF101828);
const _gold = Color(0xFFD8AD42);

/// Accurate map of Kaduna State's 23 LGAs. By default LGAs are coloured by
/// senatorial zone; pass [fillColor] to colour them by anything else (for
/// example live situation), [badge] for a small per-LGA tag, and [onLgaTap]
/// to make LGAs selectable. Boundaries: GRID3 via geoBoundaries (CC BY 4.0).
class KadunaMap extends StatefulWidget {
  const KadunaMap({
    super.key,
    this.showLabels = true,
    this.fillColor,
    this.labelColor,
    this.badge,
    this.selectedLgaId,
    this.onLgaTap,
  });

  final bool showLabels;
  final Color Function(String lgaId)? fillColor;
  final Color Function(String lgaId)? labelColor;
  final String? Function(String lgaId)? badge;
  final String? selectedLgaId;
  final ValueChanged<String>? onLgaTap;

  @override
  State<KadunaMap> createState() => _KadunaMapState();
}

class _KadunaMapState extends State<KadunaMap> {
  Size? _pathsSize;
  Map<String, Path> _paths = const {};
  String? _hovered;

  Map<String, Path> _pathsFor(Size size) {
    if (_pathsSize != size) {
      _paths = _KadunaProjection.instance.paths(size);
      _pathsSize = size;
    }
    return _paths;
  }

  String? _hit(Offset position, Size size) {
    for (final entry in _pathsFor(size).entries) {
      if (entry.value.contains(position)) return entry.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: _KadunaProjection.instance.aspectRatio,
    child: LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final paint = CustomPaint(
          size: size,
          painter: _KadunaMapPainter(
            paths: _pathsFor(size),
            showLabels: widget.showLabels,
            fillColor: widget.fillColor,
            labelColor: widget.labelColor,
            badge: widget.badge,
            selectedLgaId: widget.selectedLgaId,
            hoveredLgaId: widget.onLgaTap == null ? null : _hovered,
          ),
        );
        if (widget.onLgaTap == null) return paint;
        return MouseRegion(
          cursor: _hovered == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          onHover: (event) {
            final hit = _hit(event.localPosition, size);
            if (hit != _hovered) setState(() => _hovered = hit);
          },
          onExit: (_) => setState(() => _hovered = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final hit = _hit(details.localPosition, size);
              if (hit != null) widget.onLgaTap!(hit);
            },
            child: paint,
          ),
        );
      },
    ),
  );
}

class _KadunaProjection {
  _KadunaProjection._() {
    for (final shape in kadunaLgaShapes) {
      for (final ring in shape.rings) {
        for (var i = 0; i < ring.length; i += 2) {
          minLon = math.min(minLon, ring[i]);
          maxLon = math.max(maxLon, ring[i]);
          minLat = math.min(minLat, ring[i + 1]);
          maxLat = math.max(maxLat, ring[i + 1]);
        }
      }
    }
    lonScale = math.cos((minLat + maxLat) / 2 * math.pi / 180);
  }

  static final instance = _KadunaProjection._();

  double minLon = double.infinity, maxLon = -double.infinity;
  double minLat = double.infinity, maxLat = -double.infinity;
  late final double lonScale;

  double get aspectRatio => (maxLon - minLon) * lonScale / (maxLat - minLat);

  Offset project(double lon, double lat, Size size) {
    final scale = size.width / ((maxLon - minLon) * lonScale);
    return Offset((lon - minLon) * lonScale * scale, (maxLat - lat) * scale);
  }

  Map<String, Path> paths(Size size) {
    final result = <String, Path>{};
    for (final shape in kadunaLgaShapes) {
      final path = Path();
      for (final ring in shape.rings) {
        for (var i = 0; i < ring.length; i += 2) {
          final point = project(ring[i], ring[i + 1], size);
          i == 0
              ? path.moveTo(point.dx, point.dy)
              : path.lineTo(point.dx, point.dy);
        }
        path.close();
      }
      result[shape.lgaId] = path;
    }
    return result;
  }
}

class _KadunaMapPainter extends CustomPainter {
  const _KadunaMapPainter({
    required this.paths,
    required this.showLabels,
    required this.fillColor,
    required this.labelColor,
    required this.badge,
    required this.selectedLgaId,
    required this.hoveredLgaId,
  });

  final Map<String, Path> paths;
  final bool showLabels;
  final Color Function(String lgaId)? fillColor;
  final Color Function(String lgaId)? labelColor;
  final String? Function(String lgaId)? badge;
  final String? selectedLgaId;
  final String? hoveredLgaId;

  // The two Kaduna city LGAs are too small to hold a name, so their labels sit
  // outside with a leader line (offsets in degrees).
  static const _labelOffsets = <String, Offset>{
    'KD-KADUNA-NORTH': Offset(-.42, .07),
    'KD-KADUNA-SOUTH': Offset(-.42, -.09),
  };

  Color _fill(String lgaId) =>
      fillColor?.call(lgaId) ??
      kadunaZoneColors[kadunaLgaDistrict[lgaId]] ??
      Colors.grey;

  Color _label(String lgaId) {
    final custom = labelColor?.call(lgaId);
    if (custom != null) return custom;
    return _fill(lgaId).computeLuminance() > .45 ? _ink : Colors.white;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final projection = _KadunaProjection.instance;
    final strokeWidth = math.max(1.0, size.width / 450);
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round;

    for (final shape in kadunaLgaShapes) {
      final path = paths[shape.lgaId]!;
      var color = _fill(shape.lgaId);
      if (shape.lgaId == hoveredLgaId) {
        color = Color.lerp(color, Colors.white, .18)!;
      }
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(path, border);
    }
    final selected = selectedLgaId == null ? null : paths[selectedLgaId];
    if (selected != null) {
      canvas.drawPath(
        selected,
        Paint()
          ..color = _gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 3.2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    if (!showLabels) return;
    for (final shape in kadunaLgaShapes) {
      final bounds = paths[shape.lgaId]!.getBounds();
      final offset = _labelOffsets[shape.lgaId];
      final anchor = projection.project(shape.labelLon, shape.labelLat, size);
      final at = offset == null
          ? anchor
          : projection.project(
              shape.labelLon + offset.dx,
              shape.labelLat + offset.dy,
              size,
            );
      final fontSize = offset != null
          ? size.width / 58
          : (math.sqrt(bounds.width * bounds.height) / 7.5).clamp(
              size.width / 80,
              size.width / 38,
            );
      final tag = badge?.call(shape.lgaId);

      if (offset != null) {
        canvas.drawLine(
          anchor,
          at,
          Paint()
            ..color = _ink
            ..strokeWidth = math.max(1, size.width / 600),
        );
        canvas.drawCircle(anchor, size.width / 260, Paint()..color = _ink);
      }

      final text =
          TextPainter(
            text: TextSpan(
              text: shape.name,
              style: TextStyle(
                fontFamily: 'Roboto',
                color: offset != null ? _ink : _label(shape.lgaId),
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
              children: [
                if (tag != null)
                  TextSpan(
                    text: '\n$tag',
                    style: TextStyle(
                      fontSize: fontSize * .62,
                      letterSpacing: .4,
                    ),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
          )..layout(
            maxWidth: offset != null
                ? fontSize * 7
                : math.max(bounds.width * .8, fontSize * 3.2),
          );
      final topLeft = offset == null
          ? at - Offset(text.width / 2, text.height / 2)
          : at - Offset(text.width + fontSize * .3, text.height / 2);
      if (offset != null) {
        final pad = fontSize * .35;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            (topLeft & text.size).inflate(pad),
            Radius.circular(pad),
          ),
          Paint()..color = Colors.white.withValues(alpha: .92),
        );
      }
      text.paint(canvas, topLeft);
    }
  }

  @override
  bool shouldRepaint(covariant _KadunaMapPainter oldDelegate) => true;
}

/// Width-to-height ratio of [KadunaMap], for laying out overlays on it.
double get kadunaMapAspectRatio => _KadunaProjection.instance.aspectRatio;

/// Where [KadunaMap] draws the given LGA's name, in a map of [size]: the
/// LGA's interior label point, or the leader-line label for the small city
/// LGAs. Useful for pinning overlays to an LGA.
Offset? kadunaLgaLabelPosition(String lgaId, Size size) {
  for (final shape in kadunaLgaShapes) {
    if (shape.lgaId != lgaId) continue;
    final offset = _KadunaMapPainter._labelOffsets[lgaId] ?? Offset.zero;
    return _KadunaProjection.instance.project(
      shape.labelLon + offset.dx,
      shape.labelLat + offset.dy,
      size,
    );
  }
  return null;
}
