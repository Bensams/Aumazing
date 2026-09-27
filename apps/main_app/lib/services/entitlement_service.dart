import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/payment_simulation_config.dart';
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

  /// Simulated-checkout only: the Premium a mock purchase "bought" (AUM-331).
  ///
  /// Held apart from both [_isPremium] and [_developerPremiumOverride] on
  /// purpose. The real entitlement keeps flowing underneath untouched, so a
  /// simulated purchase can never be mistaken for — or overwrite — a genuine
  /// one, and a background [refresh] cannot cancel the demo mid-sentence.
  ///
  /// Nothing here writes to Supabase, the `entitlements` table, or
  /// SharedPreferences, and it is not persisted: a restart drops it, which is
  /// the honest behaviour for a purchase that never happened.
  bool _simulatedPurchasePremium = false;

  /// Extra child-profile slots bought on top of the one free profile
  /// (pre-final defense note: one profile per account, ₱30 per additional
  /// profile, Premium only). Read from `entitlements.extra_profile_slots`,
  /// which only the payment webhook may write, and cached like Premium.
  int _extraProfileSlots = 0;

  /// Slots bought through the simulated checkout. In memory only, like
  /// [_simulatedPurchasePremium]: a restart drops them, which is the honest
  /// behaviour for a purchase that never happened.
  int _simulatedProfileSlots = 0;

  /// When the paid Premium period ends (`entitlements.expires_at`), or null
  /// for an entitlement with no end. Each payment buys 30 days, so Premium
  /// lapses on this date even offline, from the cached value.
  DateTime? _premiumUntil;

  bool get _periodActive =>
      _premiumUntil == null || DateTime.now().isBefore(_premiumUntil!);

  /// The effective entitlement every gate in the app reads.
  bool get isPremium =>
      PremiumAccessConfig.unlockedForEveryone ||
      _developerPremiumOverride ||
      _simulatedPurchasePremium ||
      isRealPremium;

  /// The genuine entitlement, ignoring any developer override: paid for, and
  /// its period not yet over.
  bool get isRealPremium => _isPremium && _periodActive;

  /// When the current Premium period ends, if it has an end.
  DateTime? get premiumUntil => _premiumUntil;

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

  /// Extra child-profile slots the account can use, beyond the free one.
  ///
  /// Real slots plus simulated ones. Builds that unlock everything
  /// ([PremiumAccessConfig.unlockedForEveryone]) or run with the developer
  /// Premium override get no profile limit at all.
  int get extraProfileSlots => _extraProfileSlots + _simulatedProfileSlots;

  /// Whether profile slots are not limited in this build or session.
  bool get unlimitedProfiles =>
      PremiumAccessConfig.unlockedForEveryone || _developerPremiumOverride;

  /// Records one extra profile slot a simulated checkout "sold".
  ///
  /// Gated exactly like [grantSimulatedPurchase]: a build that cannot show the
  /// mock checkout cannot honour its result either.
  void grantSimulatedProfileSlot() {
    if (!PaymentSimulationConfig.isAvailable) return;
    _simulatedProfileSlots++;
    debugPrint(
      '[Entitlement] Simulated profile slot granted — NOT a real payment '
      '(real slots unchanged: $_extraProfileSlots)',
    );
    notifyListeners();
  }

  /// Test seam: sets the genuine slot count as a backend read would.
  @visibleForTesting
  void debugSetExtraProfileSlots(int value) {
    assert(() {
      _extraProfileSlots = value;
      _simulatedProfileSlots = 0;
      notifyListeners();
      return true;
    }());
  }

  /// Whether a simulated purchase is currently standing in for Premium.
  bool get isSimulatedPurchaseActive => _simulatedPurchasePremium;

  /// Grants the Premium a simulated checkout just "paid" for (AUM-331).
  ///
  /// A no-op unless the simulated checkout is compiled in
  /// ([PaymentSimulationConfig.isAvailable]), so a build that cannot show the
  /// mock cannot be talked into honouring its result either — the grant is
  /// gated at the same place the screen is, not merely by who calls it.
  void grantSimulatedPurchase() {
    if (!PaymentSimulationConfig.isAvailable) return;
    if (_simulatedPurchasePremium) return;
    _simulatedPurchasePremium = true;
    debugPrint(
      '[Entitlement] Simulated purchase granted — NOT a real payment '
      '(real entitlement unchanged: $_isPremium)',
    );
    notifyListeners();
  }

  /// Drops a simulated purchase, returning to whatever is genuinely true.
  void clearSimulatedPurchase() {
    if (!_simulatedPurchasePremium) return;
    _simulatedPurchasePremium = false;
    notifyListeners();
  }

  /// Test seam: sets the *genuine* in-memory entitlement the way a cache read
  /// or a backend [refresh] would, without a Supabase connection. Applied
  /// inside an `assert` so it does nothing in profile or release builds, and
  /// it writes no cache or backend state.
  @visibleForTesting
  void debugSetRealPremium(bool value, {DateTime? until}) {
    assert(() {
      _isPremium = value;
      _premiumUntil = until;
      notifyListeners();
      return true;
    }());
  }

  static String _cacheKey(String userId) => 'entitlement_premium_$userId';
  static String _slotsKey(String userId) => 'entitlement_profile_slots_$userId';
  static String _untilKey(String userId) => 'entitlement_premium_until_$userId';

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
      _premiumUntil = null;
      _extraProfileSlots = 0;
      _loadedUserId = null;
      notifyListeners();
      return;
    }
    _loadedUserId = user.id;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isPremium = prefs.getBool(_cacheKey(user.id)) ?? false;
      _premiumUntil = DateTime.tryParse(prefs.getString(_untilKey(user.id)) ?? '');
      _extraProfileSlots = prefs.getInt(_slotsKey(user.id)) ?? 0;
      notifyListeners();
    } catch (_) {}
    await refresh();
    await _refreshProfileSlots(user.id);
  }

  /// Reads the purchased profile-slot count on its own, so a backend that
  /// does not have the `extra_profile_slots` column yet leaves the Premium
  /// read above untouched and simply keeps the cached (or zero) count.
  Future<void> _refreshProfileSlots(String userId) async {
    try {
      final row =
          await Supabase.instance.client
              .from('entitlements')
              .select('extra_profile_slots')
              .eq('user_id', userId)
              .maybeSingle();
      final slots = (row?['extra_profile_slots'] as num?)?.toInt() ?? 0;
      if (slots != _extraProfileSlots) {
        _extraProfileSlots = slots;
        notifyListeners();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_slotsKey(userId), slots);
    } catch (e) {
      debugPrint('[Entitlement] profile-slot read failed (keeping cache): $e');
    }
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
              .select('is_premium, expires_at')
              .eq('user_id', user.id)
              .maybeSingle();
      final premium = row?['is_premium'] == true;
      final until = DateTime.tryParse(row?['expires_at'] as String? ?? '');
      if (premium != _isPremium ||
          until != _premiumUntil ||
          _loadedUserId != user.id) {
        _isPremium = premium;
        _premiumUntil = until;
        _loadedUserId = user.id;
        notifyListeners();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cacheKey(user.id), premium);
      if (until == null) {
        await prefs.remove(_untilKey(user.id));
      } else {
        await prefs.setString(_untilKey(user.id), until.toIso8601String());
      }
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
        if (isRealPremium) return true;
      }
      if (!DateTime.now().isBefore(deadline)) break;
      await Future.delayed(pollInterval);
    }
    return confirmed && isRealPremium;
  }

  /// Waits for a purchased child-profile slot (AUM-349) to reach the backend:
  /// true once the account's real slot count rises above [above]. As with
  /// [waitForActivation], only the signature-verified webhook adds a slot, so
  /// the checkout's success redirect alone never counts.
  Future<bool> waitForProfileSlot({
    required int above,
    Duration timeout = const Duration(seconds: 60),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    final deadline = DateTime.now().add(timeout);
    while (true) {
      await _refreshProfileSlots(user.id);
      if (_extraProfileSlots > above) return true;
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future.delayed(pollInterval);
    }
  }

  /// The purchased (not simulated) slot count, for comparing before and
  /// after a checkout.
  int get realExtraProfileSlots => _extraProfileSlots;
}
