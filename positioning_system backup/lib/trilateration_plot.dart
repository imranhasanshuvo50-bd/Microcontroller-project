import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'robot_point.dart';

class TrilaterationPlot extends StatelessWidget {
  const TrilaterationPlot({
    super.key,
    required this.fieldSize,
    required this.anchorA,
    required this.anchorB,
    required this.distanceA,
    required this.distanceB,
    required this.plottedPositions,
  });

  /// World-space field size (same unit as distances).
  final Size fieldSize;

  /// World-space anchor positions.
  final Offset anchorA;
  final Offset anchorB;

  /// Latest plotted distances from anchors A and B.
  final double? distanceA;
  final double? distanceB;

  /// Plotted robot positions in world coordinates.
  final List<RobotPoint> plottedPositions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _TrilaterationPainter(
            fieldSize: fieldSize,
            anchorA: anchorA,
            anchorB: anchorB,
            distanceA: distanceA,
            distanceB: distanceB,
            plottedPositions: plottedPositions,
            colorScheme: Theme.of(context).colorScheme,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TrilaterationPainter extends CustomPainter {
  _TrilaterationPainter({
    required this.fieldSize,
    required this.anchorA,
    required this.anchorB,
    required this.distanceA,
    required this.distanceB,
    required this.plottedPositions,
    required this.colorScheme,
  });

  final Size fieldSize;
  final Offset anchorA;
  final Offset anchorB;
  final double? distanceA;
  final double? distanceB;
  final List<RobotPoint> plottedPositions;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colorScheme.surface);

    const padding = 18.0;
    final outer = Rect.fromLTWH(
      padding,
      padding,
      math.max(0, size.width - padding * 2),
      math.max(0, size.height - padding * 2),
    );
    if (outer.width <= 0 || outer.height <= 0) return;

    final framePaint = Paint()
      ..color = colorScheme.outlineVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (fieldSize.width <= 0 || fieldSize.height <= 0) {
      canvas.drawRect(outer, framePaint);
      _centerText(canvas, size, 'Invalid field size');
      return;
    }

    final fieldWorldRect = Rect.fromLTWH(0, 0, fieldSize.width, fieldSize.height);
    final worldBounds = _computeWorldBounds(fieldWorldRect);
    final scale = math.min(outer.width / worldBounds.width, outer.height / worldBounds.height);
    final viewPxSize = Size(worldBounds.width * scale, worldBounds.height * scale);
    final viewRect = Rect.fromLTWH(
      outer.left + (outer.width - viewPxSize.width) / 2,
      outer.top + (outer.height - viewPxSize.height) / 2,
      viewPxSize.width,
      viewPxSize.height,
    );

    Offset worldToCanvas(Offset world) {
      return Offset(
        viewRect.left + (world.dx - worldBounds.left) * scale,
        viewRect.top + (world.dy - worldBounds.top) * scale,
      );
    }

    final fieldRect = Rect.fromPoints(
      worldToCanvas(fieldWorldRect.topLeft),
      worldToCanvas(fieldWorldRect.bottomRight),
    );
    canvas.drawRect(fieldRect, framePaint);

    final a = worldToCanvas(anchorA);
    final b = worldToCanvas(anchorB);

    final anchorFillPaint = Paint()..color = Colors.red;
    final anchorBorderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const anchorSize = 14.0;

    void drawAnchor(Offset c) {
      final r = Rect.fromCenter(center: c, width: anchorSize, height: anchorSize);
      canvas.drawRect(r, anchorFillPaint);
      canvas.drawRect(r, anchorBorderPaint);
    }

    drawAnchor(a);
    drawAnchor(b);

    final baselinePaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 2;
    canvas.drawLine(a, b, baselinePaint);

    if (distanceA == null || distanceB == null) {
      if (plottedPositions.isEmpty) _centerText(canvas, size, 'Waiting for data…');
      return;
    }

    final rA = math.max(0, distanceA!) * scale;
    final rB = math.max(0, distanceB!) * scale;

    final circleAPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final circleBPaint = Paint()
      ..color = colorScheme.tertiary.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.save();
    canvas.clipRect(outer);
    canvas.drawCircle(a, rA, circleAPaint);
    canvas.drawCircle(b, rB, circleBPaint);

    final intersections = _visibleIntersections();
    final intersectionPaint = Paint()..color = const Color(0xFFFFC107);
    for (final p in intersections) {
      final o = worldToCanvas(p);
      canvas.drawCircle(o, 5, intersectionPaint);
    }

    if (plottedPositions.isNotEmpty) {
      final path = Path();
      final first = worldToCanvas(Offset(plottedPositions.first.x, plottedPositions.first.y));
      path.moveTo(first.dx, first.dy);
      for (final p in plottedPositions.skip(1)) {
        final o = worldToCanvas(Offset(p.x, p.y));
        path.lineTo(o.dx, o.dy);
      }

      final pathPaint = Paint()
        ..color = colorScheme.outline.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawPath(path, pathPaint);

      const robotRadius = 14.0;
      final lastWorld = plottedPositions.last;
      var last = worldToCanvas(Offset(lastWorld.x, lastWorld.y));
      last = Offset(
        last.dx.clamp(outer.left + robotRadius, outer.right - robotRadius),
        last.dy.clamp(outer.top + robotRadius, outer.bottom - robotRadius),
      );

      final robotFillPaint = Paint()..color = const Color(0xFF29E38B);
      final robotBorderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(last, robotRadius, robotFillPaint);
      canvas.drawCircle(last, robotRadius, robotBorderPaint);
      canvas.drawCircle(last, 3, Paint()..color = Colors.black);
    }

    canvas.restore();
  }

  Rect _computeWorldBounds(Rect fieldWorldRect) {
    final points = <Offset>[
      fieldWorldRect.topLeft,
      fieldWorldRect.topRight,
      fieldWorldRect.bottomRight,
      fieldWorldRect.bottomLeft,
      anchorA,
      anchorB,
      ...plottedPositions.map((p) => Offset(p.x, p.y)),
      ..._visibleIntersections(),
    ];

    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;

    for (final p in points.skip(1)) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }

    final rect = Rect.fromLTRB(minX, minY, maxX, maxY);
    final maxDim = math.max(rect.width, rect.height);
    final pad = maxDim <= 0 ? 1.0 : maxDim * 0.08;
    final padded = rect.inflate(pad);

    if (padded.width <= 0 || padded.height <= 0) {
      return fieldWorldRect;
    }
    return padded;
  }

  List<Offset> _visibleIntersections() {
    if (distanceA == null || distanceB == null) return const [];
    final allIntersections = circleCircleIntersections(anchorA, distanceA!, anchorB, distanceB!);
    final inFront = allIntersections.where((p) => p.dy >= 0).toList();
    return inFront.isNotEmpty ? inFront : allIntersections;
  }

  void _centerText(Canvas canvas, Size size, String text) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    textPainter.paint(
      canvas,
      Offset((size.width - textPainter.width) / 2, (size.height - textPainter.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _TrilaterationPainter oldDelegate) {
    return oldDelegate.fieldSize != fieldSize ||
        oldDelegate.anchorA != anchorA ||
        oldDelegate.anchorB != anchorB ||
        oldDelegate.distanceA != distanceA ||
        oldDelegate.distanceB != distanceB ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.plottedPositions.length != plottedPositions.length ||
        (plottedPositions.isNotEmpty &&
            (oldDelegate.plottedPositions.last.x != plottedPositions.last.x ||
                oldDelegate.plottedPositions.last.y != plottedPositions.last.y));
  }
}

/// Returns 0, 1, or 2 intersection points of two circles in world coordinates.
List<Offset> circleCircleIntersections(Offset c0, double r0, Offset c1, double r1) {
  final dx = c1.dx - c0.dx;
  final dy = c1.dy - c0.dy;
  final d = math.sqrt(dx * dx + dy * dy);

  if (d == 0) return const [];
  if (d > r0 + r1) return const [];
  if (d < (r0 - r1).abs()) return const [];

  final a = (r0 * r0 - r1 * r1 + d * d) / (2 * d);
  final h2 = r0 * r0 - a * a;
  final h = h2 <= 0 ? 0.0 : math.sqrt(h2);

  final xm = c0.dx + a * dx / d;
  final ym = c0.dy + a * dy / d;

  final rx = -dy * (h / d);
  final ry = dx * (h / d);

  final p3 = Offset(xm + rx, ym + ry);
  final p4 = Offset(xm - rx, ym - ry);

  if (h == 0) return [p3];
  return [p3, p4];
}
