import 'package:flutter/material.dart';

import 'contrast.dart';

/// The colours Match It paints its shapes in.
///
/// Mirrors `MatchItGame.allPairs` in game_core. shared_ui cannot import
/// game_core (the dependency runs the other way), so the list is duplicated
/// here and held in sync by a test in game_core — if a shape colour is added
/// or changed there without updating this list, that test fails.
///
/// This is the set a parent-chosen background is scored against: it is the
/// densest concentration of coloured game art in the app, and the game where
/// telling two shapes apart *is* the task.
abstract final class GameArtColors {
  static const List<Color> matchItShapes = [
    Color(0xFFFFB300), // gold
    Color(0xFFFB8C00), // orange
    Color(0xFFE53935), // red
    Color(0xFF8E24AA), // purple
    Color(0xFFEC407A), // pink
    Color(0xFF43A047), // green
    Color(0xFF1E88E5), // blue
    Color(0xFFD500F9), // magenta
    Color(0xFF00ACC1), // teal
    Color(0xFFFDD835), // yellow
  ];
}

/// Whether a custom background is one flat colour or a two-colour blend.
enum ChildBackgroundKind {
  solid('solid'),
  gradient('gradient');

  const ChildBackgroundKind(this.slug);

  final String slug;

  static ChildBackgroundKind? fromSlug(String? slug) {
    for (final k in values) {
      if (k.slug == slug) return k;
    }
    return null;
  }
}

/// A parent-chosen background for their child's game screens.
///
/// Deliberately narrow: one colour, or two blended corner-to-corner. The
/// three-stop theme gradients exist for the built-in presets; a parent
/// building their own does not need that many degrees of freedom, and every
/// extra stop is another chance to bury a shape.
@immutable
class ChildBackground {
  const ChildBackground.solid(Color colour)
      : kind = ChildBackgroundKind.solid,
        start = colour,
        end = colour;

  const ChildBackground.gradient(this.start, this.end)
      : kind = ChildBackgroundKind.gradient;

  const ChildBackground._(this.kind, this.start, this.end);

  final ChildBackgroundKind kind;
  final Color start;

  /// Equal to [start] for a solid background.
  final Color end;

  /// The gradient the game screens actually paint.
  ///
  /// A solid background is expressed as a two-stop gradient of the same
  /// colour rather than a separate code path, so every consumer can keep
  /// treating the background as a [LinearGradient].
  LinearGradient toGradient() => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [start, end],
      );

  /// The distinct colours a shape can be seen against — one for a solid
  /// background, both ends for a gradient.
  List<Color> get sampleColours =>
      kind == ChildBackgroundKind.solid ? [start] : [start, end];

  /// Worst-case contrast between the Match It shape colours and this
  /// background.
  double get worstShapeContrast => Contrast.worstCase(
        foregrounds: GameArtColors.matchItShapes,
        backgrounds: sampleColours,
      );

  /// How many of the ten Match It shapes clear 3:1 against this background.
  ///
  /// Reported instead of a pass/fail flag because **no background can score
  /// ten**. Purple (`#8E24AA`, luminance 0.099) only clears 3:1 on a
  /// background lighter than luminance 0.397; yellow (`#FDD835`, luminance
  /// 0.703) only clears it on one darker than 0.201. Those bands do not
  /// overlap, so the shape set cannot be made fully legible by choosing a
  /// background at all — it needs the per-shape outline that
  /// `MatchableShape` currently draws only when selected.
  ///
  /// Until that lands, this count is the honest measure: higher is better,
  /// ten is unreachable.
  int get shapesClearingMinimum => GameArtColors.matchItShapes
      .where((s) => sampleColours.every((b) =>
          Contrast.contrastRatio(s, b) >= Contrast.graphicalObjectMinimum))
      .length;

  /// Best achievable count, for rendering "7 of 10" honestly.
  static int get totalShapes => GameArtColors.matchItShapes.length;

  ChildBackground copyWith({
    ChildBackgroundKind? kind,
    Color? start,
    Color? end,
  }) =>
      ChildBackground._(
        kind ?? this.kind,
        start ?? this.start,
        end ?? this.end,
      );

  /// Serialised for SharedPreferences, e.g. `gradient:ffa9e3cc,ffabd2f0`.
  String encode() =>
      '${kind.slug}:${_hex(start)}${kind == ChildBackgroundKind.gradient ? ',${_hex(end)}' : ''}';

  /// Inverse of [encode]. Returns null for anything unparseable so a corrupt
  /// or older stored value falls back to the preset theme rather than
  /// throwing on startup.
  static ChildBackground? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final kind = ChildBackgroundKind.fromSlug(parts[0]);
    if (kind == null) return null;
    final colours = parts[1].split(',').map(_parseHex).toList();
    if (colours.any((c) => c == null)) return null;
    if (kind == ChildBackgroundKind.solid) {
      return colours.length == 1 ? ChildBackground.solid(colours[0]!) : null;
    }
    return colours.length == 2
        ? ChildBackground.gradient(colours[0]!, colours[1]!)
        : null;
  }

  static String _hex(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0');

  static Color? _parseHex(String s) {
    final v = int.tryParse(s, radix: 16);
    return v == null ? null : Color(v);
  }

  @override
  bool operator ==(Object other) =>
      other is ChildBackground &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}

/// Ready-made colours offered as one-tap circles beside the wheel.
///
/// These are not "safe" colours — as [ChildBackground.shapesClearingMinimum]
/// explains, no single colour makes every shape legible. They are the *best
/// available* choices, and they are deliberately ordered worst-to-best by
/// shape legibility so the ordering itself is informative.
///
/// For reference, the current preset theme gradients score 1–3 of 10. Every
/// swatch here beats them, and the dark options score 9 of 10 — only purple
/// fails, because purple is the one shape that needs a *light* background.
/// A test pins these scores so a future colour tweak cannot quietly make
/// things worse.
abstract final class ChildBackgroundSwatches {
  static const List<({String name, Color colour})> ready = [
    // Light — calm and low-glare, but the yellow/gold/orange/teal shapes
    // wash out against them.
    (name: 'Pale lilac', colour: Color(0xFFEDE7F6)),
    (name: 'Pale sky', colour: Color(0xFFE3EFF8)),
    (name: 'Pale mint', colour: Color(0xFFE4F2E9)),
    (name: 'Warm sand', colour: Color(0xFFF4EDE0)),
    (name: 'Soft grey', colour: Color(0xFFECECEF)),
    (name: 'Soft white', colour: Color(0xFFFAF9F6)),
    // Dark — markedly better for telling shapes apart, and lower glare on a
    // bright screen. Offered because the measurement supports them, not
    // because they are the expected look.
    (name: 'Dark slate', colour: Color(0xFF27333A)),
    (name: 'Charcoal', colour: Color(0xFF2E2E33)),
    (name: 'Deep navy', colour: Color(0xFF1E2438)),
  ];
}
