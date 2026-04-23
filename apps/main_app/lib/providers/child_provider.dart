import 'package:flutter/foundation.dart';

import '../core/services/local_db_service.dart';
import '../model/child_profile.dart';
import '../core/services/auth_service.dart';

/// Manages the current child profile and comfort settings.
class ChildProvider extends ChangeNotifier {
  final LocalDbService _localDb;
  final AuthService _authService;

  ChildProfile? _profile;
  bool _isLoading = false;

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

  void clear() {
    _profile = null;
    notifyListeners();
  }
}
