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
/// screen background, whatever colour the parent picked for either — and is
/// the *same* colour on every card, so it never reads as a cue. See
/// [standingOutline].
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

  /// The one outline colour every ordinary object card is drawn with.
  ///
  /// Deliberately not parent-choosable, and — this is the part that matters
  /// pedagogically — deliberately **not** derived per card.
  ///
  /// An earlier version picked dark or light per card from that card's own
  /// luminance, which is the right answer if each card is judged alone and
  /// the wrong answer for a child. Cards are shown side by side, so a board
  /// could carry four dark outlines and one bright white one purely because
  /// of the fill underneath. To a child looking for the answer, the odd
  /// outline *is* the answer: a standing outline that varies reads as
  /// feedback. It is exactly the shape a "correct" cue takes.
  ///
  /// So the standing outline is a constant. Every neutral object wears the
  /// same one, and difference in outline colour is reserved for states that
  /// genuinely mean something — selected, hint, correct, wrong. See
  /// `ShapePainter3D.drawCard3D`, which is the single place it is applied.
  static const Color standingOutline = Contrast.ink;

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
  ///
  /// Three fields, unchanged: the outline colour was never stored (it was
  /// derived, and is now a constant), so making it uniform needs no format
  /// change and every value already on a device still reads back.
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
