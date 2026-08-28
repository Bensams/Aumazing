import 'dart:ui';

/// Makes a game's *focus object* — the thing a child is meant to look at and
/// act on — read louder than the tile or background behind it.
///
/// Geometric shapes get a halo + contour in [ShapePainter3D]: a hard edge is
/// exactly right for a star or a triangle. Glyphs and bundled illustrations
/// cannot take that treatment — a keyline mangles a multi-colour emoji and
/// boxes in a photo-like picture — so they get the softer lift here: a drop
/// shadow that separates the object from its background without touching the
/// object itself.
///
/// The point in both cases is the same, and is the whole reason this exists:
/// the object should be the loudest thing in its cell, so a child focuses on
/// the picture or symbol rather than the square it sits on.
abstract final class ObjectEmphasis {
  /// Drop shadow for an emoji / symbol glyph, applied through
  /// [TextStyle.shadows]. Sized off [fontSize] so it scales with the glyph and
  /// stays a soft lift rather than a hard outline.
  static List<Shadow> glyphShadows(double fontSize) => [
        Shadow(
          color: const Color(0x4D000000),
          blurRadius: fontSize * 0.11,
          offset: Offset(0, fontSize * 0.05),
        ),
      ];

  /// Soft drop shadow behind a square picture occupying [rect]. Call it right
  /// before drawing the picture, so a bundled illustration lifts off the card
  /// or background under it. [radius] rounds the shadow to match the art.
  ///
  /// Only for a real, box-filling picture — not a painted/schematic fallback,
  /// whose subject does not fill the square, where a rectangular shadow would
  /// read as a floating box rather than the object's own shadow.
  static void drawArtShadow(Canvas canvas, Rect rect, {double radius = 0}) {
    final shadowRect = rect.translate(0, rect.height * 0.02);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shadowRect, Radius.circular(radius)),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rect.shortestSide * 0.05),
    );
  }
}
