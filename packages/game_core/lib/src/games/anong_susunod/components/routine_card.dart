import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:shared_ui/shared_ui.dart' show GameLanguage;

import '../../../config/game_motion.dart';
import '../../shared/fingertip_drag.dart';
import '../routine_art_cache.dart';
import '../routine_steps.dart';
import 'step_label.dart';

/// A single picture card in the tray, or seated inside a slot.
///
/// Selection state is shown three ways at once — a thicker outline, a lift, and
/// a warm ring — because a child who cannot discriminate the outline colour
/// still needs to know which card they picked.
///
/// The step's name is printed under the picture in [language]. TEACCH pairs the
/// symbol with its word rather than replacing one with the other: a pre-reader
/// works from the picture and loses nothing, and a child who is starting to
/// read gets the same word every time they meet the step.
///
/// Drag is driven by the game rather than by `DragCallbacks` here: the game
/// already owns the tap routing, and one component deciding both gestures is
/// what keeps a drag and a tap onto the same slot scored identically.
class RoutineCard extends PositionComponent with FingertipDrag {
  RoutineCard({
    required this.step,
    required this.language,
    required Vector2 position,
    required Vector2 size,
  })  : homePosition = position.clone(),
        super(position: position, size: size, anchor: Anchor.center);

  final RoutineStep step;

  /// The language the printed label is drawn in — the child's, not the
  /// device's.
  final GameLanguage language;

  final StepLabel _label = StepLabel();

  bool selected = false;

  /// Set while the card is being nudged by the prompt hierarchy.
  bool hinted = false;

  /// Seated in a slot: the slot draws the step from here on, so this stops
  /// rendering and stops answering to touches. Without the first of those the
  /// same step shows in two places at once, which is precisely the ambiguity a
  /// visual schedule exists to remove.
  bool placed = false;

  /// Where this card rests in the tray. A drag is released back to it, and the
  /// game's layout pass keeps it current as the canvas resizes.
  Vector2 homePosition;

  double _t = 0;

  static const Color _surface = Color(0xFFFFFDF8);
  static const Color _outline = Color(0x333F3B4A);
  static const Color _primary = Color(0xFF9B82C4);
  static const Color _butter = Color(0xFFFFF4C4);

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    // Ticked rather than event-driven so the grab offset keeps decaying while a
    // finger is held still — see [FingertipDrag].
    followFingertip(dt);
  }

  bool containsLocal(Vector2 point) {
    final half = size / 2;
    return (point.x - position.x).abs() <= half.x &&
        (point.y - position.y).abs() <= half.y;
  }

  @override
  void render(Canvas canvas) {
    // Seated: the slot is drawing this step now.
    if (placed) return;

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

    // The picture keeps the bulk of the card; the name takes a strip along the
    // bottom, sized so a two-line label still clears the rounded corner.
    final labelBand = size.y * 0.26;
    final pictureHeight = size.y - labelBand;
    final art = math.min(size.x * 0.72, pictureHeight * 0.9);
    drawRoutineArt(
      canvas,
      step.art,
      Offset((size.x - art) / 2, (pictureHeight - art) / 2),
      art,
    );

    _label.paint(
      canvas,
      step.label(language),
      origin: Offset(size.x * 0.06, pictureHeight),
      width: size.x * 0.88,
      height: labelBand,
      fontSize: math.max(9.0, size.x * 0.13),
    );

    canvas.restore();
  }

  static double _wave(double t) {
    // Cheap triangle wave — no trig needed for a 1.6 Hz breathe.
    final f = t % 1.0;
    return f < 0.5 ? f * 2 : 2 - f * 2;
  }
}
