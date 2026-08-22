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

  bool _dragging = false;

  static const double _cornerRadius = 24.0;

  @override
  void onTapDown(TapDownEvent event) {
    if (!inputEnabled) return;

    // Immediate visual feedback: show pressed state
    isPressed = true;

    // Slight scale-down for tactile press feel
    add(ScaleEffect.by(
      Vector2.all(0.93),
      EffectController(duration: 0.08, curve: Curves.easeIn),
    ));
  }

  @override
  void onTapUp(TapUpEvent event) {
    final wasPressed = isPressed;
    _releasePress();
    // A completed tap (not a drag) picks this shape — but only if the press
    // actually started while input was live.
    if (wasPressed && inputEnabled) onTapped(index);
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _releasePress();
  }

  void _releasePress() {
    if (!isPressed) return;
    isPressed = false;

    // Bounce back to normal scale
    add(ScaleEffect.by(
      Vector2.all(1 / 0.93),
      EffectController(duration: 0.1, curve: Curves.easeOut),
    ));
  }

  // ── Drag handling ────────────────────────────────────────────────────
  //
  // The palette card is fixed furniture, so a drag lifts a copy that follows
  // the finger and always returns home; the "choice" is reported on release.

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (!inputEnabled) return;
    _dragging = true;
    isPressed = false;
    priority = 100; // float above the other cards + slots while dragging
    startFingertipFollow(event.canvasPosition);
    add(ScaleEffect.to(
      Vector2.all(1.12),
      EffectController(duration: 0.12, curve: Curves.easeOut),
    ));
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!_dragging) return;
    moveFingertip(event.canvasEndPosition);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_dragging) followFingertip(dt);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!_dragging) return;
    final dropCenter = visualCenter;
    _dragging = false;
    stopFingertipFollow();
    priority = 0;
    _returnHome();
    onDragDropped?.call(index, dropCenter);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (!_dragging) return;
    _dragging = false;
    stopFingertipFollow();
    priority = 0;
    _returnHome();
  }

  void _returnHome() {
    add(MoveToEffect(
      homePosition,
      EffectController(duration: 0.2, curve: Curves.easeOut),
    ));
    add(ScaleEffect.to(
      Vector2.all(1.0),
      EffectController(duration: 0.12, curve: Curves.easeOut),
    ));
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
