import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../../config/game_motion.dart';
import '../../shared/fingertip_drag.dart';
import '../../shared/shape_painter_3d.dart';
import '../greetings.dart';

/// Called when the child answers with a card, by tap or by drag.
///
/// [pressedAt] is when the finger first came down on the card — the moment
/// the child *responded*, whichever way they then finished the gesture — so
/// greeting latency means the same thing for a tap and for a drag.
typedef GreetingTapped = void Function(
    GreetingButton button, DateTime pressedAt);

/// Called when the child lets go of a dragged card. [dropCenter] is the
/// card's centre, in game space, at the moment it was released.
typedef GreetingDropped = void Function(
    GreetingButton button, Vector2 dropCenter, DateTime pressedAt);

/// One large greeting card the child taps — or drags to the buddy — to greet
/// back.
///
/// Styled as a card the same way `sari_sari_sort`'s items are, so the two games
/// feel like the same app. A tap is always enough: returning a greeting is a
/// single act, and *requiring* a drag would put a motor-planning demand in
/// front of a social one. Dragging the card onto the buddy is offered as well,
/// because handing the greeting *to* the buddy is how many children naturally
/// try it — and a child who reaches toward the character is making exactly the
/// social move the game is about.
///
/// Tap and drag share one component, so they are told apart by distance, the
/// way Match It does it: a release within [_tapSlop] of where the finger came
/// down is a tap, however long it was held. The drag recognizer claims the
/// pointer as soon as it moves at all, so waiting for a perfectly still finger
/// would lose nearly every child's tap.
class GreetingButton extends PositionComponent
    with TapCallbacks, DragCallbacks, FingertipDrag {
  GreetingButton({
    required this.greeting,
    required this.color,
    required Vector2 position,
    required Vector2 size,
    this.onTapped,
    this.onDropped,
    this.claimsPoint,
  }) : super(position: position, size: size) {
    homePosition = position.clone();
  }

  final Greeting greeting;
  final Color color;

  /// Fired for a tap (including a wobbly one that never left the card).
  final GreetingTapped? onTapped;

  /// Fired when a real drag ends. The game decides whether the card landed on
  /// the buddy; the card only moves.
  final GreetingDropped? onDropped;

  /// Decides which card owns a point where the generous hit boxes of two
  /// neighbours overlap. Given a point in game space, returns whether this
  /// card should take it. Without one, the inflated bounds alone decide.
  final bool Function(GreetingButton button, Vector2 point)? claimsPoint;

  /// Where the card rests in the row. The game updates it on every layout;
  /// the card glides back here after a drag.
  late Vector2 homePosition;

  /// Pointer travel (game px) below which a release still counts as a tap.
  static const double _tapSlop = 14.0;

  /// When the finger came down on the card, for greeting latency.
  DateTime? _pressedAt;

  /// Where the finger came down, in game space. The tap/drag decision is
  /// displacement from here, not accumulated movement, so a trembling finger
  /// that never leaves the card keeps its tap.
  Vector2? _pointerOrigin;

  /// The drag recognizer has this pointer.
  bool _pointerDown = false;

  /// The pointer has travelled past [_tapSlop]: a real drag.
  bool _dragging = false;

  /// Whether the child is holding the card away from its slot right now.
  bool get isDragging => _dragging;

  /// Set while the correct-icon pulse (prompt rung 2) is running.
  bool _pulsing = false;

  /// Whether prompt rung 2 is highlighting this card. Exposed so a test
  /// can assert that a re-orientation did NOT reveal the answer.
  bool get isPulsing => _pulsing;

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

  /// Routes pointer events to this card using the same generous bounds, and
  /// lets the game break ties between overlapping neighbours by distance.
  @override
  bool containsLocalPoint(Vector2 point) {
    final inGame = position + point;
    if (!containsPointGenerous(inGame)) return false;
    return claimsPoint?.call(this, inGame) ?? true;
  }

  // ── Tap and drag input ───────────────────────────────────────────────

  @override
  void onTapDown(TapDownEvent event) {
    _pressedAt ??= DateTime.now();
  }

  /// The rare tap the gesture arena awards to the tap recognizer: the finger
  /// did not move at all, so the drag path never saw it.
  @override
  void onTapUp(TapUpEvent event) {
    if (_pointerDown) return;
    final pressedAt = _pressedAt ?? DateTime.now();
    _pressedAt = null;
    onTapped?.call(this, pressedAt);
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    // The drag recognizer took the pointer; it now owns the press time.
    if (!_pointerDown) _pressedAt = null;
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _pointerDown = true;
    _dragging = false;
    _pressedAt ??= DateTime.now();
    _pointerOrigin = event.canvasPosition.clone();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!_pointerDown) return;
    if (!_dragging) {
      // Still tap-like: leave the card in its slot so a shaky tap does not
      // visibly nudge it.
      final origin = _pointerOrigin;
      if (origin != null &&
          (event.canvasEndPosition - origin).length < _tapSlop) {
        return;
      }
      _dragging = true;
      priority = 100; // above the buddy and the other cards while held
      // Centring starts only once the gesture is confirmed as a drag; the
      // glide covers the catch-up.
      startFingertipFollow(event.canvasEndPosition);
      return;
    }
    moveFingertip(event.canvasEndPosition);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!_pointerDown) return;
    _pointerDown = false;
    final pressedAt = _pressedAt ?? DateTime.now();
    _pressedAt = null;

    if (!_dragging) {
      // Released without ever leaving the card — that was a tap.
      onTapped?.call(this, pressedAt);
      return;
    }

    _dragging = false;
    final dropCenter = visualCenter;
    stopFingertipFollow();
    priority = 0;
    onDropped?.call(this, dropCenter, pressedAt);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    // Flame implements onDragCancel as onDragEnd(event.toDragEnd()). Clear
    // the pointer first so that dispatch cannot run the drop path for a
    // gesture that was cancelled, not released.
    final wasDragging = _dragging;
    _pointerDown = false;
    _dragging = false;
    _pressedAt = null;
    super.onDragCancel(event);
    if (!wasDragging) return;
    stopFingertipFollow();
    priority = 0;
    returnHome();
  }

  /// Glide back to the card's slot — after a drop anywhere but the buddy, and
  /// after the buddy has taken the greeting. [onArrived] runs once it is home,
  /// so a bounce or press animation plays in the slot rather than mid-flight.
  void returnHome({void Function()? onArrived}) {
    removeWhere((c) => c is MoveToEffect);
    if ((position - homePosition).length < 0.5) {
      position = homePosition.clone();
      onArrived?.call();
      return;
    }
    add(MoveToEffect(
      homePosition.clone(),
      EffectController(duration: 0.22, curve: Curves.easeOut),
      onComplete: onArrived,
    ));
  }

  /// The centre of the card, for the ghost hand and the pulse.
  Vector2 get centre => position + size / 2;

  /// Idle-motion phase, in seconds. Advanced only for [Greeting.wave] and
  /// [Greeting.highFive], and only while motion is allowed, so the two
  /// hardest-to-name gestures each carry a distinct *movement* — a rocking
  /// swing versus a push-in zoom — that a child recognises without reading a
  /// label. Exposed read-only so the reduced-motion contract is testable.
  double _idle = 0;
  double get idlePhase => _idle;

  @override
  void update(double dt) {
    super.update(dt);
    followFingertip(dt);
    if (GameMotion.reduced) return;
    if (greeting == Greeting.wave || greeting == Greeting.highFive) {
      _idle += dt;
    }
  }

  /// Transforms [canvas] so the hand rocks (wave) or pushes in and out (high
  /// five) around [pivot]. Only the painted glyph moves: the card body, its
  /// generous hit box, and the pulse/reject/confirm effects on the component
  /// itself are untouched, so tapping, selection and dragging behave exactly
  /// as before. Under reduced motion nothing is pushed and the hand is still.
  /// Returns whether a matching [Canvas.restore] is owed.
  bool _applyIdleMotion(Canvas canvas, Offset pivot) {
    if (GameMotion.reduced) return false;
    const twoPi = math.pi * 2;
    double angle = 0;
    double scale = 1;
    switch (greeting) {
      case Greeting.wave:
        // ~13 degrees each way at ~1.1 Hz: an unmistakable left-right wave.
        angle = 0.22 * math.sin(twoPi * 1.1 * _idle);
      case Greeting.highFive:
        // The palm eases toward the child and back at ~1 Hz — a high five.
        scale = 1 + 0.13 * math.sin(twoPi * _idle);
      default:
        return false;
    }
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    if (angle != 0) canvas.rotate(angle);
    if (scale != 1) canvas.scale(scale);
    canvas.translate(-pivot.dx, -pivot.dy);
    return true;
  }

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

    final glyphBox = Rect.fromCenter(
      center: rect.center,
      width: rect.width * 0.66,
      height: rect.height * 0.66,
    );
    final animating = _applyIdleMotion(canvas, glyphBox.center);
    paintGreetingGlyph(
      canvas,
      greeting,
      glyphBox,
      skin: _skin,
      ink: _ink,
    );
    if (animating) canvas.restore();
  }
}
