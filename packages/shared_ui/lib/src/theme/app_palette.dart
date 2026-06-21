import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_gradients.dart';

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
  });

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
}

/// Catalogue of the three built-in palettes.
abstract final class GamePalettes {
  // ── Boy — natural ocean & sage (calm, ASD-friendly) ──────────────────
  static const GamePalette boy = GamePalette(
    theme: GameTheme.boy,
    primary: Color(0xFF5E94B5), // muted ocean blue
    accent: Color(0xFF6FAE97), // sage green
    cardSurface: Color(0xFFEAF3F8),
    onPrimary: Color(0xFFFFFFFF),
    gameBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFD9EAF3), Color(0xFFFAF9F6), Color(0xFFDDEFE6)],
    ),
    parentBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFE3F0F7), Color(0xFFFAF9F6), Color(0xFFE4F2EC)],
    ),
  );

  // ── Girl — natural rose & peach (calm, ASD-friendly) ─────────────────
  static const GamePalette girl = GamePalette(
    theme: GameTheme.girl,
    primary: Color(0xFFCB7E97), // muted rose
    accent: Color(0xFFE0A98C), // soft peach/coral
    cardSurface: Color(0xFFF9E9EE),
    onPrimary: Color(0xFFFFFFFF),
    gameBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF7E1E8), Color(0xFFFAF9F6), Color(0xFFFBE8DD)],
    ),
    parentBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF8E6EC), Color(0xFFFAF9F6), Color(0xFFFBEDE4)],
    ),
  );

  // ── Neutral — the existing lavender & mint pastel ────────────────────
  static const GamePalette neutral = GamePalette(
    theme: GameTheme.neutral,
    primary: AppColors.primaryPurple,
    accent: AppColors.mint,
    cardSurface: Color(0xFFF1ECFA),
    onPrimary: Color(0xFFFFFFFF),
    gameBackground: AppGradients.matchIt,
    parentBackground: AppGradients.parentLavenderMint,
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
