import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';

import 'package:shared_ui/shared_ui.dart';
import '../../shared/shape_painter_3d.dart';

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

  // ── Hint state ─────────────────────────────────────────────────────
  bool _isHint = false;
  double _hintTime = 0.0;

  /// Whether this shape is currently showing a visual hint.
  bool get isHint => _isHint;

  /// Sets the hint state and resets the animation timer.
  set isHint(bool v) {
    _isHint = v;
    if (v) {
      _hintTime = 0.0;
    }
  }

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

  void showHint() {
    isHint = true;
  }

  void hideHint() {
    isHint = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_isHint) {
      _hintTime += dt;
    }
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    int bgAlpha = 40;
    if (showingCorrect) bgAlpha = 120;
    if (showingWrong) bgAlpha = 100;
    if (_isHint) bgAlpha = 80;

    Color? borderColor;
    if (showingCorrect) borderColor = AppColors.mint;
    if (showingWrong) borderColor = const Color(0xFFE88888);
    if (_isHint) borderColor = const Color(0xFFFFA726);

    // Hint pulsing ring (same pattern as SequenceShape)
    if (_isHint) {
      final pulse = (math.sin(_hintTime * 2 * math.pi) + 1) / 2; // 0..1
      final pulseAlpha = (128 + 127 * pulse).round().clamp(0, 255);
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
      alpha: bgAlpha,
      showBorder: showingCorrect || showingWrong || _isHint,
      borderColor: borderColor,
    );

    // 3D shape in center
    ShapePainter3D.drawByName(
      canvas, shapeType, size.x / 2, size.y / 2, size.x * 0.3, shapeColor,
    );
  }
}
