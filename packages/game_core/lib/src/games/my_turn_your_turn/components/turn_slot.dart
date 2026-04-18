import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import 'package:shared_ui/shared_ui.dart';
import '../../shared/shape_painter_3d.dart';

/// A slot in the turn-taking grid.
class TurnSlot extends PositionComponent with TapCallbacks {
  TurnSlot({
    required this.slotIndex,
    required this.onTapped,
    super.position,
    super.size,
  });

  final int slotIndex;
  final void Function(int index) onTapped;

  bool isFilled = false;
  bool isBuddy = false; // true = filled by buddy, false = filled by child
  Color fillColor = AppColors.lavender;
  bool inputEnabled = false;

  static const double _cornerRadius = 20.0;

  @override
  void onTapDown(TapDownEvent event) {
    if (!inputEnabled || isFilled) return;
    onTapped(slotIndex);
  }

  void fillByBuddy(Color color) {
    isFilled = true;
    isBuddy = true;
    fillColor = color;
    add(ScaleEffect.by(
      Vector2.all(1.05),
      EffectController(
        duration: 0.2,
        reverseDuration: 0.2,
        curve: Curves.easeInOut,
      ),
    ));
  }

  void fillByChild(Color color) {
    isFilled = true;
    isBuddy = false;
    fillColor = color;
    add(ScaleEffect.by(
      Vector2.all(1.08),
      EffectController(duration: 0.15, curve: Curves.easeOut),
    ));
  }

  void showEarlyTapWarning() {
    add(SequenceEffect([
      MoveEffect.by(Vector2(4, 0), EffectController(duration: 0.04)),
      MoveEffect.by(Vector2(-8, 0), EffectController(duration: 0.08)),
      MoveEffect.by(Vector2(4, 0), EffectController(duration: 0.04)),
    ]));
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    if (isFilled) {
      // 3D filled card
      ShapePainter3D.drawCard3D(
        canvas,
        rect,
        color: fillColor,
        cornerRadius: _cornerRadius,
        alpha: 160,
      );

      // Emoji indicator
      final label = isBuddy ? '🐻' : '⭐';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: size.x * 0.32),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(size.x / 2 - tp.width / 2, size.y / 2 - tp.height / 2),
      );
    } else {
      // 3D recessed empty slot
      final rrect = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(_cornerRadius),
      );

      // Inset shadow (darker inside)
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0x18000000),
              Color(0x08E8E4F0),
              Color(0x20FFFFFF),
            ],
            stops: [0.0, 0.5, 1.0],
          ).createShader(rect),
      );

      // Subtle border
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = AppColors.lavender.withAlpha(80)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      // Inner shadow top-left for depth
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(2, 2, size.x - 4, size.y - 4),
          const Radius.circular(_cornerRadius - 2),
        ),
        Paint()
          ..color = const Color(0x0C000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 4),
      );
    }
  }
}
