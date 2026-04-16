import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';

import 'package:shared_ui/shared_ui.dart';

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
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_cornerRadius),
    );

    // Background
    int alpha = 40;
    if (isHighlighted) alpha = 160;
    if (isCorrect) alpha = 120;
    if (isWrong) alpha = 100;

    canvas.drawRRect(rrect, Paint()..color = shapeColor.withAlpha(alpha));

    // Border
    if (isHighlighted || isCorrect || isWrong) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isWrong
              ? const Color(0xFFE88888)
              : isCorrect
                  ? AppColors.mint
                  : shapeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // Draw shape
    _drawShape(canvas, size.x / 2, size.y / 2, size.x * 0.28);
  }

  void _drawShape(Canvas canvas, double cx, double cy, double r) {
    final paint = Paint()
      ..color = isHighlighted ? shapeColor : shapeColor.withAlpha(200)
      ..style = PaintingStyle.fill;

    switch (shapeType) {
      case CopyMeShapeType.circle:
        canvas.drawCircle(Offset(cx, cy), r, paint);
      case CopyMeShapeType.star:
        _drawStar(canvas, cx, cy, r, paint);
      case CopyMeShapeType.heart:
        _drawHeart(canvas, cx, cy, r, paint);
      case CopyMeShapeType.diamond:
        _drawDiamond(canvas, cx, cy, r, paint);
    }
  }

  void _drawStar(Canvas canvas, double cx, double cy, double r, Paint p) {
    final path = Path();
    final inner = r * 0.45;
    for (var i = 0; i < 10; i++) {
      final angle = (i * math.pi / 5) - math.pi / 2;
      final radius = i.isEven ? r : inner;
      final x = cx + radius * math.cos(angle);
      final y = cy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, p);
  }

  void _drawHeart(Canvas canvas, double cx, double cy, double r, Paint p) {
    final path = Path();
    final w = r * 1.1, h = r * 1.1;
    path.moveTo(cx, cy + h * 0.6);
    path.cubicTo(cx - w * 1.2, cy - h * 0.2, cx - w * 0.4, cy - h * 0.9,
        cx, cy - h * 0.3);
    path.cubicTo(cx + w * 0.4, cy - h * 0.9, cx + w * 1.2, cy - h * 0.2,
        cx, cy + h * 0.6);
    path.close();
    canvas.drawPath(path, p);
  }

  void _drawDiamond(Canvas canvas, double cx, double cy, double r, Paint p) {
    canvas.drawPath(
      Path()
        ..moveTo(cx, cy - r)
        ..lineTo(cx + r * 0.7, cy)
        ..lineTo(cx, cy + r)
        ..lineTo(cx - r * 0.7, cy)
        ..close(),
      p,
    );
  }
}
