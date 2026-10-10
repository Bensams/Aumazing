import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How many child profiles an account may hold (pre-final defense note):
/// one profile is free; each additional one is bought separately — ₱30 — and
/// only Premium accounts can buy them.
///
/// Three rules keep this fair to families:
///
/// * **Nothing is ever taken away.** The gate applies only to *adding* a
///   child. A child already on the account stays, whatever happens to Premium
///   or to the slot count.
/// * **Families already past the limit are grandfathered.** The first time the
///   gate runs for an account it records a *baseline* — the free profile, or
///   the number of children the account already has if that is more. Bought
///   slots add to the baseline, so a family that already had three children
///   needs one slot for a fourth, not three.
/// * **The first child is always free.** An account with no children can
///   always add one.
enum AddChildGate {
  /// Adding a child is allowed right now.
  allowed,

  /// The account is on the free plan and already has its free profile.
  needsPremium,

  /// Premium, but every profile slot is in use: one more must be bought.
  needsSlot,
}

/// Profiles every account gets without paying.
const int kFreeChildProfiles = 1;

/// Price of one additional child profile, as shown to the parent.
const String kExtraProfilePriceLabel = '₱30.00';

class ChildProfileAllowance {
  ChildProfileAllowance._();

  static final ChildProfileAllowance instance = ChildProfileAllowance._();

  static String _baselineKey(String accountKey) =>
      'child_profile_baseline_$accountKey';

  /// The account's baseline allowance, recording it on first use.
  ///
  /// [accountKey] is the signed-in user id, or a stable guest key.
  Future<int> baselineFor(String accountKey, {required int existing}) async {
    final atLeast =
        existing > kFreeChildProfiles ? existing : kFreeChildProfiles;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_baselineKey(accountKey));
      if (stored != null) return stored;
      await prefs.setInt(_baselineKey(accountKey), atLeast);
      return atLeast;
    } catch (e) {
      // Fail open: a parent who loses local storage keeps the children they
      // have and the free-plan rules for new ones.
      debugPrint('[ChildProfileAllowance] baseline unavailable: $e');
      return atLeast;
    }
  }

  /// Whether one more child may be added.
  static AddChildGate gate({
    required int existing,
    required int baseline,
    required bool isPremium,
    required int extraSlots,
    bool unlimited = false,
  }) {
    if (unlimited) return AddChildGate.allowed;
    if (existing < kFreeChildProfiles) return AddChildGate.allowed;
    if (existing < baseline) return AddChildGate.allowed;
    if (!isPremium) return AddChildGate.needsPremium;
    if (existing < baseline + extraSlots) return AddChildGate.allowed;
    return AddChildGate.needsSlot;
  }

  /// Total profiles the account may hold right now, for display.
  static int allowance({
    required int baseline,
    required bool isPremium,
    required int extraSlots,
  }) => baseline + (isPremium ? extraSlots : 0);
}
