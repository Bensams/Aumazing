import 'package:flutter/material.dart';

/// Supported in-app languages.
///
/// Curated (human-translated) localization — not runtime machine translation —
/// so wording stays correct and the app remains offline-first. Matches the
/// `en` / `tl` / `ceb` voice-over folders in shared_audio.
enum GameLanguage {
  english('en', 'English'),
  tagalog('tl', 'Tagalog'),
  cebuano('ceb', 'Cebuano');

  const GameLanguage(this.slug, this.label);

  /// Code used for asset folders / persistence (en, tl, ceb).
  final String slug;

  /// Human-readable name shown in the picker.
  final String label;

  static GameLanguage fromSlug(String? slug) {
    if (slug == null) return GameLanguage.english;
    return GameLanguage.values.firstWhere(
      (l) => l.slug == slug,
      orElse: () => GameLanguage.english,
    );
  }
}

/// Typed access to all localized strings for one [GameLanguage].
///
/// Each getter returns the string for the active language, falling back to
/// English when a Tagalog/Cebuano value is still empty — so the UI never shows
/// a blank while translations are being filled in.
///
/// NOTE: Tagalog/Cebuano values are starter translations and should be
/// reviewed by a SpEd/Filipino-language consultant before release. Empty
/// strings ('') are intentional TODO slots that fall back to English.
class AppStrings {
  const AppStrings(this.language);

  final GameLanguage language;

  String _pick(Map<GameLanguage, String> m) {
    final v = m[language];
    if (v != null && v.isNotEmpty) return v;
    return m[GameLanguage.english] ?? '';
  }

  // ── Praise / feedback ────────────────────────────────────────────────
  String get greatJob => _pick(const {
        GameLanguage.english: 'Great job!',
        GameLanguage.tagalog: 'Magaling!',
        GameLanguage.cebuano: 'Maayo kaayo!',
      });

  String get wellDone => _pick(const {
        GameLanguage.english: 'Well done!',
        GameLanguage.tagalog: 'Mahusay!',
        GameLanguage.cebuano: 'Maayo!',
      });

  String get tryAgain => _pick(const {
        GameLanguage.english: 'Try again',
        GameLanguage.tagalog: 'Subukan ulit',
        GameLanguage.cebuano: 'Sulayi pag-usab',
      });

  String get letsPlay => _pick(const {
        GameLanguage.english: "Let's play!",
        GameLanguage.tagalog: 'Maglaro tayo!',
        GameLanguage.cebuano: 'Magdula ta!',
      });

  // ── Sari-Sari Store Sorting ──────────────────────────────────────────
  String get sortInstruction => _pick(const {
        GameLanguage.english: 'Put each item in the right basket!',
        GameLanguage.tagalog: 'Ilagay ang bawat bagay sa tamang basket!',
        GameLanguage.cebuano: 'Ibutang ang matag butang sa saktong basket!',
      });

  String get binFood => _pick(const {
        GameLanguage.english: 'Food',
        GameLanguage.tagalog: 'Pagkain',
        GameLanguage.cebuano: 'Pagkaon',
      });

  String get binDrinks => _pick(const {
        GameLanguage.english: 'Drinks',
        GameLanguage.tagalog: 'Inumin',
        GameLanguage.cebuano: 'Ilimnon',
      });

  String get binToiletries => _pick(const {
        GameLanguage.english: 'Things',
        GameLanguage.tagalog: 'Gamit',
        GameLanguage.cebuano: 'Galamiton',
      });

  // ── Settings ─────────────────────────────────────────────────────────
  String get settingsTitle => _pick(const {
        GameLanguage.english: 'Settings',
        GameLanguage.tagalog: 'Mga Setting',
        GameLanguage.cebuano: 'Mga Setting',
      });

  String get languageLabel => _pick(const {
        GameLanguage.english: 'Language',
        GameLanguage.tagalog: 'Wika',
        GameLanguage.cebuano: 'Pinulongan',
      });

  String get backgroundThemeLabel => _pick(const {
        GameLanguage.english: 'Background Theme',
        GameLanguage.tagalog: 'Tema ng Background',
        GameLanguage.cebuano: 'Tema sa Background',
      });

  // ── Generic actions ──────────────────────────────────────────────────
  String get close => _pick(const {
        GameLanguage.english: 'Close',
        GameLanguage.tagalog: 'Isara',
        GameLanguage.cebuano: 'Sirad-i',
      });

  String get continueLabel => _pick(const {
        GameLanguage.english: 'Continue',
        GameLanguage.tagalog: 'Magpatuloy',
        GameLanguage.cebuano: 'Padayon',
      });
}

/// Holds the selected [GameLanguage] and notifies on change.
///
/// Mirrors AppThemeController. Create near the app root and expose via
/// [AppLanguageScope]; or drive it from a provider (e.g. ChildProvider).
class AppLanguageController extends ChangeNotifier {
  AppLanguageController([GameLanguage initial = GameLanguage.english])
      : _language = initial;

  GameLanguage _language;

  GameLanguage get language => _language;

  /// Localized strings for the current language.
  AppStrings get strings => AppStrings(_language);

  void setLanguage(GameLanguage language) {
    if (language == _language) return;
    _language = language;
    notifyListeners();
  }
}

/// Inherited access to the active [AppLanguageController] / [AppStrings].
class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController controllerOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    assert(scope != null, 'No AppLanguageScope found in the widget tree.');
    return scope!.notifier!;
  }

  static AppStrings stringsOf(BuildContext context) =>
      controllerOf(context).strings;
}
