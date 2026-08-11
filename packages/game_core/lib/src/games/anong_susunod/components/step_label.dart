import 'dart:ui';

import 'package:flutter/painting.dart' show TextPainter, TextSpan;
import 'package:flutter/painting.dart' as painting;

/// Draws a routine step's printed name, cached between frames.
///
/// The label is laid out once per (text, width, size) and reused: a Flame
/// component renders every frame, and re-laying out four short strings sixty
/// times a second is measurable work for a result that never changes while a
/// card sits still.
///
/// Shared by [RoutineCard] and [SequenceSlot] so a step reads identically in
/// the tray and in the slot it lands in — a word that changed size or wrapped
/// differently on placement would look like a different word.
class StepLabel {
  TextPainter? _painter;
  String? _text;
  double _width = -1;
  double _fontSize = -1;

  /// Two lines is the ceiling: "Kumain ng almusal" needs the second, and a
  /// third would push the picture down to where it stops being the main thing
  /// on the card.
  static const int maxLines = 2;

  static const Color _ink = Color(0xFF3F3B4A);

  TextPainter _layout(String text, double width, double fontSize) {
    final cached = _painter;
    if (cached != null &&
        _text == text &&
        _width == width &&
        _fontSize == fontSize) {
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: painting.TextStyle(
          color: _ink,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: width);
    _painter = painter;
    _text = text;
    _width = width;
    _fontSize = fontSize;
    return painter;
  }

  /// Paints [text] centred inside the box at [origin] of [width] × [height].
  void paint(
    Canvas canvas,
    String text, {
    required Offset origin,
    required double width,
    required double height,
    required double fontSize,
  }) {
    if (text.isEmpty || width <= 0) return;
    final painter = _layout(text, width, fontSize);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(origin.dx, origin.dy, width, height));
    painter.paint(
      canvas,
      Offset(
        origin.dx + (width - painter.width) / 2,
        origin.dy + (height - painter.height) / 2,
      ),
    );
    canvas.restore();
  }
}
