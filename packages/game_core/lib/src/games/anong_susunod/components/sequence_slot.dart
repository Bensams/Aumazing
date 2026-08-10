import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import '../routine_steps.dart';

/// One numbered position in the visual schedule.
///
/// The ordinal is drawn as a filled badge rather than plain text: the number is
/// the structure the child is learning, and TEACCH asks for that structure to
/// be explicit rather than implied by left-to-right position alone. Children
/// who cannot yet read numerals still get position, size, and the connector
/// arrows.
class SequenceSlot extends PositionComponent {
  SequenceSlot({
    required this.index,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor.center);

  final int index;

  /// The step seated here, or null while the slot is empty.
  RoutineStep? filled;

  /// Pre-placed by the tier (not something the child earned).
  bool preset = false;

  /// Briefly true after a wrong placement, to tint the slot.
  bool rejecting = false;

  static const Color _empty = Color(0xFFFCFBFF);
  static const Color _done = Color(0xFFD4F4E8);
  static const Color _presetFill = Color(0xFFE8DEFA);
  static const Color _reject = Color(0xFFFFE8DD);
  static const Color _lav = Color(0xFFD4C5E8);
  static const Color _primary = Color(0xFF9B82C4);
  static const Color _ink = Color(0xFF3F3B4A);

  bool containsLocal(Vector2 point) {
    final half = size / 2;
    return (point.x - position.x).abs() <= half.x &&
        (point.y - position.y).abs() <= half.y;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final radius = size.x * 0.13;
    final rr = RRect.fromRectXY(rect, radius, radius);

    final Color fill;
    if (rejecting) {
      fill = _reject;
    } else if (preset) {
      fill = _presetFill;
    } else if (filled != null) {
      fill = _done;
    } else {
      fill = _empty;
    }

    canvas.drawRRect(rr, Paint()..color = fill);

    // Empty slots are dashed, filled ones solid: the border style alone tells
    // the child what is left to do, without relying on the fill colour.
    if (filled == null) {
      _drawDashed(canvas, rr);
    } else {
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _primary,
      );
    }

    if (filled != null) {
      final art = size.x * 0.6;
      RoutineArtPainter.paint(
        canvas,
        filled!.art,
        Offset((size.x - art) / 2, (size.y - art) / 2 + size.y * 0.06),
        art,
      );
    }

    _drawBadge(canvas);
  }

  void _drawBadge(Canvas canvas) {
    final r = size.x * 0.13;
    final centre = Offset(size.x / 2, r + 4);
    canvas.drawCircle(centre, r, Paint()..color = _primary);

    final tp = TextPainter(
      text: TextSpan(
        text: '${index + 1}',
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: r * 1.25,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawDashed(Canvas canvas, RRect rr) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = _lav;

    final path = Path()..addRRect(rr);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + 9).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += 16;
      }
    }
  }

  /// The connector arrow drawn to the right of this slot.
  static void drawArrow(Canvas canvas, Offset from, double height) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _primary;

    final h = height * 0.22;
    canvas.drawPath(
      Path()
        ..moveTo(from.dx - h * 0.4, from.dy - h * 0.5)
        ..lineTo(from.dx + h * 0.35, from.dy)
        ..lineTo(from.dx - h * 0.4, from.dy + h * 0.5),
      paint,
    );
  }

  static Color get inkColor => _ink;
}
