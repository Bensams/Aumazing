import 'package:flutter/foundation.dart';

import '../model/child_profile.dart';
import '../services/local_db_service.dart';
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
  bool get vibrationEnabled => _profile?.vibrationEnabled ?? true;

  /// Loads the child profile from SQLite cache, or falls back to
  /// Supabase user metadata.
  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = _authService.currentUser;
      if (user == null) return;

      // Try local cache first
      _profile = await _localDb.getChildProfile(user.id);

      // Fall back to Supabase user metadata
      if (_profile == null) {
        final meta = _authService.childProfile;
        if (meta != null) {
          _profile = ChildProfile(
            id: user.id,
            userId: user.id,
            name: meta['name'] as String,
            age: meta['age'] as int,
            avatar: meta['avatar'] as String,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          // Cache locally
          await _localDb.upsertChildProfile(_profile!);
        }
      }
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
    bool? vibrationEnabled,
  }) async {
    if (_profile == null) return;

    _profile = _profile!.copyWith(
      musicEnabled: musicEnabled,
      vibrationEnabled: vibrationEnabled,
    );

    await _localDb.upsertChildProfile(_profile!);
    notifyListeners();
  }

  /// Updates child profile details.
  Future<void> updateProfile({
    String? name,
    int? age,
    String? avatar,
  }) async {
    if (_profile == null) return;

    _profile = _profile!.copyWith(
      name: name,
      age: age,
      avatar: avatar,
    );

    await _localDb.upsertChildProfile(_profile!);
    notifyListeners();
  }

  void clear() {
    _profile = null;
    notifyListeners();
  }
}
