/// One movement of stars for one child (STAR-E1).
///
/// The ledger is **append-only** and the balance is derived by summing it.
/// There is deliberately no `star_balance` column anywhere in this app.
///
/// That is not purism. This app is offline-first: a child plays on a tablet
/// with no signal, the rows upload later, and the same family may use more than
/// one device. A single mutable balance under last-write-wins sync silently
/// discards whichever device wrote second — which, here, means a child loses
/// stars they watched themselves earn. Append-only rows from any number of
/// devices merge by addition and cannot disagree.
library;

/// Why stars moved. Stored as a string so old rows stay readable after new
/// reasons are added.
enum StarReason {
  /// Finished a game. Always [kStarsPerGame], never scaled by performance.
  gamePlayed('game_played'),

  /// Finished a pre- or post-assessment run, scored and complete.
  assessmentCompleted('assessment_completed'),

  /// Bought a costume. The ONLY reason that may carry a negative delta.
  purchase('purchase');

  const StarReason(this.value);
  final String value;

  static StarReason fromValue(String? v) => StarReason.values.firstWhere(
        (r) => r.value == v,
        orElse: () => StarReason.gamePlayed,
      );

  /// Whether this reason is allowed to remove stars.
  ///
  /// Guarded in [StarLedgerEntry]'s constructor and pinned by test. Stars are
  /// never lost, never expire and never decay (STAR-B5): loss aversion in a
  /// child prone to dysregulation is a meltdown, not a retention mechanic.
  bool get maySpend => this == StarReason.purchase;
}

class StarLedgerEntry {
  StarLedgerEntry({
    required this.id,
    required this.childId,
    required this.delta,
    required this.reason,
    this.gameSessionId,
    this.itemId,
    required this.createdAt,
    this.synced = false,
  }) : assert(
          delta >= 0 || reason.maySpend,
          'Only a purchase may remove stars — see STAR-B5.',
        );

  final String id;
  final String childId;

  /// Signed. Positive for earning, negative only for [StarReason.purchase].
  final int delta;

  final StarReason reason;

  /// The session this award belongs to, for earn rows.
  ///
  /// Carries the idempotency guarantee (STAR-E2): `(child_id, game_session_id,
  /// reason)` is unique, so replaying an upload — which the sync layer does
  /// after any failure — cannot pay a child twice for one game.
  final String? gameSessionId;

  /// Which costume, for purchase rows.
  final String? itemId;

  final DateTime createdAt;
  final bool synced;

  StarLedgerEntry copyWith({bool? synced}) => StarLedgerEntry(
        id: id,
        childId: childId,
        delta: delta,
        reason: reason,
        gameSessionId: gameSessionId,
        itemId: itemId,
        createdAt: createdAt,
        synced: synced ?? this.synced,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'child_id': childId,
        'delta': delta,
        'reason': reason.value,
        'game_session_id': gameSessionId,
        'item_id': itemId,
        'created_at': createdAt.toIso8601String(),
        'synced': synced ? 1 : 0,
      };

  factory StarLedgerEntry.fromMap(Map<String, dynamic> map) => StarLedgerEntry(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        delta: (map['delta'] as num).toInt(),
        reason: StarReason.fromValue(map['reason'] as String?),
        gameSessionId: map['game_session_id'] as String?,
        itemId: map['item_id'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        synced: (map['synced'] ?? 0) == 1,
      );

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'child_id': childId,
        'delta': delta,
        'reason': reason.value,
        'game_session_id': gameSessionId,
        'item_id': itemId,
        'created_at': createdAt.toIso8601String(),
      };

  factory StarLedgerEntry.fromSupabase(Map<String, dynamic> map) =>
      StarLedgerEntry(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        delta: (map['delta'] as num).toInt(),
        reason: StarReason.fromValue(map['reason'] as String?),
        gameSessionId: map['game_session_id'] as String?,
        itemId: map['item_id'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        synced: true,
      );
}

/// A costume this child owns.
///
/// Unlocks are monotonic — once owned, always owned. That makes them trivially
/// mergeable across devices and means no sync path can take a costume back
/// (STAR-C7).
class ChildUnlock {
  const ChildUnlock({
    required this.childId,
    required this.itemId,
    required this.unlockedAt,
    this.synced = false,
  });

  final String childId;
  final String itemId;
  final DateTime unlockedAt;
  final bool synced;

  Map<String, dynamic> toMap() => {
        'child_id': childId,
        'item_id': itemId,
        'unlocked_at': unlockedAt.toIso8601String(),
        'synced': synced ? 1 : 0,
      };

  factory ChildUnlock.fromMap(Map<String, dynamic> map) => ChildUnlock(
        childId: map['child_id'] as String,
        itemId: map['item_id'] as String,
        unlockedAt: DateTime.parse(map['unlocked_at'] as String),
        synced: (map['synced'] ?? 0) == 1,
      );
}
