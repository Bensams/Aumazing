import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Scene themes for the child's "My Path" progression row.
///
/// Deliberately narrower than [GameTheme]: a world skins only the *trail*, the
/// *step badges* and the *backdrop* behind the row. It never repaints a game
/// card's own gradient — those colors come from `GameEntry.gradientColors` and
/// are the child's learned cue for which game is which. Recoloring them per
/// world would destroy that cue, which is a regression for an ASD child, not
/// decoration.
///
/// [classic] reproduces the pre-world look exactly, so a child whose parent has
/// not chosen a world sees no change at all.
enum WorldTheme {
  classic('classic', 'Classic'),
  nightSky('night_sky', 'Night Sky');

  const WorldTheme(this.slug, this.label);

  final String slug;
  final String label;

  /// Maps a slug back to the enum (defaults to [classic]).
  static WorldTheme fromSlug(String? slug) {
    if (slug == null) return WorldTheme.classic;
    return WorldTheme.values.firstWhere(
      (w) => w.slug == slug,
      orElse: () => WorldTheme.classic,
    );
  }
}

/// Which backdrop the painter draws behind the path row.
enum WorldBackdropKind {
  /// No panel — the lobby gradient shows through (the classic look).
  none,

  /// A static star field over a deep gradient, with a planet edge below.
  stars,
}

/// The colors and backdrop for one [WorldTheme].
///
/// Two distinct surfaces are being styled and they need opposite treatments:
/// the **trail** sits on the backdrop panel (dark in a night world, so the
/// trail must be light), while the **badges** sit on the pastel game cards
/// (light, so the badges must stay dark). Getting these the same way round is
/// the easiest mistake to make here.
class WorldStyle {
  const WorldStyle({
    required this.theme,
    required this.kind,
    required this.trailTravelled,
    required this.trailAhead,
    required this.badgeCurrent,
    required this.badgeAvailable,
    required this.badgeLocked,
    required this.badgeDone,
    required this.currentRing,
    required this.platformShade,
    required this.labelOnScene,
    this.backdropGradient = const [],
    this.backdropAsset,
  });

  final WorldTheme theme;

  /// Selects the backdrop painter.
  final WorldBackdropKind kind;

  /// Trail behind the child — ground already covered.
  final Color trailTravelled;

  /// Trail ahead of the child — drawn dashed.
  final Color trailAhead;

  /// Fill of the current step's badge (sits on a pastel card).
  final Color badgeCurrent;

  /// Fill of an unlocked-but-not-current step's badge.
  final Color badgeAvailable;

  /// Fill of a locked step's badge.
  final Color badgeLocked;

  /// Fill of a completed step's badge.
  final Color badgeDone;

  /// Ring around the current step's platform, and its badge outline.
  final Color currentRing;

  /// Underside of a step platform — the rock it floats on. Darker than the
  /// scene so the platform reads as solid rather than painted onto the sky.
  final Color platformShade;

  /// Game-name text sitting directly on the scene (not on a card), so it has
  /// to contrast with the backdrop rather than with a pastel surface.
  final Color labelOnScene;

  /// Gradient of the backdrop panel. Empty means no panel is drawn.
  final List<Color> backdropGradient;

  /// Optional illustration layered over the painted backdrop.
  ///
  /// Null until artwork exists. When set, it must also be declared in
  /// `packages/shared_ui/pubspec.yaml`; a missing or unreadable file is
  /// swallowed by `WorldBackdrop` and the painted layer stands alone, so a
  /// half-finished asset drop can never take the path off screen.
  final String? backdropAsset;

  /// True when this world draws a panel behind the row.
  bool get hasBackdrop =>
      kind != WorldBackdropKind.none && backdropGradient.length >= 2;
}

/// Catalogue of the built-in worlds.
abstract final class WorldStyles {
  /// Today's look, unchanged — the default when no world is chosen.
  static const WorldStyle classic = WorldStyle(
    theme: WorldTheme.classic,
    kind: WorldBackdropKind.none,
    trailTravelled: Color(0xD99B82C4), // primaryPurple @ 85%
    trailAhead: Color(0x738A8A9B), // mutedForeground @ 45%
    badgeCurrent: AppColors.primaryPurple,
    badgeAvailable: AppColors.primaryPurple,
    badgeLocked: AppColors.mutedForeground,
    badgeDone: Color(0xFF43A047),
    currentRing: AppColors.white,
    platformShade: Color(0xFF8E7FB4), // muted purple rock
    labelOnScene: AppColors.foreground, // dark text on the pastel lobby
  );

  /// Deep indigo sky with a static star field and a planet edge.
  ///
  /// The trail turns warm gold so it separates from both the blue-violet
  /// backdrop and the white stars; badges stay dark because they sit on the
  /// light game cards, not on the sky.
  static const WorldStyle nightSky = WorldStyle(
    theme: WorldTheme.nightSky,
    kind: WorldBackdropKind.stars,
    trailTravelled: Color(0xFFFFD27D), // warm gold — covered ground
    trailAhead: Color(0x8CBBC6E8), // pale blue @ 55% — still ahead
    badgeCurrent: Color(0xFF3B2E63), // deep indigo on a pastel card
    badgeAvailable: Color(0xFF4C3F7A),
    badgeLocked: AppColors.mutedForeground,
    badgeDone: Color(0xFF2E7D46),
    currentRing: Color(0xFFFFD27D),
    platformShade: Color(0xFF3A2F5E), // deep violet rock underside
    labelOnScene: Color(0xFFE6E2F5), // near-white on the night sky
    backdropGradient: [
      Color(0xFF1B1B3A), // near-black indigo
      Color(0xFF2D2456),
      Color(0xFF43356E), // violet, lifting toward the horizon
    ],
  );

  /// Returns the style for [theme].
  static WorldStyle of(WorldTheme theme) {
    switch (theme) {
      case WorldTheme.classic:
        return classic;
      case WorldTheme.nightSky:
        return nightSky;
    }
  }
}
