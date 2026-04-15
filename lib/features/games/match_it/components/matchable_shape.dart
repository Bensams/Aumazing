import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';

/// The shape type drawn on each matchable card.
enum ShapeType { star, heart, circle, diamond, triangle }

/// A large, ASD-friendly tappable shape component for the Match It game.
///
/// Renders a colored rounded-rect card with a centered shape icon.
/// Supports selection highlight, correct/incorrect feedback, and
/// gentle scale animations.
class MatchableShape extends PositionComponent with TapCallbacks {
  MatchableShape({
    required this.shapeType,
    required this.shapeColor,
    required this.index,
    required this.onSelected,
    super.position,
    super.size,
  });

  final ShapeType shapeType;
  final Color shapeColor;
  final int index;
  final void Function(int index) onSelected;

  bool isSelected = false;
  bool isMatched = false;
  bool _showError = false;

  static const double _cornerRadius = 24.0;
  static const double _borderWidth = 3.0;

  @override
  void onTapDown(TapDownEvent event) {
    if (isMatched) return;
    onSelected(index);
  }

  void select() {
    isSelected = true;
    add(ScaleEffect.by(
      Vector2.all(1.05),
      EffectController(duration: 0.15, curve: Curves.easeOut),
    ));
  }

  void deselect() {
    isSelected = false;
    scale = Vector2.all(1.0);
  }

  void markMatched() {
    isMatched = true;
    isSelected = false;
    add(ScaleEffect.by(
      Vector2.all(0.9),
      EffectController(duration: 0.3, curve: Curves.easeInOut),
    ));
    add(OpacityEffect.to(
      0.4,
      EffectController(duration: 0.3),
    ));
  }

  void showError() {
    _showError = true;
    isSelected = true;
    add(
      SequenceEffect([
        MoveEffect.by(
          Vector2(6, 0),
          EffectController(duration: 0.05),
        ),
        MoveEffect.by(
          Vector2(-12, 0),
          EffectController(duration: 0.1),
        ),
        MoveEffect.by(
          Vector2(12, 0),
          EffectController(duration: 0.1),
        ),
        MoveEffect.by(
          Vector2(-6, 0),
          EffectController(duration: 0.05),
        ),
      ]),
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      _showError = false;
      isSelected = false;
    });
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_cornerRadius),
    );

    // Background fill
    final bgColor = isMatched
        ? shapeColor.withAlpha(30)
        : shapeColor.withAlpha(isSelected ? 80 : 40);
    canvas.drawRRect(
      rrect,
      Paint()..color = bgColor,
    );

    // Border
    if (isSelected || _showError) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = _showError
              ? const Color(0xFFE88888)
              : const Color(0xFF9B82C4).withAlpha(140)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _borderWidth,
      );
    }

    // Draw shape icon in center
    _drawShape(canvas, size.x / 2, size.y / 2, size.x * 0.3);
  }

  void _drawShape(Canvas canvas, double cx, double cy, double r) {
    final paint = Paint()
      ..color = isMatched ? shapeColor.withAlpha(80) : shapeColor
      ..style = PaintingStyle.fill;

    switch (shapeType) {
      case ShapeType.star:
        _drawStar(canvas, cx, cy, r, paint);
      case ShapeType.heart:
        _drawHeart(canvas, cx, cy, r, paint);
      case ShapeType.circle:
        canvas.drawCircle(Offset(cx, cy), r, paint);
      case ShapeType.diamond:
        _drawDiamond(canvas, cx, cy, r, paint);
      case ShapeType.triangle:
        _drawTriangle(canvas, cx, cy, r, paint);
    }
  }

  void _drawStar(Canvas canvas, double cx, double cy, double r, Paint paint) {
    final path = Path();
    const points = 5;
    final innerR = r * 0.45;
    for (var i = 0; i < points * 2; i++) {
      final angle = (i * math.pi / points) - math.pi / 2;
      final radius = i.isEven ? r : innerR;
      final x = cx + radius * math.cos(angle);
      final y = cy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, double cx, double cy, double r, Paint paint) {
    final path = Path();
    final w = r * 1.1;
    final h = r * 1.1;
    path.moveTo(cx, cy + h * 0.6);
    path.cubicTo(
      cx - w * 1.2, cy - h * 0.2,
      cx - w * 0.4, cy - h * 0.9,
      cx, cy - h * 0.3,
    );
    path.cubicTo(
      cx + w * 0.4, cy - h * 0.9,
      cx + w * 1.2, cy - h * 0.2,
      cx, cy + h * 0.6,
    );
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawDiamond(
      Canvas canvas, double cx, double cy, double r, Paint paint) {
    final path = Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + r * 0.7, cy)
      ..lineTo(cx, cy + r)
      ..lineTo(cx - r * 0.7, cy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawTriangle(
      Canvas canvas, double cx, double cy, double r, Paint paint) {
    final path = Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + r * 0.87, cy + r * 0.5)
      ..lineTo(cx - r * 0.87, cy + r * 0.5)
      ..close();
    canvas.drawPath(path, paint);
  }
}
