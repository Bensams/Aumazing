import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';

import 'package:shared_ui/shared_ui.dart';
import '../../shared/shape_painter_3d.dart';

/// Shape used in the Copy Me game for sequence demonstrations.
enum CopyMeShapeType { circle, star, heart, diamond }

class SequenceShape extends PositionComponent with TapCallbacks {
  SequenceShape({
    required this.shapeType,
    required this.shapeColor,
    required this.index,
    required this.onTapped,
    super.position,
    super.size,
  });

  final CopyMeShapeType shapeType;
  final Color shapeColor;
  final int index;
  final void Function(int index) onTapped;

  bool isHighlighted = false;
  bool isCorrect = false;
  bool isWrong = false;
  bool isHint = false;
  bool isPressed = false;
  bool inputEnabled = false;

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

    onTapped(index);
  }

  @override
  void onTapUp(TapUpEvent event) {
    _releasePress();
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

    // Border — always show a subtle border so shapes look like tappable cards
    Color? borderColor;
    bool showBorder = true;
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
    } else {
      // Default subtle border so shapes look interactive
      borderColor = shapeColor.withAlpha(60);
    }

    // Hint indicator - pulsing ring around the shape
    if (isHint) {
      final pulseAlpha = (128 + 127 * (DateTime.now().millisecond % 1000) / 1000).round().clamp(0, 255);
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
