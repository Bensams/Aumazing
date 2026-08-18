import 'package:flutter/foundation.dart';

import '../core/repositories/star_repository.dart';
import '../features/stars/star_catalogue.dart';
import '../model/star_ledger_entry.dart';

/// Why a finished activity did or did not pay (AUM-286).
///
/// The award path used to return a bare `0` for two quite different things,
/// and the game-end flow could only respond by showing nothing at all — a
/// child finished a game and the app said not one word. Naming the cases is
/// what lets each one be answered.
enum StarAwardOutcome {
  /// Stars were granted. [StarAwardResult.granted] says how many.
  earned,

  /// This game already paid today (AUM-284). It pays again tomorrow.
  alreadyEarnedToday,

  /// The daily cap is reached, so nothing more pays today whatever is played.
  dailyCapReached,

  /// No child is bound — nothing was attempted and nothing should be said.
  noChild,
}

/// The result of one award attempt.
@immutable
class StarAwardResult {
  const StarAwardResult(this.outcome, [this.granted = 0]);

  final StarAwardOutcome outcome;

  /// How many stars were actually written. Zero for everything but
  /// [StarAwardOutcome.earned] — and possibly fewer than [kStarsPerGame] even
  /// then, when the last game of the day runs into the cap part-way.
  final int granted;

  bool get didEarn => granted > 0;
}

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
  Set<String> _paidKeysToday = const {};
  List<CostumeOffer> _offers = const [];
  bool _loading = false;

  int get balance => _balance;
  int get earnedToday => _earnedToday;
  Set<String> get unlocked => _unlocked;
  List<CostumeOffer> get offers => _offers;
  bool get isLoading => _loading;

  /// Whether [gameId] has already paid this child today (AUM-284, AUM-285).
  ///
  /// The lobby shows a "got today's star" badge from this, so a child can see
  /// which games still have one waiting instead of finding out by playing and
  /// getting silence. Answered by rebuilding the same key the award path uses
  /// and testing for membership — no parsing, so the format lives in exactly
  /// one place.
  ///
  /// False when no child is bound, which is the honest answer: nothing has
  /// been paid to nobody, and a badge is the wrong thing to show while the
  /// ledger is still loading.
  bool hasEarnedStarToday(String gameId) {
    final childId = _childId;
    if (childId == null) return false;
    return _paidKeysToday.contains(
      starPlayKey(childId: childId, gameId: gameId),
    );
  }

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
      _paidKeysToday = const {};
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
      _paidKeysToday = await _repo.paidKeysToday(childId);
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
  /// [playKey] identifies what is being paid for, and paying for it twice is
  /// refused. Games build it with [starPlayKey] — child, game, calendar day —
  /// so a game pays once per day and a replay earns nothing (AUM-284); that
  /// also makes a double-tapped "finish", a rebuild or a retried write unable
  /// to pay twice (STAR-E2). The assessment path keys on its run id instead,
  /// because a run is a single thing that happens once.
  Future<StarAwardResult> awardForPlay({
    required String playKey,
    StarReason reason = StarReason.gamePlayed,
  }) async {
    final childId = _childId;
    if (childId == null) return const StarAwardResult(StarAwardOutcome.noChild);

    final granted = await _repo.awardForSession(
      childId: childId,
      gameSessionId: playKey,
      reason: reason,
    );
    if (granted > 0) {
      await refresh();
      return StarAwardResult(StarAwardOutcome.earned, granted);
    }

    // Nothing was written, so nothing about the ledger changed — but the
    // *reason* has to be read from it, and a cache from before this session
    // could be stale (the app may have been restarted since the game last
    // paid). One extra read on a path that is rare and never in a hot loop is
    // cheaper than telling a child the wrong thing.
    await refresh();
    if (_paidKeysToday.contains(playKey)) {
      return const StarAwardResult(StarAwardOutcome.alreadyEarnedToday);
    }
    if (atDailyCap) {
      return const StarAwardResult(StarAwardOutcome.dailyCapReached);
    }
    // Neither — an unexpected refusal. Say nothing rather than guess at a
    // reason; a wrong explanation is worse than the silence it replaces.
    return const StarAwardResult(StarAwardOutcome.noChild);
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
