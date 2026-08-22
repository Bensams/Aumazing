import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart';

import '../../shared/shape_painter_3d.dart';
import 'sequence_shape.dart';

/// One placeholder square in the Copy Me *pattern row* (the top strip).
///
/// A slot is either empty — a dashed grey outline, the "put something here"
/// affordance a child recognises — or [filled] with one of the four shapes.
/// The game fills the slots left-to-right while demonstrating the pattern, then
/// clears them so the child can copy it back into the same row by tapping or
/// dragging the palette cards below.
class PatternSlot extends PositionComponent {
  PatternSlot({
    required this.index,
    super.position,
    super.size,
  });

  final int index;

  /// The shape currently seated here, or null while the slot is empty.
  CopyMeShapeType? filledType;
  Color? filledColor;

  bool get isFilled => filledType != null;

  static const double _cornerRadius = 24.0;

  // Empty-slot look: a soft grey fill under a dashed grey outline, matching the
  // greyed placeholder squares in the design. Deliberately neutral so the only
  // colour in the pattern row is the pattern itself.
  static const Color _emptyFill = Color(0xFFE4E4E4);
  static const Color _emptyBorder = Color(0xFFB5B5B5);

  /// Seat [type]/[color] here with a small pop, as if the shape dropped in.
  void fill(CopyMeShapeType type, Color color) {
    filledType = type;
    filledColor = color;
    scale = Vector2.all(1.0);
    add(ScaleEffect.by(
      Vector2.all(1.12),
      EffectController(
        duration: 0.16,
        reverseDuration: 0.14,
        curve: Curves.easeOut,
      ),
    ));
  }

  /// Empty the slot back to its dashed placeholder state.
  void clear() {
    filledType = null;
    filledColor = null;
    scale = Vector2.all(1.0);
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    final type = filledType;
    final color = filledColor;
    if (type != null && color != null) {
      // Filled: the same 3D card + shape used by the palette, so a copied slot
      // reads as "the same thing" the child just tapped.
      ShapePainter3D.drawCard3D(
        canvas,
        rect,
        color: color,
        cornerRadius: _cornerRadius,
        alpha: 150,
      );
      ShapePainter3D.drawByName(
        canvas, type.name, size.x / 2, size.y / 2, size.x * 0.28, color,
      );
      return;
    }

    // Empty: recessed grey square with a dashed outline.
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(_cornerRadius));
    canvas.drawRRect(rr, Paint()..color = _emptyFill);
    _drawDashedBorder(canvas, rr);
  }

  void _drawDashedBorder(Canvas canvas, RRect rr) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = _emptyBorder;

    final dash = math.max(8.0, size.x * 0.08);
    final gap = dash * 0.75;
    final path = Path()..addRRect(rr);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }
}
