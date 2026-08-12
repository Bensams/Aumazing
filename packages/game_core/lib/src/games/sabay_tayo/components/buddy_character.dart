import 'dart:ui';

import 'package:flame/components.dart';

import '../../../config/game_motion.dart';
import 'buddy_art_cache.dart';

/// The partner the child shares attention with in "Sabay Tayo!".
///
/// Draws one of the mascot sprite sheets ([BuddyArtCache]) and, crucially,
/// *aims*: [lookAt] picks the gaze pose whose direction matches where the
/// target actually sits on screen, so the eyes are a real cue rather than a
/// decoration the child learns to ignore.
///
/// Two things about the art constrain the design here:
///
/// * **The `point` sheet always points one way.** It was generated as "points
///   to its own left", which lands on the viewer's right. To point at anything
///   on the left the whole character is mirrored horizontally. That is why
///   tier 1 — the only tier where the pointing arm is a required support —
///   never places its objects in the middle column: a mirrored point is
///   unambiguous to the left or the right and meaningless straight up.
/// * **Gaze is nine discrete poses, not a sweep.** The generator will not
///   produce a smooth eye travel (see `scripts/SPRITES.md`), so the gaze
///   changes by swapping sheets. That reads as a deliberate head turn, which
///   is what a joint-attention cue should look like anyway.
class BuddyCharacter extends PositionComponent {
  BuddyCharacter({
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor.bottomCenter);

  /// Frames per second for gesture playback. `CalmMascot` clamps its own
  /// gestures to 3–8 fps and this matches the top of that range: the gestures
  /// here are feedback on an answer the child just gave, so they should land
  /// promptly rather than unfold.
  static const double _gestureFps = 8;

  /// Where the buddy is currently attending, as fractions of the playfield.
  /// (0.5, 0.5) is straight ahead at the child.
  double _gazeX = 0.5;
  double _gazeY = 0.5;

  /// The held pose when no gesture is playing — a `look_*` sheet, or `idle`.
  ///
  /// Never mirrored: the gaze sheets were generated one per direction, so the
  /// right pose already exists for every cell. Only the single-sided `point`
  /// sheet needs flipping.
  String _restingAction = 'idle';

  // ── Gesture playback ─────────────────────────────────────────────────
  String? _gesture;
  bool _gestureMirror = false;
  int _gestureFrame = 0;
  double _gestureElapsed = 0;

  /// Held after a gesture finishes, e.g. `encourage` following `oops`.
  String? _holdAction;
  double _holdRemaining = 0;

  /// The action being drawn this frame — gesture first, then any held pose,
  /// then the resting gaze.
  String get currentAction => _gesture ?? _holdAction ?? _restingAction;

  /// Whether a gesture is mid-playback. The game waits on this before moving
  /// on, so a celebration is never cut off by the next trial.
  bool get isGesturing => _gesture != null || _holdRemaining > 0;

  /// Aim the buddy at ([x], [y]) — fractions of the playfield, (0,0) top-left.
  ///
  /// Named `gazeAt` rather than `lookAt` because [PositionComponent] already
  /// has a `lookAt(Vector2)` that rotates the whole component — which is not
  /// what this does and not something this component should ever do.
  ///
  /// Falls back to `idle` for the centre cell and for any pose that failed to
  /// decode; the eyes in the painted fallback still track, because [drawBuddy]
  /// receives the fractions either way.
  void gazeAt(double x, double y) {
    _gazeX = x;
    _gazeY = y;
    _restingAction = resolvedGazeAction(x, y) ?? 'idle';
  }

  /// Return to facing the child.
  void faceChild() {
    _gazeX = 0.5;
    _gazeY = 0.5;
    _restingAction = 'idle';
  }

  /// Point at ([x], [y]) — the gestural rung of the prompt hierarchy, layered
  /// on top of the gaze rather than replacing it.
  ///
  /// The sheet points to the viewer's right, so a target on the left mirrors
  /// the character. A target in the middle third gets the unmirrored sheet and
  /// is, frankly, a weak cue — see the class comment on why tier 1 never puts
  /// a target there.
  void pointAt(double x, double y) {
    gazeAt(x, y);
    _playGesture('point', mirror: x < 0.5, hold: 'point', holdSeconds: 1.6);
  }

  /// Play the celebration — the reinforcement for a correct answer.
  void celebrate() {
    _playGesture('celebrate', mirror: false);
  }

  /// The soft "oh, not quite" for a wrong tap, handing straight over to
  /// `encourage`. Never a pose the buddy sits in: the child should see the
  /// reassurance, not the disappointment.
  void reassure() {
    _playGesture('oops', mirror: false, hold: 'encourage', holdSeconds: 1.0);
  }

  void _playGesture(
    String action, {
    required bool mirror,
    String? hold,
    double holdSeconds = 0,
  }) {
    _gesture = action;
    _gestureMirror = mirror;
    _gestureFrame = 0;
    _gestureElapsed = 0;
    _holdAction = hold;
    _holdRemaining = holdSeconds;

    // Reduced motion: skip straight to the end of the gesture and hold it. The
    // information a gesture carries is in its final pose — an extended arm, a
    // raised hand — and none of it needs the frames in between.
    if (GameMotion.reduced) {
      _gestureFrame = BuddyArtCache.frameCount(action) - 1;
      _finishGesture();
    }
  }

  /// Hands a finished gesture over to its held pose, if it has one. `point`
  /// holds *itself* — the arm stays extended while the child looks — whereas
  /// `oops` hands over to `encourage`.
  void _finishGesture() {
    _gesture = null;
    if (_holdAction == null) _holdRemaining = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_gesture != null) {
      _gestureElapsed += dt;
      final frames = BuddyArtCache.frameCount(_gesture!);
      final next = (_gestureElapsed * _gestureFps).floor();
      if (next >= frames) {
        _gestureFrame = frames - 1;
        _finishGesture();
      } else {
        _gestureFrame = next;
      }
      return;
    }

    if (_holdRemaining > 0) {
      _holdRemaining -= dt;
      if (_holdRemaining <= 0) {
        _holdAction = null;
        _holdRemaining = 0;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final action = currentAction;
    // Only a gesture or its held pose is ever mirrored; a resting gaze has its
    // own sheet per direction.
    final mirror =
        (_gesture != null || _holdAction != null) && _gestureMirror;

    // Held poses draw their sheet's last frame; a gesture draws its current
    // one; a gaze still is a single cell either way.
    final frame = _gesture != null
        ? _gestureFrame
        : (_holdAction != null ? BuddyArtCache.frameCount(action) - 1 : 0);

    final dest = Rect.fromLTWH(0, 0, size.x, size.y);

    canvas.save();
    if (mirror) {
      canvas.translate(size.x, 0);
      canvas.scale(-1, 1);
    }
    drawBuddy(
      canvas,
      action,
      dest,
      frameIndex: frame,
      // The fallback aims from these, and a mirrored canvas would otherwise
      // send its pupils the wrong way.
      gazeX: mirror ? 1 - _gazeX : _gazeX,
      gazeY: _gazeY,
    );
    canvas.restore();
  }
}
