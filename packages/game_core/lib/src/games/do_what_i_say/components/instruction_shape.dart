import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';

import 'package:shared_ui/shared_ui.dart';

/// Shape size category for Do What I Say instructions.
enum SizeCategory { big, small }

/// Tappable shape for the Do What I Say game.
class InstructionShape extends PositionComponent with TapCallbacks {
  InstructionShape({
    required this.shapeType,
    required this.shapeColor,
    required this.colorName,
    required this.sizeCategory,
    required this.index,
    required this.onTapped,
    super.position,
    super.size,
  });

  final String shapeType; // 'circle', 'star', 'triangle', 'diamond'
  final Color shapeColor;
  final String colorName; // 'red', 'blue', etc.
  final SizeCategory sizeCategory;
  final int index;
  final void Function(int index) onTapped;

  bool showingCorrect = false;
  bool showingWrong = false;
  bool inputEnabled = true;

  static const double _cornerRadius = 20.0;

  @override
  void onTapDown(TapDownEvent event) {
    if (!inputEnabled) return;
    onTapped(index);
  }

  void showCorrect() {
    showingCorrect = true;
    add(ScaleEffect.by(
      Vector2.all(1.08),
      EffectController(duration: 0.15, curve: Curves.easeOut),
    ));
    Future.delayed(const Duration(milliseconds: 500), () {
      showingCorrect = false;
      scale = Vector2.all(1.0);
    });
  }

  void showWrong() {
    showingWrong = true;
    add(SequenceEffect([
      MoveEffect.by(Vector2(6, 0), EffectController(duration: 0.05)),
      MoveEffect.by(Vector2(-12, 0), EffectController(duration: 0.1)),
      MoveEffect.by(Vector2(12, 0), EffectController(duration: 0.1)),
      MoveEffect.by(Vector2(-6, 0), EffectController(duration: 0.05)),
    ]));
    Future.delayed(const Duration(milliseconds: 400), () {
      showingWrong = false;
    });
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_cornerRadius),
    );

    int bgAlpha = 40;
    if (showingCorrect) bgAlpha = 120;
    if (showingWrong) bgAlpha = 100;

    canvas.drawRRect(rrect, Paint()..color = shapeColor.withAlpha(bgAlpha));

    if (showingCorrect || showingWrong) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = showingWrong ? const Color(0xFFE88888) : AppColors.mint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    _drawShape(canvas, size.x / 2, size.y / 2, size.x * 0.3);
  }

  void _drawShape(Canvas canvas, double cx, double cy, double r) {
    final paint = Paint()
      ..color = shapeColor
      ..style = PaintingStyle.fill;

    switch (shapeType) {
      case 'circle':
        canvas.drawCircle(Offset(cx, cy), r, paint);
      case 'star':
        _drawStar(canvas, cx, cy, r, paint);
      case 'triangle':
        final path = Path()
          ..moveTo(cx, cy - r)
          ..lineTo(cx + r * 0.87, cy + r * 0.5)
          ..lineTo(cx - r * 0.87, cy + r * 0.5)
          ..close();
        canvas.drawPath(path, paint);
      case 'diamond':
        final path = Path()
          ..moveTo(cx, cy - r)
          ..lineTo(cx + r * 0.7, cy)
          ..lineTo(cx, cy + r)
          ..lineTo(cx - r * 0.7, cy)
          ..close();
        canvas.drawPath(path, paint);
    }
  }

  void _drawStar(Canvas canvas, double cx, double cy, double r, Paint p) {
    final path = Path();
    final inner = r * 0.45;
    for (var i = 0; i < 10; i++) {
      final angle = (i * math.pi / 5) - math.pi / 2;
      final radius = i.isEven ? r : inner;
      path.lineTo(cx + radius * math.cos(angle), cy + radius * math.sin(angle));
    }
    path.close();
    canvas.drawPath(path, p);
  }
}
