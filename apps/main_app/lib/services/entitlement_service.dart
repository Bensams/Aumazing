import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/premium_access_config.dart';
import '../dev/developer_tools_config.dart';

/// Premium entitlement state (freemium model).
///
/// In the normal product edition, the source of truth is the `entitlements`
/// table, written ONLY by the paymongo-webhook Edge Function after server-side
/// signature verification. A separately built free-distribution edition can
/// unlock the same gates at compile time through [PremiumAccessConfig] without
/// enabling developer tools or writing entitlement data. The last known real
/// entitlement is cached locally so normal gating works offline.
class EntitlementService extends ChangeNotifier {
  EntitlementService._();

  static final EntitlementService instance = EntitlementService._();

  bool _isPremium = false;
  String? _loadedUserId;
  bool _bound = false;

  /// Developer-tools only: pretends Premium is active for this process.
  ///
  /// Deliberately a *separate* field from [_isPremium]: the genuine cached
  /// and backend-refreshed value keeps flowing underneath, so turning the
  /// override off restores the real entitlement immediately and a background
  /// [refresh] can never silently cancel an active override. Nothing here
  /// writes to Supabase, the `entitlements` table, or SharedPreferences, and
  /// it is not persisted — a restart drops it.
  bool _developerPremiumOverride = false;

  /// The effective entitlement every gate in the app reads.
  bool get isPremium =>
      PremiumAccessConfig.unlockedForEveryone ||
      _developerPremiumOverride ||
      _isPremium;

  /// The genuine entitlement, ignoring any developer override.
  bool get isRealPremium => _isPremium;

  /// Whether the in-memory developer override is currently forcing Premium.
  bool get isDeveloperPremiumOverrideActive => _developerPremiumOverride;

  /// Turns the developer Premium override on or off.
  ///
  /// A no-op unless the developer toolbox is available
  /// ([DeveloperToolsConfig.isAvailable]), so the override cannot be reached
  /// in a profile or release build even if something calls this.
  void setDeveloperPremiumOverride(bool value) {
    if (!DeveloperToolsConfig.isAvailable) return;
    if (_developerPremiumOverride == value) return;
    _developerPremiumOverride = value;
    debugPrint(
      '[Entitlement] Developer Premium override: $value '
      '(real entitlement unchanged: $_isPremium)',
    );
    notifyListeners();
  }

  /// Test seam: sets the *genuine* in-memory entitlement the way a cache read
  /// or a backend [refresh] would, without a Supabase connection. Applied
  /// inside an `assert` so it does nothing in profile or release builds, and
  /// it writes no cache or backend state.
  @visibleForTesting
  void debugSetRealPremium(bool value) {
    assert(() {
      if (_isPremium != value) {
        _isPremium = value;
        notifyListeners();
      }
      return true;
    }());
  }

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
  ///
  /// Returns true when the read reached the backend, false when it failed
  /// and the cached value was kept. Callers that must distinguish
  /// "confirmed not premium" from "could not check" need that difference
  /// — see [waitForActivation].
  Future<bool> refresh() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    try {
      final row =
          await Supabase.instance.client
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
      return true;
    } catch (e) {
      debugPrint('[Entitlement] refresh failed (keeping cache): $e');
      return false;
    }
  }

  /// Polls for the webhook to land after the parent returns from a
  /// successful checkout (payment confirmed → signed webhook →
  /// entitlement row). Returns true only once the *backend* confirms
  /// Premium is active.
  ///
  /// Reaching the success URL is not evidence of payment — it is just a
  /// browser redirect, and the only thing that grants Premium is the
  /// signature-verified webhook. So this deliberately requires a
  /// successful backend read within the window: a stale cached `true`, or
  /// an offline device that cannot check, reports false rather than
  /// unlocking on the redirect alone.
  Future<bool> waitForActivation({
    Duration timeout = const Duration(seconds: 20),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var confirmed = false;
    while (true) {
      final reachedBackend = await refresh();
      if (reachedBackend) {
        confirmed = true;
        if (_isPremium) return true;
      }
      if (!DateTime.now().isBefore(deadline)) break;
      await Future.delayed(pollInterval);
    }
    return confirmed && _isPremium;
  }
}
