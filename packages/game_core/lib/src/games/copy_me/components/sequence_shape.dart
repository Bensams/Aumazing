import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';

import 'package:shared_ui/shared_ui.dart';
import '../../../config/game_motion.dart';
import '../../shared/fingertip_drag.dart';
import '../../shared/shape_painter_3d.dart';

/// Shape used in the Copy Me game for sequence demonstrations.
enum CopyMeShapeType { circle, star, heart, diamond }

/// A palette card in the Copy Me game — one of the four fixed shapes the child
/// copies the pattern with. It accepts **both** gestures: a tap picks the shape,
/// and a drag lifts the card and carries it up toward the pattern row before
/// dropping it in. Either way the game is told which shape the child chose.
class SequenceShape extends PositionComponent
    with TapCallbacks, DragCallbacks, FingertipDrag {
  SequenceShape({
    required this.shapeType,
    required this.shapeColor,
    required this.index,
    required this.onTapped,
    this.onDragDropped,
    super.position,
    super.size,
  }) {
    homePosition = this.position.clone();
  }

  final CopyMeShapeType shapeType;
  final Color shapeColor;
  final int index;

  /// Fired when the child taps the card (picks this shape).
  final void Function(int index) onTapped;

  /// Fired when the child releases a drag of this card. [dropCenter] is the
  /// card's centre in game space; the game decides whether it landed on the
  /// pattern row and, if so, treats it as picking this shape. The card always
  /// returns to its palette slot afterward.
  final void Function(int index, Vector2 dropCenter)? onDragDropped;

  bool isHighlighted = false;
  bool isCorrect = false;
  bool isWrong = false;
  bool isHint = false;
  bool isPressed = false;
  bool inputEnabled = false;

  /// Resting position in the palette; a dragged card glides back here.
  late Vector2 homePosition;

  // ── Tap / drag arbitration ───────────────────────────────────────────
  //
  // Tap and drag live on the SAME card. Flame's drag recognizer claims the
  // pointer the instant it moves at all, which knocks the tap recognizer out
  // of the gesture arena — so on a component with both TapCallbacks and
  // DragCallbacks, onTapUp only fires for a perfectly still finger. Children
  // are never that still, so a tap is resolved in onDragEnd instead: a press
  // that never travels past [_tapSlop] counts as a tap; anything further is a
  // real drag. This is the same pattern Match It and My Turn Your Turn use.

  /// The pointer is currently being tracked by the drag recognizer.
  bool _pointerDown = false;

  /// The pointer has travelled past [_tapSlop] — this is a drag, not a tap.
  bool _dragging = false;

  /// Where the pointer went down, in game space. The tap/drag test is the
  /// DISPLACEMENT from here, not the running sum of deltas, so a trembling
  /// finger that never leaves the card keeps its tap.
  Vector2? _pointerOrigin;

  /// Pointer travel (game px) below which a release counts as a tap.
  static const double _tapSlop = 14.0;

  static const double _cornerRadius = 24.0;

  @override
  void onTapDown(TapDownEvent event) {}

  @override
  void onTapUp(TapUpEvent event) {
    // Only reached for the rare tap the arena awards to the tap recognizer
    // (a genuinely motionless finger); the usual path is onDragEnd.
    if (!inputEnabled || _pointerDown) return;
    onTapped(index);
  }

  // ── Drag-and-drop input ──────────────────────────────────────────────

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (!inputEnabled) return;
    _pointerDown = true;
    _dragging = false;
    isPressed = true;
    _pointerOrigin = event.canvasPosition.clone();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!inputEnabled || !_pointerDown) return;

    if (!_dragging) {
      // Still tap-like: leave the card in its slot so a shaky tap doesn't
      // visibly nudge it.
      final origin = _pointerOrigin;
      if (origin != null &&
          (event.canvasEndPosition - origin).length < _tapSlop) {
        return;
      }
      // Confirmed as a drag: lift the card and start following the fingertip.
      _dragging = true;
      isPressed = false;
      priority = 100; // float above the other cards + slots while dragging
      add(ScaleEffect.to(
        Vector2.all(1.12),
        EffectController(duration: 0.1, curve: Curves.easeOut),
      ));
      startFingertipFollow(event.canvasEndPosition);
      return;
    }

    moveFingertip(event.canvasEndPosition);
  }

  @override
  void update(double dt) {
    super.update(dt);
    followFingertip(dt);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!_pointerDown) return;
    _pointerDown = false;
    isPressed = false;

    if (!_dragging) {
      // Released without ever leaving the card — that was a tap.
      if (inputEnabled) onTapped(index);
      return;
    }

    _dragging = false;
    // Read the centre before the card snaps back, so the drop point is the card
    // as the child last saw it.
    final dropCenter = visualCenter;
    stopFingertipFollow();
    priority = 0;
    scale = Vector2.all(1.0);
    position = homePosition.clone(); // palette cards are fixed furniture
    onDragDropped?.call(index, dropCenter);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _pointerDown = false;
    isPressed = false;
    if (!_dragging) return;
    _dragging = false;
    stopFingertipFollow();
    priority = 0;
    scale = Vector2.all(1.0);
    position = homePosition.clone();
  }

  void highlight() {
    isHighlighted = true;
    add(ScaleEffect.by(
      Vector2.all(1.1),
      EffectController(
        duration: 0.25,
        reverseDuration: 0.25,
        curve: Curves.easeInOut,
      ),
    ));
    Future.delayed(const Duration(milliseconds: 500), () {
      isHighlighted = false;
    });
  }

  void showCorrect() {
    isCorrect = true;
    isPressed = false; // Clear press state
    add(ScaleEffect.by(
      Vector2.all(1.08),
      EffectController(duration: 0.15, curve: Curves.easeOut),
    ));
    Future.delayed(const Duration(milliseconds: 400), () {
      isCorrect = false;
      scale = Vector2.all(1.0);
    });
  }

  void showWrong() {
    isWrong = true;
    isPressed = false; // Clear press state
    scale = Vector2.all(1.0); // Reset scale before shake
    add(SequenceEffect([
      MoveEffect.by(Vector2(6, 0), EffectController(duration: 0.05)),
      MoveEffect.by(Vector2(-12, 0), EffectController(duration: 0.1)),
      MoveEffect.by(Vector2(12, 0), EffectController(duration: 0.1)),
      MoveEffect.by(Vector2(-6, 0), EffectController(duration: 0.05)),
    ]));
    Future.delayed(const Duration(milliseconds: 400), () {
      isWrong = false;
    });
  }

  void showHint() {
    isHint = true;
  }

  void hideHint() {
    isHint = false;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Card background alpha — increased from 40 to 110 for better visibility
    int alpha = 110;
    if (isPressed) alpha = 150;
    if (isHighlighted) alpha = 180;
    if (isCorrect) alpha = 160;
    if (isWrong) alpha = 130;
    if (isHint) alpha = 120;

    // Border — a *state* border only. A card at rest takes the parent's
    // standing outline instead, which is what makes it read as a tappable
    // card; it used to draw its own tinted border unconditionally, so no card
    // on the board was ever visibly plain.
    Color? borderColor;
    if (isPressed) {
      borderColor = shapeColor;
    } else if (isWrong) {
      borderColor = const Color(0xFFE88888);
    } else if (isCorrect) {
      borderColor = AppColors.mint;
    } else if (isHighlighted) {
      borderColor = shapeColor;
    } else if (isHint) {
      borderColor = const Color(0xFFFFA726);
    }
    final showBorder = borderColor != null;

    // Hint indicator - pulsing ring around the shape
    if (isHint) {
      final pulseAlpha = GameMotion.reduced
          ? 240
          : (128 + 127 * (DateTime.now().millisecond % 1000) / 1000)
              .round()
              .clamp(0, 255);
      final hintPaint = Paint()
        ..color = const Color(0xFFFFA726).withAlpha(pulseAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-8, -8, size.x + 16, size.y + 16),
          const Radius.circular(_cornerRadius + 4),
        ),
        hintPaint,
      );
    }

    ShapePainter3D.drawCard3D(
      canvas,
      rect,
      color: shapeColor,
      cornerRadius: _cornerRadius,
      alpha: alpha,
      showBorder: showBorder,
      borderColor: borderColor,
    );

    // 3D shape icon — increased default alpha from 200 to full color for visibility
    final drawColor = (isHighlighted || isPressed) ? shapeColor : shapeColor.withAlpha(230);
    ShapePainter3D.drawByName(
      canvas, shapeType.name, size.x / 2, size.y / 2, size.x * 0.28, drawColor,
    );
  }
}
