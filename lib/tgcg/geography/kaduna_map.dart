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

/// Accurate map of Kaduna State's 23 LGAs, coloured by senatorial zone.
/// Boundaries: GRID3 via geoBoundaries (CC BY 4.0).
class KadunaMap extends StatelessWidget {
  const KadunaMap({super.key, this.showLabels = true});

  final bool showLabels;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: _KadunaProjection.instance.aspectRatio,
        child: CustomPaint(
          painter: _KadunaMapPainter(showLabels: showLabels),
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
}

class _KadunaMapPainter extends CustomPainter {
  const _KadunaMapPainter({required this.showLabels});

  final bool showLabels;

  // The two Kaduna city LGAs are too small to hold a name, so their labels sit
  // outside with a leader line (offsets in degrees).
  static const _labelOffsets = <String, Offset>{
    'KD-KADUNA-NORTH': Offset(-.42, .07),
    'KD-KADUNA-SOUTH': Offset(-.42, -.09),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final projection = _KadunaProjection.instance;
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, size.width / 450)
      ..strokeJoin = StrokeJoin.round;

    final paths = <String, Path>{};
    for (final shape in kadunaLgaShapes) {
      final path = Path();
      for (final ring in shape.rings) {
        for (var i = 0; i < ring.length; i += 2) {
          final point = projection.project(ring[i], ring[i + 1], size);
          i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
        }
        path.close();
      }
      paths[shape.lgaId] = path;
      final color = kadunaZoneColors[kadunaLgaDistrict[shape.lgaId]] ?? Colors.grey;
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(path, border);
    }

    if (!showLabels) return;
    for (final shape in kadunaLgaShapes) {
      final district = kadunaLgaDistrict[shape.lgaId];
      final onYellow = district == 'SD/054/KD';
      final bounds = paths[shape.lgaId]!.getBounds();
      final offset = _labelOffsets[shape.lgaId];
      final anchor = projection.project(shape.labelLon, shape.labelLat, size);
      final at = offset == null
          ? anchor
          : projection.project(shape.labelLon + offset.dx, shape.labelLat + offset.dy, size);
      final fontSize = offset != null
          ? size.width / 58
          : (math.sqrt(bounds.width * bounds.height) / 7.5)
              .clamp(size.width / 80, size.width / 38);

      if (offset != null) {
        canvas.drawLine(
          anchor,
          at,
          Paint()
            ..color = const Color(0xFF101828)
            ..strokeWidth = math.max(1, size.width / 600),
        );
        canvas.drawCircle(anchor, size.width / 260, Paint()..color = const Color(0xFF101828));
      }

      final text = TextPainter(
        text: TextSpan(
          text: shape.name,
          style: TextStyle(
            color: offset != null || onYellow ? const Color(0xFF101828) : Colors.white,
            fontFamily: 'Roboto',
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
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
  bool shouldRepaint(covariant _KadunaMapPainter oldDelegate) =>
      oldDelegate.showLabels != showLabels;
}
