import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../features/stars/star_catalogue.dart';
import '../../model/star_ledger_entry.dart';
import '../services/local_db_service.dart';
import '../sync/sync_status.dart';

/// Reads and writes the star ledger and the costume unlocks (STAR-E1…E4).
///
/// Offline-first, following the same local-SQLite-then-sync pattern as
/// [ChildRepository]: every write lands locally first with `synced = 0`, and
/// the sync layer promotes it later. Nothing here talks to Supabase directly.
///
/// Two rules this class exists to enforce, both of which are easy to lose if
/// the logic is spread across callers:
///
///  * **Balance is derived, never stored.** [balanceFor] sums the ledger. If
///    you ever find yourself wanting a cached balance column for speed,
///    measure first — a child has hundreds of rows, not millions.
///  * **Earning is idempotent per session.** [awardForSession] is a no-op if
///    that session already paid, so a retried sync or a double-tapped "finish"
///    cannot inflate a balance.
class StarRepository {
  StarRepository({LocalDbService? db, Uuid? uuid})
      : _db = db ?? localDbService,
        _uuid = uuid ?? const Uuid();

  final LocalDbService _db;
  final Uuid _uuid;

  Future<Database> get _database => _db.database;

  // ── Reading ─────────────────────────────────────────────────────────

  /// Current balance: the sum of every ledger row for this child.
  Future<int> balanceFor(String childId) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(delta), 0) AS total FROM ${LocalTables.starLedger} '
      'WHERE child_id = ?',
      [childId],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  /// Every entry, newest first — the parent-facing star history (STAR-G1).
  Future<List<StarLedgerEntry>> historyFor(String childId, {int? limit}) async {
    final db = await _database;
    final rows = await db.query(
      LocalTables.starLedger,
      where: 'child_id = ?',
      whereArgs: [childId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(StarLedgerEntry.fromMap).toList();
  }

  /// Stars earned today, for the daily cap (STAR-B4).
  ///
  /// Counts only positive deltas: spending must never buy back headroom under
  /// the cap, or a child could farm extra stars by purchasing.
  Future<int> earnedTodayFor(String childId, {DateTime? now}) async {
    final db = await _database;
    final today = now ?? DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(delta), 0) AS total FROM ${LocalTables.starLedger} '
      'WHERE child_id = ? AND delta > 0 AND created_at >= ?',
      [childId, start.toIso8601String()],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  /// The play keys that have already paid this child today (AUM-285).
  ///
  /// Returned as opaque strings and compared by membership: the caller asks
  /// `contains(starPlayKey(...))` rather than parsing a game id back out, so
  /// the key's format stays a private detail of the one function that builds
  /// it. Parsing it here would put a second, silent definition of the format
  /// in the codebase, and the two would drift.
  ///
  /// Positive deltas only, and the same local-midnight boundary
  /// [earnedTodayFor] uses — a purchase must never look like a game that paid.
  Future<Set<String>> paidKeysToday(String childId, {DateTime? now}) async {
    final db = await _database;
    final today = now ?? DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final rows = await db.query(
      LocalTables.starLedger,
      columns: ['game_session_id'],
      where: 'child_id = ? AND delta > 0 AND created_at >= ?',
      whereArgs: [childId, start.toIso8601String()],
    );
    return rows
        .map((r) => r['game_session_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  /// Costume ids this child owns. [Costume.none] is always implicitly owned
  /// and is not stored.
  Future<Set<String>> unlockedFor(String childId) async {
    final db = await _database;
    final rows = await db.query(
      LocalTables.childUnlocks,
      columns: ['item_id'],
      where: 'child_id = ?',
      whereArgs: [childId],
    );
    return rows.map((r) => r['item_id'] as String).toSet();
  }

  // ── Earning ─────────────────────────────────────────────────────────

  /// Awards the fixed activity payout, unless this session already paid or the
  /// child is at the daily cap.
  ///
  /// Returns how many stars were actually granted — 0 when capped or already
  /// paid — so the UI can say "you've got all of today's stars" instead of
  /// silently showing nothing.
  ///
  /// The amount does not depend on the session's score, errors, hints, retries
  /// or duration, and there is no code path here that reads them. See STAR-B1.
  Future<int> awardForSession({
    required String childId,
    required String gameSessionId,
    StarReason reason = StarReason.gamePlayed,
    DateTime? now,
  }) async {
    final db = await _database;

    // Idempotency (STAR-E2). Cheaper than relying on the unique index to throw,
    // and it lets the caller distinguish "already paid" from "capped".
    final existing = await db.query(
      LocalTables.starLedger,
      where: 'child_id = ? AND game_session_id = ? AND reason = ?',
      whereArgs: [childId, gameSessionId, reason.value],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      debugPrint('[StarRepository] session $gameSessionId already awarded');
      return 0;
    }

    final earned = await earnedTodayFor(childId, now: now);
    final headroom = kDailyStarCap - earned;
    if (headroom <= 0) return 0;

    // Partial rather than nothing: a child who is 1 star from the cap still
    // earned that star by playing, and rounding it away would make the last
    // game of the day feel like it did not count.
    final amount = kStarsPerGame < headroom ? kStarsPerGame : headroom;

    await _insert(
      StarLedgerEntry(
        id: _uuid.v4(),
        childId: childId,
        delta: amount,
        reason: reason,
        gameSessionId: gameSessionId,
        createdAt: now ?? DateTime.now(),
      ),
    );
    return amount;
  }

  // ── Spending ────────────────────────────────────────────────────────

  /// Buys [costume] for [childId].
  ///
  /// Returns true when the purchase happened. Already-owned and can't-afford
  /// both return false without writing — the caller decides what to say, and
  /// neither is an error condition worth throwing over.
  ///
  /// The debit row and the unlock row go in one transaction, so a crash cannot
  /// leave a child charged for a costume they do not own.
  Future<bool> purchase({
    required String childId,
    required Costume costume,
    DateTime? now,
  }) async {
    if (costume == Costume.none) return false;

    final owned = await unlockedFor(childId);
    if (owned.contains(costume.id)) return false;

    final balance = await balanceFor(childId);
    if (balance < costume.priceStars) return false;

    final db = await _database;
    final at = now ?? DateTime.now();
    await db.transaction((txn) async {
      await txn.insert(
        LocalTables.starLedger,
        StarLedgerEntry(
          id: _uuid.v4(),
          childId: childId,
          delta: -costume.priceStars,
          reason: StarReason.purchase,
          itemId: costume.id,
          createdAt: at,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.insert(
        LocalTables.childUnlocks,
        ChildUnlock(childId: childId, itemId: costume.id, unlockedAt: at)
            .toMap(),
        // Monotonic: a replayed unlock is a no-op, never a removal.
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
    return true;
  }

  /// The shop's view of the costumes on offer to this child, cheapest first.
  ///
  /// Returns an offer for every costume in stock including the unaffordable
  /// ones — the shop shows everything it sells, always, because a child needs
  /// to see what they are working towards (STAR-C1). "Not yet" is a progress
  /// bar here, never a padlock.
  ///
  /// [Costume.inStock] is narrower than [Costume.purchasable]: a costume with
  /// no sprite sheets is not sold, because buying it would not change the
  /// mascot in-game. Anything the child already owns is added back whatever
  /// its stock state — a costume that leaves the shop must not vanish from the
  /// wardrobe of a child who bought it (STAR-D4).
  Future<List<CostumeOffer>> offersFor(String childId) async {
    final balance = await balanceFor(childId);
    final owned = await unlockedFor(childId);
    final shown = {
      ...Costume.inStock,
      ...Costume.purchasable.where((c) => owned.contains(c.id)),
    }.toList()
      ..sort((a, b) => a.priceStars.compareTo(b.priceStars));
    return [
      for (final costume in shown)
        CostumeOffer(
          costume: costume,
          owned: owned.contains(costume.id),
          balance: balance,
        ),
    ];
  }

  Future<void> _insert(StarLedgerEntry entry) async {
    final db = await _database;
    await db.insert(
      LocalTables.starLedger,
      entry.toMap(),
      // The unique index on (child_id, game_session_id, reason) is the real
      // idempotency guarantee; ignoring the conflict makes a racing double
      // award a no-op rather than a crash mid-celebration.
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
