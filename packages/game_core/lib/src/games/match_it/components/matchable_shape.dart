import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';

import '../../shared/shape_painter_3d.dart';

/// The shape type drawn on each matchable card.
enum ShapeType { star, heart, circle, diamond, triangle }

/// A large, ASD-friendly tappable shape component for the Match It game.
///
/// Renders a colored rounded-rect card with a centered 3D shape icon.
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

    // Card background
    final bgAlpha = isMatched ? 30 : (isSelected ? 80 : 40);
    Color? borderColor;
    if (_showError) borderColor = const Color(0xFFE88888);
    if (isSelected && !_showError) {
      borderColor = const Color(0xFF9B82C4).withAlpha(140);
    }

    ShapePainter3D.drawCard3D(
      canvas,
      rect,
      color: shapeColor,
      cornerRadius: _cornerRadius,
      alpha: bgAlpha,
      showBorder: isSelected || _showError,
      borderColor: borderColor,
      borderWidth: _borderWidth,
    );

    // 3D shape icon in center
    final drawColor = isMatched ? shapeColor.withAlpha(80) : shapeColor;
    final shapeName = shapeType.name; // enum name matches shape_painter_3d keys
    ShapePainter3D.drawByName(
      canvas, shapeName, size.x / 2, size.y / 2, size.x * 0.3, drawColor,
    );
  }
}
