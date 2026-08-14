import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../../config/game_motion.dart';
import '../../shared/shape_painter_3d.dart';
import '../greetings.dart';

/// One large icon button the child taps to greet back.
///
/// Styled as a card the same way `sari_sari_sort`'s items are, so the two games
/// feel like the same app, but tapped rather than dragged: returning a greeting
/// is a single act, and asking for a drag would put a motor-planning demand in
/// front of a social one.
class GreetingButton extends PositionComponent {
  GreetingButton({
    required this.greeting,
    required this.color,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size);

  final Greeting greeting;
  final Color color;

  /// Set while the correct-icon pulse (prompt rung 2) is running.
  bool _pulsing = false;

  /// Set briefly after a wrong tap: the card bounces back rather than being
  /// removed or dimmed, so nothing is ever taken away from the child.
  bool _rejecting = false;

  static const Color _ink = Color(0xFF5A5A6B);
  static const Color _skin = Color(0xFFF2DFC0);

  /// Hit test with ~20% inflated bounds, matching `sari_sari_sort`'s tolerance.
  ///
  /// A child aiming at a hand and landing four pixels off the card has answered
  /// the social bid correctly; scoring that as a miss measures their fine motor
  /// control, which is not what this game is for.
  bool containsPointGenerous(Vector2 point) {
    final rect = toRect().inflate(math.min(size.x, size.y) * 0.20);
    return rect.contains(Offset(point.x, point.y));
  }

  /// The centre of the card, for the ghost hand and the pulse.
  Vector2 get centre => position + size / 2;

  /// Bounce the card back — the gentle answer to a wrong tap.
  void rejectGently() {
    _rejecting = true;
    add(SequenceEffect(
      [
        MoveEffect.by(Vector2(0, -size.y * 0.10),
            EffectController(duration: 0.12, curve: Curves.easeOut)),
        MoveEffect.by(Vector2(0, size.y * 0.10),
            EffectController(duration: 0.18, curve: Curves.easeIn)),
      ],
      onComplete: () => _rejecting = false,
    ));
  }

  /// Prompt rung 2: draw the eye to the right card without pressing it.
  void startPulse() {
    if (_pulsing) return;
    _pulsing = true;
    // Under reduced motion the highlight is static — same information, no
    // repeating movement. Same trade the other games make for hint rings.
    if (GameMotion.reduced) return;
    add(SequenceEffect(
      [
        ScaleEffect.to(Vector2.all(1.08),
            EffectController(duration: 0.45, curve: Curves.easeInOut)),
        ScaleEffect.to(Vector2.all(1.0),
            EffectController(duration: 0.45, curve: Curves.easeInOut)),
      ],
      infinite: true,
    ));
  }

  void stopPulse() {
    if (!_pulsing) return;
    _pulsing = false;
    removeWhere((c) => c is SequenceEffect);
    scale = Vector2.all(1.0);
  }

  /// Acknowledge a correct tap: a single confident press-and-release.
  void confirm() {
    add(SequenceEffect([
      ScaleEffect.to(Vector2.all(0.92),
          EffectController(duration: 0.09, curve: Curves.easeOut)),
      ScaleEffect.to(Vector2.all(1.0),
          EffectController(duration: 0.16, curve: Curves.easeOutBack)),
    ]));
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Two real states draw their own border; anything else is a resting card
    // and takes the parent's standing outline.
    //
    //  * pulsing — prompt rung 2, the same amber the other games use for a
    //    hint. It must stay visible under reduced motion, where the scale
    //    animation never runs and the border is the whole prompt. It used to
    //    be white, which is indistinguishable from a card marked correct.
    //  * rejecting — the wrong-tap red, matching Match It and Sari-Sari Sort.
    final Color? stateBorder = _pulsing
        ? const Color(0xFFFFA726)
        : (_rejecting ? const Color(0xFFE88888) : null);

    ShapePainter3D.drawCard3D(
      canvas,
      rect,
      color: color,
      cornerRadius: size.x * 0.16,
      alpha: 255,
      showBorder: stateBorder != null,
      borderColor: stateBorder,
      borderWidth: _pulsing ? 6.0 : 3.0,
    );

    paintGreetingGlyph(
      canvas,
      greeting,
      Rect.fromCenter(
        center: rect.center,
        width: rect.width * 0.66,
        height: rect.height * 0.66,
      ),
      skin: _skin,
      ink: _ink,
    );
  }
}
