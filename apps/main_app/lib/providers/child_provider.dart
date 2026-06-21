import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../core/services/local_db_service.dart';
import '../model/child_profile.dart';
import '../core/services/auth_service.dart';

/// Manages the current child profile and comfort settings.
class ChildProvider extends ChangeNotifier {
  final LocalDbService _localDb;
  final AuthService _authService;

  ChildProfile? _profile;
  bool _isLoading = false;

  /// Parent's manual background-theme override. When null, the theme is
  /// derived from the child's sex. Persisted locally (no DB migration).
  GameTheme? _themeOverride;
  static const _themeOverrideKeyPrefix = 'theme_override_';

  /// Selected app/game language (English / Tagalog / Cebuano). Persisted
  /// locally; defaults to English.
  GameLanguage _language = GameLanguage.english;
  static const _languageKeyPrefix = 'language_';

  ChildProvider({
    LocalDbService? localDb,
    AuthService? authService,
  })  : _localDb = localDb ?? LocalDbService(),
        _authService = authService ?? AuthService();

  ChildProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get hasProfile => _profile != null;

  // Comfort settings shortcuts
  bool get musicEnabled => _profile?.musicEnabled ?? true;
  double get musicVolume => _profile?.musicVolume ?? 0.5;
  double get sfxVolume => _profile?.sfxVolume ?? 0.7;
  bool get vibrationEnabled => _profile?.vibrationEnabled ?? true;
  double get animationIntensity => _profile?.animationIntensity ?? 1.0;
  double get promptSpeed => _profile?.promptSpeed ?? 1.0;
  bool get sensoryPreferencesSet => _profile?.sensoryPreferencesSet ?? false;

  // Reward preference shortcuts
  RewardPreference get rewardPreference => _profile?.rewardPreference ?? RewardPreference.bubbles;
  bool get useRandomReward => _profile?.useRandomReward ?? false;

  // ── Background theme ──────────────────────────────────────────────────

  /// The parent's manual theme override, or null if following the child's sex.
  GameTheme? get themeOverride => _themeOverride;

  /// Whether the active theme comes from a manual override (vs. auto-from-sex).
  bool get isThemeOverridden => _themeOverride != null;

  /// The active background theme: manual override if set, else derived from
  /// the child's sex (defaults to neutral).
  GameTheme get activeTheme =>
      _themeOverride ?? GameTheme.fromSexValue(_profile?.sex?.value);

  /// The full color palette for the [activeTheme] (game + dashboard).
  GamePalette get activePalette => GamePalettes.of(activeTheme);

  // ── Language ──────────────────────────────────────────────────────────

  /// The active app/game language (defaults to English).
  GameLanguage get language => _language;

  /// Localized strings for the active language.
  AppStrings get strings => AppStrings(_language);

  /// Returns the sensory settings as a map for use in scoring/assessment.
  Map<String, dynamic> get sensorySettingsMap =>
      _profile?.sensorySettingsMap ??
      {
        'music_enabled': true,
        'music_volume': 0.5,
        'sfx_volume': 0.7,
        'vibration_enabled': true,
        'animation_intensity': 1.0,
        'prompt_speed': 1.0,
      };

  /// Loads the child profile from SQLite cache only.
  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      final userId = _authService.effectiveUserId;
      if (userId == null) {
        _profile = null;
        return;
      }

      final children = await _localDb.getChildren(userId: userId);
      _profile = children.isEmpty ? null : children.first;
      await _loadThemeOverride();
      await _loadLanguage();
    } catch (e) {
      debugPrint('[ChildProvider] loadProfile error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates comfort settings and persists them.
  Future<void> updateComfortSettings({
    bool? musicEnabled,
    double? musicVolume,
    double? sfxVolume,
    bool? vibrationEnabled,
    double? animationIntensity,
    double? promptSpeed,
    bool? sensoryPreferencesSet,
  }) async {
    if (_profile == null) return;

    _profile = _profile!.copyWith(
      musicEnabled: musicEnabled,
      musicVolume: musicVolume,
      sfxVolume: sfxVolume,
      vibrationEnabled: vibrationEnabled,
      animationIntensity: animationIntensity,
      promptSpeed: promptSpeed,
      sensoryPreferencesSet: sensoryPreferencesSet,
    );

    await _localDb.upsertChild(_profile!);
    notifyListeners();
  }

  /// Updates child profile details.
  Future<void> updateProfile({
    String? displayName,
    DateTime? birthDate,
    String? avatar,
  }) async {
    if (_profile == null) return;

    _profile = _profile!.copyWith(
      displayName: displayName,
      birthDate: birthDate,
      avatar: avatar,
    );

    await _localDb.upsertChild(_profile!);
    notifyListeners();
  }

  /// Updates reward preferences and persists them.
  Future<void> updateRewardPreferences({
    RewardPreference? rewardPreference,
    bool? useRandomReward,
  }) async {
    if (_profile == null) return;

    _profile = _profile!.copyWith(
      rewardPreference: rewardPreference,
      useRandomReward: useRandomReward,
    );

    await _localDb.upsertChild(_profile!, markPending: true);
    notifyListeners();
  }

  /// Sets a manual background-theme override and persists it locally.
  Future<void> setThemeOverride(GameTheme theme) async {
    _themeOverride = theme;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_themeOverrideKeyPrefix$id', theme.slug);
    }
  }

  /// Clears the manual override so the theme follows the child's sex again.
  Future<void> clearThemeOverride() async {
    _themeOverride = null;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_themeOverrideKeyPrefix$id');
    }
  }

  /// Loads any persisted theme override for the current child.
  Future<void> _loadThemeOverride() async {
    final id = _profile?.id;
    if (id == null) {
      _themeOverride = null;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final slug = prefs.getString('$_themeOverrideKeyPrefix$id');
    _themeOverride = slug == null ? null : GameTheme.fromSlug(slug);
  }

  /// Sets the app/game language and persists it locally.
  Future<void> setLanguage(GameLanguage language) async {
    _language = language;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_languageKeyPrefix$id', language.slug);
    }
  }

  /// Loads the persisted language for the current child (defaults to English).
  Future<void> _loadLanguage() async {
    final id = _profile?.id;
    if (id == null) {
      _language = GameLanguage.english;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final slug = prefs.getString('$_languageKeyPrefix$id');
    _language = GameLanguage.fromSlug(slug);
  }

  void clear() {
    _profile = null;
    _themeOverride = null;
    _language = GameLanguage.english;
    notifyListeners();
  }
}
