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

  /// Fraction of the basket width given over to the picture; the rest is the
  /// word.
  ///
  /// Picture *and* word, side by side, because the two readings of a basket are
  /// not interchangeable: a child who cannot yet read has only the picture, and
  /// a child who is learning to read needs the word paired with the picture
  /// often enough for the pairing to stick. Stacking them vertically was the
  /// old arrangement and it forced the word into whatever height was left over.
  static const double _pictureFraction = 0.36;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _emojiPaint = TextPaint(
      style: TextStyle(fontSize: size.y * 0.46),
    );
    _labelPaint = TextPaint(
      style: TextStyle(
        // Sized against the basket's own height rather than a fixed point size,
        // so the word grows with the basket instead of the basket having to
        // accommodate a word that never changes.
        fontSize: size.y * 0.30,
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

    // Picture on the left, word on the right, both vertically centred.
    _emojiPaint.render(
      canvas,
      emoji,
      Vector2(size.x * _pictureFraction / 2, size.y / 2),
      anchor: Anchor.center,
    );

    // White backing pill so the label stays legible on the bold basket color.
    final pillLeft = size.x * _pictureFraction;
    final pillWidth = size.x * (1 - _pictureFraction) - size.x * 0.06;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pillLeft, size.y * 0.22, pillWidth, size.y * 0.56),
        Radius.circular(size.y * 0.28),
      ),
      Paint()..color = const Color(0xFFFFFFFF).withAlpha(225),
    );
    _labelPaint.render(
      canvas,
      label,
      Vector2(pillLeft + pillWidth / 2, size.y / 2),
      anchor: Anchor.center,
    );
  }
}
