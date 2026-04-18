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
  bool inputEnabled = false;

  static const double _cornerRadius = 24.0;

  @override
  void onTapDown(TapDownEvent event) {
    if (!inputEnabled) return;
    onTapped(index);
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

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Card background alpha
    int alpha = 40;
    if (isHighlighted) alpha = 160;
    if (isCorrect) alpha = 120;
    if (isWrong) alpha = 100;

    // Border
    Color? borderColor;
    if (isWrong) {
      borderColor = const Color(0xFFE88888);
    } else if (isCorrect) {
      borderColor = AppColors.mint;
    } else if (isHighlighted) {
      borderColor = shapeColor;
    }

    ShapePainter3D.drawCard3D(
      canvas,
      rect,
      color: shapeColor,
      cornerRadius: _cornerRadius,
      alpha: alpha,
      showBorder: isHighlighted || isCorrect || isWrong,
      borderColor: borderColor,
    );

    // 3D shape icon
    final drawColor = isHighlighted ? shapeColor : shapeColor.withAlpha(200);
    ShapePainter3D.drawByName(
      canvas, shapeType.name, size.x / 2, size.y / 2, size.x * 0.28, drawColor,
    );
  }
}
