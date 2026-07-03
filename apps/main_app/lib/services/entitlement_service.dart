import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Premium entitlement state (freemium model).
///
/// The source of truth is the `entitlements` table, written ONLY by the
/// paymongo-webhook Edge Function after server-side signature verification
/// — the app can never grant itself Premium. The last known state is
/// cached locally so gating works offline.
class EntitlementService extends ChangeNotifier {
  EntitlementService._();

  static final EntitlementService instance = EntitlementService._();

  bool _isPremium = false;
  String? _loadedUserId;
  bool _bound = false;

  bool get isPremium => _isPremium;

  static String _cacheKey(String userId) => 'entitlement_premium_$userId';

  /// Call once after Supabase.initialize: loads the current state and
  /// reloads whenever the signed-in user changes (login, logout, guest
  /// upgrade), so gates across the app stay correct without manual pokes.
  void init() {
    if (_bound) return;
    _bound = true;
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => load());
    load();
  }

  /// Loads the cached state, then refreshes from the backend.
  Future<void> load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _isPremium = false;
      _loadedUserId = null;
      notifyListeners();
      return;
    }
    _loadedUserId = user.id;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isPremium = prefs.getBool(_cacheKey(user.id)) ?? false;
      notifyListeners();
    } catch (_) {}
    await refresh();
  }

  /// Re-reads the entitlement from Supabase (RLS: own row only).
  Future<void> refresh() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final row = await Supabase.instance.client
          .from('entitlements')
          .select('is_premium')
          .eq('user_id', user.id)
          .maybeSingle();
      final premium = row?['is_premium'] == true;
      if (premium != _isPremium || _loadedUserId != user.id) {
        _isPremium = premium;
        _loadedUserId = user.id;
        notifyListeners();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cacheKey(user.id), premium);
    } catch (e) {
      debugPrint('[Entitlement] refresh failed (keeping cache): $e');
    }
  }

  /// Polls for the webhook to land after a successful checkout
  /// (payment confirmed → webhook → entitlement row). Returns true once
  /// Premium is active.
  Future<bool> waitForActivation({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await refresh();
      if (_isPremium) return true;
      await Future.delayed(const Duration(seconds: 2));
    }
    return _isPremium;
  }
}
