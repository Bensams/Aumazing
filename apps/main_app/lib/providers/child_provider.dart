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
  bool get vibrationEnabled => _profile?.vibrationEnabled ?? true;

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
    bool? vibrationEnabled,
  }) async {
    if (_profile == null) return;

    _profile = _profile!.copyWith(
      musicEnabled: musicEnabled,
      vibrationEnabled: vibrationEnabled,
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

  void clear() {
    _profile = null;
    notifyListeners();
  }
}
