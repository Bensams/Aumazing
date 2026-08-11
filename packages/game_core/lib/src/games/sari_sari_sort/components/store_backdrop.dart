import 'dart:ui';

import 'package:flame/components.dart';

/// The store itself: awning, a few hanging sachets, and the counter the
/// baskets stand on.
///
/// Purely decorative — it never handles a touch and is drawn behind every
/// interactive component, so the drag mechanic cannot be affected by it. Its
/// job is to tell the child *where they are*: three unmarked bins on a blank
/// field is an abstract sorting exercise, while the same three bins on a
/// counter under an awning is an errand they have run with their mother.
///
/// Deliberately flat and quiet. A real sari-sari store is a wall of packaging,
/// and reproducing that would put the busiest possible background behind the
/// one thing the child is supposed to look at. So: two muted awning tones, a
/// plain counter, and a handful of sachets confined to the margins where no
/// item or basket is ever placed. Every decorative element is low-contrast
/// against the background and high-contrast against nothing — the objects keep
/// the contrast budget.
class StoreBackdrop extends PositionComponent {
  StoreBackdrop({
    required Vector2 position,
    required Vector2 size,
    required this.awningHeight,
    required this.counterTop,
  }) : super(position: position, size: size, priority: -10);

  /// Height of the scalloped awning strip at the top of the store.
  final double awningHeight;

  /// Y (local) of the counter surface the baskets rest on.
  final double counterTop;

  // Muted, low-arousal palette. The store recedes; the objects come forward.
  static const _awningLight = Color(0xFFEFD9C0);
  static const _awningDark = Color(0xFFE0BFA0);
  static const _counter = Color(0xFFD8C4AC);
  static const _counterEdge = Color(0xFFC2A98C);
  static const _sachet = Color(0xFFE6DED2);

  @override
  void render(Canvas canvas) {
    _renderAwning(canvas);
    _renderSachets(canvas);
    _renderCounter(canvas);
  }

  /// Two-tone awning: a solid band with a scalloped lower edge.
  ///
  /// Drawn as triangles rather than an image so it costs nothing to ship and
  /// scales to any canvas — this app targets low-end Android 5.0 devices and
  /// every avoided PNG is memory a slow phone keeps.
  void _renderAwning(Canvas canvas) {
    final bandHeight = awningHeight * 0.62;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, bandHeight),
      Paint()..color = _awningLight,
    );

    // Scallops. Width is derived from the canvas so they stay a sane size on
    // both a phone and a tablet instead of multiplying on a wide screen.
    final scallopW = size.x / 12;
    final scallopH = awningHeight - bandHeight;
    final paintDark = Paint()..color = _awningDark;
    for (var i = 0; i * scallopW < size.x; i++) {
      final left = i * scallopW;
      final path = Path()
        ..moveTo(left, bandHeight)
        ..lineTo(left + scallopW, bandHeight)
        ..lineTo(left + scallopW / 2, bandHeight + scallopH)
        ..close();
      canvas.drawPath(path, i.isEven ? paintDark : (Paint()..color = _awningLight));
    }
  }

  /// Sachets on their strings, hung in the left and right margins only.
  ///
  /// The margins are the one part of the canvas the layout never places an
  /// item or a basket in, so the decoration cannot compete with, overlap or
  /// steal a touch from anything the child needs to reach.
  void _renderSachets(Canvas canvas) {
    final stringPaint = Paint()
      ..color = _counterEdge
      ..strokeWidth = 1.5;
    final sachetPaint = Paint()..color = _sachet;

    final w = size.x * 0.022;
    final h = w * 1.6;
    final top = awningHeight;

    for (final x in [size.x * 0.04, size.x * 0.96]) {
      for (var i = 0; i < 3; i++) {
        final y = top + i * h * 1.15;
        canvas.drawLine(Offset(x, top), Offset(x, y), stringPaint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - w / 2, y, w, h),
            Radius.circular(w * 0.25),
          ),
          sachetPaint,
        );
      }
    }
  }

  /// The counter: a surface line with a front face below it.
  void _renderCounter(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTWH(0, counterTop, size.x, size.y - counterTop),
      Paint()..color = _counter,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, counterTop, size.x, size.y * 0.012),
      Paint()..color = _counterEdge,
    );
  }
}
