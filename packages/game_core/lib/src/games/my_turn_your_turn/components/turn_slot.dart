
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import 'package:shared_ui/shared_ui.dart';
import '../../../config/game_motion.dart';
import '../../shared/shape_painter_3d.dart';

/// A slot in the turn-taking grid.
class TurnSlot extends PositionComponent with TapCallbacks {
  TurnSlot({
    required this.slotIndex,
    required this.onTapped,
    this.onTappedWhileDisabled,
    super.position,
    super.size,
  });

  final int slotIndex;
  final void Function(int index) onTapped;

  /// Called when the slot is tapped while [inputEnabled] is false (buddy's turn)
  /// and the slot is not yet filled. Used to record impulse-control errors.
  final void Function(int slotIndex)? onTappedWhileDisabled;

  bool isFilled = false;
  bool isBuddy = false; // true = filled by buddy, false = filled by child
  Color fillColor = AppColors.lavender;
  String fillEmoji = ''; // emoji shown once filled (buddy or child avatar)
  bool inputEnabled = false;

  // ── Hint state ─────────────────────────────────────────────────────
  bool _isHint = false;
  double _hintTime = 0.0; // time accumulator for pulsing animation

  set isHint(bool v) {
    _isHint = v;
    _hintTime = 0.0;
  }

  bool get isHint => _isHint;

  void showHint() {
    isHint = true;
  }

  void hideHint() {
    isHint = false;
  }

  static const double _cornerRadius = 20.0;

  @override
  void onTapDown(TapDownEvent event) {
    if (isFilled) return;
    if (!inputEnabled) {
      onTappedWhileDisabled?.call(slotIndex);
      return;
    }
    onTapped(slotIndex);
  }

  /// Fills the slot with a piece (buddy or child avatar), showing [emoji].
  void fill({
    required Color color,
    required String emoji,
    required bool isBuddy,
  }) {
    isFilled = true;
    this.isBuddy = isBuddy;
    fillColor = color;
    fillEmoji = emoji;
    add(ScaleEffect.by(
      Vector2.all(1.08),
      EffectController(
        duration: 0.18,
        reverseDuration: 0.14,
        curve: Curves.easeInOut,
      ),
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
  void update(double dt) {
    super.update(dt);
    if (_isHint) {
      _hintTime += dt;
    }
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

      // Emoji indicator (buddy piece or child's avatar)
      final label = fillEmoji;
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
      // Hint indicator — pulsing orange ring (same style as SequenceShape)
      if (_isHint) {
        final pulseAlpha = GameMotion.reduced
            ? 240
            : (128 + 127 * math.sin(_hintTime * 2 * math.pi))
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
