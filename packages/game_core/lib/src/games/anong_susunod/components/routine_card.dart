import 'dart:ui';

import 'package:flame/components.dart';

import '../../../config/game_motion.dart';
import '../routine_art_cache.dart';
import '../routine_steps.dart';

/// A single picture card in the tray, or seated inside a slot.
///
/// Selection state is shown three ways at once — a thicker outline, a lift, and
/// a warm ring — because a child who cannot discriminate the outline colour
/// still needs to know which card they picked.
class RoutineCard extends PositionComponent {
  RoutineCard({
    required this.step,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor.center);

  final RoutineStep step;

  bool selected = false;

  /// Set while the card is being nudged by the prompt hierarchy.
  bool hinted = false;

  /// Seated in a slot: drawn flat, and no longer tappable in the tray.
  bool placed = false;

  double _t = 0;

  static const Color _surface = Color(0xFFFFFDF8);
  static const Color _outline = Color(0x333F3B4A);
  static const Color _primary = Color(0xFF9B82C4);
  static const Color _butter = Color(0xFFFFF4C4);

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  bool containsLocal(Vector2 point) {
    final half = size / 2;
    return (point.x - position.x).abs() <= half.x &&
        (point.y - position.y).abs() <= half.y;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final radius = size.x * 0.14;

    // A slow, shallow lift while selected. Under reduced motion the ring and
    // outline still carry the state, so nothing is lost by holding it still.
    var lift = 0.0;
    if (selected && !GameMotion.reduced) {
      lift = -2.5 - 1.5 * (0.5 + 0.5 * _wave(_t * 1.6));
    } else if (selected) {
      lift = -4;
    }

    canvas.save();
    canvas.translate(0, lift);

    final rr = RRect.fromRectXY(rect, radius, radius);

    // Drop shadow, heavier while lifted.
    canvas.drawRRect(
      RRect.fromRectXY(rect.translate(0, selected ? 5 : 3), radius, radius),
      Paint()..color = const Color(0x1A3F3B4A),
    );

    canvas.drawRRect(rr, Paint()..color = _surface);

    if (selected || hinted) {
      canvas.drawRRect(
        RRect.fromRectXY(rect.inflate(5), radius + 4, radius + 4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = _butter,
      );
    }

    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected || hinted ? 4 : 2.5
        ..color = selected || hinted ? _primary : _outline,
    );

    final art = size.x * 0.72;
    drawRoutineArt(
      canvas,
      step.art,
      Offset((size.x - art) / 2, (size.y - art) / 2),
      art,
    );

    canvas.restore();
  }

  static double _wave(double t) {
    // Cheap triangle wave — no trig needed for a 1.6 Hz breathe.
    final f = t % 1.0;
    return f < 0.5 ? f * 2 : 2 - f * 2;
  }
}
