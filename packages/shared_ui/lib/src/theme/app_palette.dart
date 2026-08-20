import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Selectable game/dashboard color themes.
///
/// Defaults are derived from the child's sex (see [GameTheme.fromSexValue]) but
/// the parent can override the choice. All palettes are ASD-friendly: natural,
/// real-world tones (sky / sage / rose / peach) kept at a calm saturation to
/// avoid sensory overload, with sufficient text contrast.
enum GameTheme {
  boy('boy', 'Boy'),
  girl('girl', 'Girl'),
  neutral('neutral', 'Neutral');

  const GameTheme(this.slug, this.label);

  final String slug;
  final String label;

  /// Maps a [GameTheme] slug back to the enum (defaults to [neutral]).
  static GameTheme fromSlug(String? slug) {
    if (slug == null) return GameTheme.neutral;
    return GameTheme.values.firstWhere(
      (t) => t.slug == slug,
      orElse: () => GameTheme.neutral,
    );
  }

  /// Derives the default theme from a `ChildProfile.sex` value
  /// ('male' / 'female' / 'prefer_not_to_say' / null).
  static GameTheme fromSexValue(String? sexValue) {
    switch (sexValue) {
      case 'male':
        return GameTheme.boy;
      case 'female':
        return GameTheme.girl;
      default:
        return GameTheme.neutral;
    }
  }
}

/// A complete set of colors for one [GameTheme], covering both the child game
/// screens and the parent dashboard.
class GamePalette {
  const GamePalette({
    required this.theme,
    required this.primary,
    required this.accent,
    required this.cardSurface,
    required this.onPrimary,
    required this.gameBackground,
    required this.parentBackground,
    this.backgroundTones = const [],
  });

  /// Returns a copy with [gameBackground] replaced and [backgroundTones]
  /// cleared, so every game shows the same background.
  ///
  /// This is how a parent's custom background reaches the game screens: they
  /// all read `activePalette.gameBackground` / `gameBackgroundFor(...)`
  /// already, so overriding here means no screen needs to know a custom
  /// background exists. Clearing the tones is deliberate — [gameBackgroundFor]
  /// falls back to [gameBackground] when fewer than two are defined, which
  /// also drops the per-game variation. A parent who picks one colour should
  /// get that colour everywhere, and a background that changes between games
  /// is exactly the kind of unpredictability the child mode avoids.
  GamePalette withGameBackground(LinearGradient background) => GamePalette(
        theme: theme,
        primary: primary,
        accent: accent,
        cardSurface: cardSurface,
        onPrimary: onPrimary,
        gameBackground: background,
        parentBackground: parentBackground,
        backgroundTones: const [],
      );

  final GameTheme theme;

  /// Main brand color for this theme — buttons, headers, active states.
  final Color primary;

  /// Secondary highlight color — chips, progress fills, secondary accents.
  final Color accent;

  /// Tint for raised cards/tiles on a themed background.
  final Color cardSurface;

  /// Readable text/icon color on top of [primary].
  final Color onPrimary;

  /// Full-bleed gradient behind child game screens.
  final LinearGradient gameBackground;

  /// Full-bleed gradient behind parent dashboard screens.
  final LinearGradient parentBackground;

  /// Soft shades within this theme's color family. Used by
  /// [gameBackgroundFor] to give each game a distinct-but-on-theme background.
  final List<Color> backgroundTones;

  /// A per-game background gradient that stays within the theme's family.
  ///
  /// Each [gameId] deterministically maps to a different pair of
  /// [backgroundTones] (with a calm off-white centre), so games look varied
  /// without leaving the selected theme. Falls back to [gameBackground] when
  /// no tones are defined.
  LinearGradient gameBackgroundFor(String gameId) {
    final n = backgroundTones.length;
    if (n < 2) return gameBackground;
    // Two independent hashes give a well-spread (a, b) tone pair per game.
    final a = _hash(gameId, 1000003) % n;
    final raw = _hash(gameId, 137) % (n - 1);
    final b = raw < a ? raw : raw + 1; // maps around a → guarantees b != a
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [backgroundTones[a], const Color(0xFFFAF9F6), backgroundTones[b]],
    );
  }

  /// Platform-stable string hash (Dart's String.hashCode is not guaranteed
  /// stable across runs), so a game always gets the same background.
  static int _hash(String s, int mult) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * mult + c) & 0x7fffffff;
    }
    return h;
  }
}

/// Catalogue of the three built-in palettes.
abstract final class GamePalettes {
  // ── Boy — natural sea mist (calm, ASD-friendly) ──────────────────────
  // A single flat natural tone rather than a gradient: predictable and calm,
  // and it never buries a game shape behind a shifting blend. Expressed as a
  // two-stop gradient of one colour so every consumer keeps treating the
  // background as a [LinearGradient]. Tones are left empty so all games share
  // the same flat colour.
  static const GamePalette boy = GamePalette(
    theme: GameTheme.boy,
    primary: Color(0xFF5E94B5), // muted ocean blue
    accent: Color(0xFF6FAE97), // sage green
    cardSurface: Color(0xFFEAF3F8),
    onPrimary: Color(0xFFFFFFFF),
    gameBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFDCEFE6), Color(0xFFDCEFE6)], // soft sea mist
    ),
    parentBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFE1F1EA), Color(0xFFE1F1EA)], // soft sage mist
    ),
  );

  // ── Girl — natural peach cream (calm, ASD-friendly) ──────────────────
  static const GamePalette girl = GamePalette(
    theme: GameTheme.girl,
    primary: Color(0xFFCB7E97), // muted rose
    accent: Color(0xFFE0A98C), // soft peach/coral
    cardSurface: Color(0xFFF9E9EE),
    onPrimary: Color(0xFFFFFFFF),
    gameBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFBE6DC), Color(0xFFFBE6DC)], // soft peach cream
    ),
    parentBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFBEAE2), Color(0xFFFBEAE2)], // soft rose cream
    ),
  );

  // ── Neutral — natural soft lavender ──────────────────────────────────
  static const GamePalette neutral = GamePalette(
    theme: GameTheme.neutral,
    primary: AppColors.primaryPurple,
    accent: AppColors.mint,
    cardSurface: Color(0xFFF1ECFA),
    onPrimary: Color(0xFFFFFFFF),
    gameBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFECE5FB), Color(0xFFECE5FB)], // soft lavender
    ),
    parentBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFECE5FB), Color(0xFFECE5FB)], // soft lavender
    ),
  );

  /// Returns the palette for [theme].
  static GamePalette of(GameTheme theme) {
    switch (theme) {
      case GameTheme.boy:
        return boy;
      case GameTheme.girl:
        return girl;
      case GameTheme.neutral:
        return neutral;
    }
  }
}

/// Holds the currently-selected [GameTheme] and notifies listeners on change.
///
/// Create one near the app root and expose it via [AppThemeScope]. Default it
/// from the child's sex with [setFromSex]; let the parent override with
/// [setTheme].
class AppThemeController extends ChangeNotifier {
  AppThemeController([GameTheme initial = GameTheme.neutral]) : _theme = initial;

  GameTheme _theme;

  GameTheme get theme => _theme;

  /// The active palette for the selected theme.
  GamePalette get palette => GamePalettes.of(_theme);

  /// Explicitly set the theme (parent override).
  void setTheme(GameTheme theme) {
    if (theme == _theme) return;
    _theme = theme;
    notifyListeners();
  }

  /// Default the theme from a `ChildProfile.sex` value.
  void setFromSex(String? sexValue) =>
      setTheme(GameTheme.fromSexValue(sexValue));
}

/// Inherited access to the [AppThemeController] / active [GamePalette].
///
/// ```dart
/// final palette = AppThemeScope.paletteOf(context);
/// Container(decoration: BoxDecoration(gradient: palette.gameBackground));
/// ```
class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller from the nearest [AppThemeScope].
  static AppThemeController controllerOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'No AppThemeScope found in the widget tree.');
    return scope!.notifier!;
  }

  /// The active palette from the nearest [AppThemeScope].
  static GamePalette paletteOf(BuildContext context) =>
      controllerOf(context).palette;
}
