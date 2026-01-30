import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'robot_point.dart';

class PositionPlot extends StatelessWidget {
  const PositionPlot({
    super.key,
    required this.points,
    required this.worldBounds,
  });

  final List<RobotPoint> points;
  final Rect worldBounds;

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
          painter: _PositionPlotPainter(
            points: points,
            worldBounds: worldBounds,
            colorScheme: Theme.of(context).colorScheme,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PositionPlotPainter extends CustomPainter {
  _PositionPlotPainter({
    required this.points,
    required this.worldBounds,
    required this.colorScheme,
  });

  final List<RobotPoint> points;
  final Rect worldBounds;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = colorScheme.surface);

    const padding = 24.0;
    final plot = Rect.fromLTWH(
      padding,
      padding,
      math.max(0, size.width - padding * 2),
      math.max(0, size.height - padding * 2),
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final framePaint = Paint()
      ..color = colorScheme.outlineVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(plot, framePaint);

    final anchorFillPaint = Paint()..color = Colors.red;
    final anchorBorderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const anchorSize = 14.0;
    final anchorCenters = <Offset>[
      plot.topLeft,
      plot.topRight,
      plot.bottomRight,
      plot.bottomLeft,
    ];
    for (final center in anchorCenters) {
      final anchorRect = Rect.fromCenter(
        center: center,
        width: anchorSize,
        height: anchorSize,
      );
      canvas.drawRect(anchorRect, anchorFillPaint);
      canvas.drawRect(anchorRect, anchorBorderPaint);
    }

    if (worldBounds.width <= 0 || worldBounds.height <= 0) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Invalid field size',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      textPainter.paint(
        canvas,
        Offset((size.width - textPainter.width) / 2, (size.height - textPainter.height) / 2),
      );
      return;
    }

    if (points.isEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Waiting for data…',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      textPainter.paint(
        canvas,
        Offset((size.width - textPainter.width) / 2, (size.height - textPainter.height) / 2),
      );
      return;
    }

    final minX = worldBounds.left;
    final maxX = worldBounds.right;
    final minY = worldBounds.top;
    final maxY = worldBounds.bottom;

    final scaleX = plot.width / (maxX - minX);
    final scaleY = plot.height / (maxY - minY);

    Offset toOffset(RobotPoint p) {
      final x = plot.left + (p.x - minX) * scaleX;
      final y = plot.bottom - (p.y - minY) * scaleY;
      return Offset(x, y);
    }

    canvas.save();
    canvas.clipRect(plot);

    final path = Path()..moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (final p in points.skip(1)) {
      final o = toOffset(p);
      path.lineTo(o.dx, o.dy);
    }

    final pathPaint = Paint()
      ..color = colorScheme.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, pathPaint);

    final pointPaint = Paint()..color = colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
    for (final p in points) {
      final o = toOffset(p);
      canvas.drawCircle(o, 2, pointPaint);
    }

    const robotRadius = 14.0;
    var last = toOffset(points.last);
    last = Offset(
      last.dx.clamp(plot.left + robotRadius, plot.right - robotRadius),
      last.dy.clamp(plot.top + robotRadius, plot.bottom - robotRadius),
    );
    final robotFillPaint = Paint()..color = const Color(0xFF29E38B);
    final robotBorderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(last, robotRadius, robotFillPaint);
    canvas.drawCircle(last, robotRadius, robotBorderPaint);
    canvas.drawCircle(last, 3, Paint()..color = Colors.black);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PositionPlotPainter oldDelegate) {
    if (oldDelegate.colorScheme != colorScheme) return true;
    if (oldDelegate.worldBounds != worldBounds) return true;
    if (oldDelegate.points.length != points.length) return true;
    if (points.isEmpty) return false;
    final oldLast = oldDelegate.points.last;
    final newLast = points.last;
    return oldLast.x != newLast.x || oldLast.y != newLast.y;
  }
}
