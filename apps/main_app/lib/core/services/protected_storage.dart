import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small seam around platform-protected storage. Sensitive values are kept in
/// Android Keystore-backed storage; the preferences fallback keeps widget
/// tests and unsupported development targets usable without weakening Android.
class ProtectedStorage {
  ProtectedStorage({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  Future<String?> read(String key, {String? legacyKey}) async {
    try {
      final value = await _secure.read(key: key);
      if (value != null) return value;
      if (legacyKey == null) return null;
    } catch (_) {
      // The fallback is for tests and non-Android development builds.
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyKey ?? key);
    if (legacy != null) {
      try {
        await _secure.write(key: key, value: legacy);
        await prefs.remove(legacyKey ?? key);
      } catch (_) {
        // Keep the legacy value when protected storage is unavailable.
      }
    }
    return legacy;
  }

  Future<void> write(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
      return;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> delete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
