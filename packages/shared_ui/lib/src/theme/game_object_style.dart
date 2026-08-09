import 'package:flutter/material.dart';

import 'contrast.dart';

/// How the outline around a game object card is drawn.
enum ObjectOutline {
  none('none', 'None'),
  solid('solid', 'Solid'),
  dashed('dashed', 'Dashed');

  const ObjectOutline(this.slug, this.label);

  final String slug;
  final String label;

  static ObjectOutline? fromSlug(String? slug) {
    for (final o in values) {
      if (o.slug == slug) return o;
    }
    return null;
  }
}

/// Parent-configurable appearance of the cards behind game objects — the
/// tiles under each shape, picture and item.
///
/// This exists because of how the cards were originally drawn. `drawCard3D`
/// fills with `shapeColour.withAlpha(40)`, i.e. the card is a 16% tint of the
/// very shape sitting on it, so the two share a hue *and* land on nearly the
/// same luminance. The gold star measured 1.00:1 against its own card — not
/// low contrast, none at all.
///
/// Giving the card a colour of its own, independent of the shape, fixes that
/// at source. The outline then guarantees the card is separable from the
/// screen background, whatever colour the parent picked for either.
@immutable
class GameObjectStyle {
  const GameObjectStyle({
    this.cardColour,
    this.outline = ObjectOutline.solid,
    this.outlineWidth = 3,
  });

  /// The globally active style. Set from the child's saved preferences when a
  /// game screen starts, mirroring how [GameMotion] is applied — Flame
  /// components render outside the widget tree and cannot read a Provider.
  static GameObjectStyle current = const GameObjectStyle();

  /// Fixed colour for every object card, or null to keep the original
  /// behaviour of tinting the card with the object's own colour.
  final Color? cardColour;

  final ObjectOutline outline;

  /// Stroke width in logical pixels. Clamped to [minWidth]–[maxWidth] on use.
  final double outlineWidth;

  static const double minWidth = 1;
  static const double maxWidth = 8;

  /// Deliberately not parent-choosable.
  ///
  /// The outline's entire job is to guarantee separation; letting it be
  /// picked would let it be picked badly, which is the one thing it must
  /// never be. Derived from the surface it sits on instead, so it is correct
  /// by construction on any background.
  static const Color darkOutline = Color(0xFF1A1A1F);
  static const Color lightOutline = Color(0xFFFAFAFA);

  /// An outline colour guaranteed to clear 3:1 against [surface].
  ///
  /// The threshold is 0.2 because black clears 3:1 on anything with
  /// luminance ≥ 0.1 and white clears it on anything ≤ 0.3 — picking 0.2
  /// sits inside both bands, so every possible surface is covered with room
  /// to spare.
  static Color outlineColourFor(Color surface) =>
      Contrast.relativeLuminance(surface) > 0.2 ? darkOutline : lightOutline;

  double get effectiveWidth => outlineWidth.clamp(minWidth, maxWidth);

  bool get hasOutline => outline != ObjectOutline.none;

  GameObjectStyle copyWith({
    Color? cardColour,
    bool clearCardColour = false,
    ObjectOutline? outline,
    double? outlineWidth,
  }) =>
      GameObjectStyle(
        cardColour: clearCardColour ? null : (cardColour ?? this.cardColour),
        outline: outline ?? this.outline,
        outlineWidth: outlineWidth ?? this.outlineWidth,
      );

  /// Serialised for SharedPreferences, e.g. `solid|3.0|ffffffff`.
  String encode() {
    final colour = cardColour == null
        ? '-'
        : cardColour!.toARGB32().toRadixString(16).padLeft(8, '0');
    return '${outline.slug}|$outlineWidth|$colour';
  }

  /// Inverse of [encode]; null for anything unparseable so a corrupt stored
  /// value falls back to the default rather than breaking a game launch.
  static GameObjectStyle? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    final outline = ObjectOutline.fromSlug(parts[0]);
    final width = double.tryParse(parts[1]);
    if (outline == null || width == null) return null;
    Color? colour;
    if (parts[2] != '-') {
      final v = int.tryParse(parts[2], radix: 16);
      if (v == null) return null;
      colour = Color(v);
    }
    return GameObjectStyle(
      cardColour: colour,
      outline: outline,
      outlineWidth: width,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GameObjectStyle &&
      other.cardColour == cardColour &&
      other.outline == outline &&
      other.outlineWidth == outlineWidth;

  @override
  int get hashCode => Object.hash(cardColour, outline, outlineWidth);
}
