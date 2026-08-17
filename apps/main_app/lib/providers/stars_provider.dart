import 'package:flutter/foundation.dart';

import '../core/repositories/star_repository.dart';
import '../features/stars/star_catalogue.dart';
import '../model/star_ledger_entry.dart';

/// Star balance, unlocks and purchases for the active child (AUM-246).
///
/// A thin cache over [StarRepository]: the ledger is the source of truth and
/// the balance is always re-derived from it after a write, never adjusted in
/// place. Keeping the arithmetic in one place — the repository's `SUM(delta)`
/// — means the number a child sees cannot drift from the rows behind it.
class StarsProvider extends ChangeNotifier {
  StarsProvider({StarRepository? repository})
      : _repo = repository ?? StarRepository();

  final StarRepository _repo;

  String? _childId;
  int _balance = 0;
  int _earnedToday = 0;
  Set<String> _unlocked = const {};
  List<CostumeOffer> _offers = const [];
  bool _loading = false;

  int get balance => _balance;
  int get earnedToday => _earnedToday;
  Set<String> get unlocked => _unlocked;
  List<CostumeOffer> get offers => _offers;
  bool get isLoading => _loading;

  /// True once the child has earned everything today's cap allows.
  ///
  /// The UI phrases this as a completed state — "you've got all of today's
  /// stars" — never as a lockout. Games stay fully playable either way.
  bool get atDailyCap => _earnedToday >= kDailyStarCap;

  /// Points the provider at a child and loads their state. Safe to call on
  /// every build; it no-ops when the child has not changed.
  Future<void> bind(String? childId) async {
    if (childId == _childId) return;
    _childId = childId;
    if (childId == null) {
      _balance = 0;
      _earnedToday = 0;
      _unlocked = const {};
      _offers = const [];
      notifyListeners();
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    final childId = _childId;
    if (childId == null) return;
    _loading = true;
    notifyListeners();
    try {
      _balance = await _repo.balanceFor(childId);
      _earnedToday = await _repo.earnedTodayFor(childId);
      _unlocked = await _repo.unlockedFor(childId);
      _offers = await _repo.offersFor(childId);
    } catch (e) {
      debugPrint('[StarsProvider] refresh failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Awards the fixed payout for finishing an activity.
  ///
  /// Returns how many stars were actually granted — 0 when this play already
  /// paid or the daily cap is reached — so the caller can show the right
  /// message instead of an empty animation.
  ///
  /// [playKey] must be stable for one play-through and different for the next.
  /// It is what makes a double-tapped "finish", a rebuild, or a retried write
  /// unable to pay twice (STAR-E2).
  Future<int> awardForPlay({
    required String playKey,
    StarReason reason = StarReason.gamePlayed,
  }) async {
    final childId = _childId;
    if (childId == null) return 0;
    final granted = await _repo.awardForSession(
      childId: childId,
      gameSessionId: playKey,
      reason: reason,
    );
    if (granted > 0) await refresh();
    return granted;
  }

  /// Buys [costume]. Returns true when the purchase happened.
  Future<bool> purchase(Costume costume) async {
    final childId = _childId;
    if (childId == null) return false;
    final ok = await _repo.purchase(childId: childId, costume: costume);
    if (ok) await refresh();
    return ok;
  }

  bool owns(Costume costume) =>
      costume == Costume.none || _unlocked.contains(costume.id);

  /// The parent-facing history (STAR-G1). Read straight from the ledger rather
  /// than cached: it is opened rarely and must never show a stale total.
  Future<List<StarLedgerEntry>> history({int limit = 100}) async {
    final childId = _childId;
    if (childId == null) return const [];
    return _repo.historyFor(childId, limit: limit);
  }
}
