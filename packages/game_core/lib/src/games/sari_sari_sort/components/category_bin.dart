import 'dart:math' as math;
import 'dart:ui' hide TextStyle, FontWeight;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;

import '../../../config/game_motion.dart';
import '../../shared/shape_painter_3d.dart';
import '../sari_sari_sort_game.dart' show StoreCategory;

/// A drop-target bin (basket) for one [StoreCategory] in the Sari-Sari Store
/// Sorting game.
///
/// Renders a labelled, colored basket. The owning game hit-tests dropped items
/// against [containsPoint]. Supports a pulsing hint highlight (same visual
/// language as the other Aumazing games) for idle / wrong-answer guidance.
class CategoryBin extends PositionComponent {
  CategoryBin({
    required this.category,
    required this.label,
    required this.emoji,
    required this.color,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size);

  final StoreCategory category;

  /// Filipino bin label, e.g. 'Pagkain'.
  final String label;

  /// Emoji glyph representing the basket.
  final String emoji;

  final Color color;

  bool _isHint = false;
  double _hintTime = 0.0;

  late TextPaint _emojiPaint;
  late TextPaint _labelPaint;

  static const double _cornerRadius = 24.0;

  bool get isHint => _isHint;

  void showHint() {
    _isHint = true;
    _hintTime = 0.0;
  }

  void hideHint() {
    _isHint = false;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _emojiPaint = TextPaint(
      style: TextStyle(fontSize: size.y * 0.34),
    );
    _labelPaint = TextPaint(
      style: TextStyle(
        fontSize: size.y * 0.16,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF4A4458),
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_isHint) _hintTime += dt;
  }

  @override
  void render(Canvas canvas) {
    // Pulsing hint ring (matches MatchableShape / SequenceShape).
    if (_isHint) {
      final pulse = GameMotion.reduced
          ? 1.0
          : (math.sin(_hintTime * 2 * math.pi) + 1) / 2;
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

    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    ShapePainter3D.drawCard3D(
      canvas,
      rect,
      color: color,
      cornerRadius: _cornerRadius,
      alpha: 255, // bold, fully-saturated basket color
      showBorder: true,
      borderColor: _isHint ? const Color(0xFFFFA726) : const Color(0xFFFFFFFF).withAlpha(200),
      borderWidth: _isHint ? 4.0 : 3.0,
    );

    _emojiPaint.render(
      canvas,
      emoji,
      Vector2(size.x / 2, size.y * 0.40),
      anchor: Anchor.center,
    );

    // White backing pill so the label stays legible on the bold basket color.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.x * 0.08, size.y * 0.68, size.x * 0.84, size.y * 0.22),
        Radius.circular(size.y * 0.11),
      ),
      Paint()..color = const Color(0xFFFFFFFF).withAlpha(225),
    );
    _labelPaint.render(
      canvas,
      label,
      Vector2(size.x / 2, size.y * 0.80),
      anchor: Anchor.center,
    );
  }
}
