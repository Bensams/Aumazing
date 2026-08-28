import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../config/game_motion.dart';
import '../emotion_art_cache.dart';
import '../emotions.dart';

/// The buddy — the child in the picture — showing how they feel.
///
/// The face **transitions into** the emotion from neutral rather than simply
/// holding it, and that is the first rung of this game's prompt hierarchy. A
/// held expression is a static puzzle: the child has to decode a configuration
/// of features. The same expression arriving as movement gives them the change
/// itself, which is far more legible — the brows go *up*, the mouth turns
/// *down* — and it is closer to how a face is read in a real room.
///
/// Under [GameMotion.reduced] the transition **cross-fades** instead of
/// animating the geometry: a child who finds motion aversive still needs the
/// before-and-after, and a hard cut would lose it.
class BuddyFace extends PositionComponent {
  BuddyFace({
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor.center);

  Emotion emotion = Emotion.happy;

  /// 0 = neutral rest pose, 1 = the full expression.
  double _t = 1;

  double _elapsed = 0;
  bool _running = false;

  /// How long the neutral→emotion transition takes. Slow enough to be followed
  /// by a child who is still finding the face on screen, short enough that a
  /// replayed prompt does not stall the trial.
  static const double _duration = 0.75;

  /// A beat on neutral before the change starts, so there is a *before* to
  /// notice. Without it the face is already moving by the time a child looks.
  static const double _hold = 0.35;

  bool get isAnimating => _running;

  /// Restarts the transition from neutral. Called when a round opens and again
  /// on each first-level prompt.
  void playTransition() {
    _elapsed = 0;
    _t = 0;
    _running = true;
  }

  /// Jumps straight to the full expression, no transition.
  void settle() {
    _running = false;
    _t = 1;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_running) return;
    _elapsed += dt;
    final progress = ((_elapsed - _hold) / _duration).clamp(0.0, 1.0);
    // Ease-out: the expression arrives quickly and then settles, which is how a
    // real face moves and keeps the informative part of the change early.
    _t = 1 - math.pow(1 - progress, 3).toDouble();
    if (progress >= 1.0) _running = false;
  }

  @override
  void render(Canvas canvas) {
    final size = math.min(this.size.x, this.size.y);
    final origin = Offset((this.size.x - size) / 2, (this.size.y - size) / 2);

    // A soft halo so the face reads against any game background.
    canvas.drawCircle(
      Offset(this.size.x / 2, this.size.y / 2),
      size * 0.52,
      Paint()..color = const Color(0x30FFFFFF),
    );

    // Same number either way; only how it is applied changes — see [drawFace].
    drawFace(canvas, emotion, origin, size,
        t: _t, crossFade: GameMotion.reduced);
  }
}
