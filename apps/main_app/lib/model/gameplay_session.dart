/// A single gameplay session — one play-through of one mini-game.
/// Stored locally in SQLite with a [synced] flag for later upload.
class GameplaySession {
  final String id;
  final String childId;

  /// Game identifier: 'match_it', 'copy_me', etc.
  final String gameId;

  /// Context: 'pre_assessment', 'post_assessment', or 'practice'
  final String context;

  final int score;
  final int totalItems;
  final int errorCount;

  /// Total response time in milliseconds across all items.
  final int totalResponseTimeMs;

  /// Number of retries the child used during the session.
  final int retryCount;

  /// Number of hints the child requested or was given.
  final int hintCount;

  /// Total idle time in seconds (no interaction detected).
  final double idleTimeSeconds;

  /// Number of random/off-target touches during the session.
  final int randomTouchCount;

  final DateTime startedAt;
  final DateTime endedAt;

  /// Whether this session has been synced to Supabase.
  final bool synced;

  const GameplaySession({
    required this.id,
    required this.childId,
    required this.gameId,
    required this.context,
    required this.score,
    required this.totalItems,
    required this.errorCount,
    required this.totalResponseTimeMs,
    this.retryCount = 0,
    this.hintCount = 0,
    this.idleTimeSeconds = 0.0,
    this.randomTouchCount = 0,
    required this.startedAt,
    required this.endedAt,
    this.synced = false,
  });

  int get avgResponseTimeMs =>
      totalItems > 0 ? (totalResponseTimeMs / totalItems).round() : 0;

  Duration get duration => endedAt.difference(startedAt);

  GameplaySession markSynced() => GameplaySession(
        id: id,
        childId: childId,
        gameId: gameId,
        context: context,
        score: score,
        totalItems: totalItems,
        errorCount: errorCount,
        totalResponseTimeMs: totalResponseTimeMs,
        retryCount: retryCount,
        hintCount: hintCount,
        idleTimeSeconds: idleTimeSeconds,
        randomTouchCount: randomTouchCount,
        startedAt: startedAt,
        endedAt: endedAt,
        synced: true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'child_id': childId,
        'game_id': gameId,
        'context': context,
        'score': score,
        'total_items': totalItems,
        'error_count': errorCount,
        'total_response_time_ms': totalResponseTimeMs,
        'retry_count': retryCount,
        'hint_count': hintCount,
        'idle_time_seconds': idleTimeSeconds,
        'random_touch_count': randomTouchCount,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'synced': synced ? 1 : 0,
      };

  factory GameplaySession.fromMap(Map<String, dynamic> map) => GameplaySession(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        gameId: map['game_id'] as String,
        context: map['context'] as String,
        score: map['score'] as int,
        totalItems: map['total_items'] as int,
        errorCount: map['error_count'] as int,
        totalResponseTimeMs: map['total_response_time_ms'] as int,
        retryCount: (map['retry_count'] as int?) ?? 0,
        hintCount: (map['hint_count'] as int?) ?? 0,
        idleTimeSeconds: (map['idle_time_seconds'] as num?)?.toDouble() ?? 0.0,
        randomTouchCount: (map['random_touch_count'] as int?) ?? 0,
        startedAt: DateTime.parse(map['started_at'] as String),
        endedAt: DateTime.parse(map['ended_at'] as String),
        synced: (map['synced'] ?? 0) == 1,
      );

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'child_id': childId,
        'game_id': gameId,
        'context': context,
        'score': score,
        'total_items': totalItems,
        'error_count': errorCount,
        'total_response_time_ms': totalResponseTimeMs,
        'retry_count': retryCount,
        'hint_count': hintCount,
        'idle_time_seconds': idleTimeSeconds,
        'random_touch_count': randomTouchCount,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
      };
}
