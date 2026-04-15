/// The result of a single mini-game within a pre- or post-assessment.
class AssessmentResult {
  final String id;
  final String childId;

  /// 'pre' or 'post'
  final String type;

  /// Game identifier: 'match_it', 'copy_me', 'do_what_i_say', 'my_turn_your_turn'
  final String gameId;

  final int score;
  final int totalItems;
  final int errorCount;

  /// Average response time in milliseconds across all items.
  final int avgResponseTimeMs;

  final DateTime completedAt;

  /// Optional bag of extra metrics (e.g. per-item breakdown).
  final Map<String, dynamic> rawMetrics;

  const AssessmentResult({
    required this.id,
    required this.childId,
    required this.type,
    required this.gameId,
    required this.score,
    required this.totalItems,
    required this.errorCount,
    required this.avgResponseTimeMs,
    required this.completedAt,
    this.rawMetrics = const {},
  });

  double get accuracy =>
      totalItems > 0 ? (score / totalItems).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'child_id': childId,
        'type': type,
        'game_id': gameId,
        'score': score,
        'total_items': totalItems,
        'error_count': errorCount,
        'avg_response_time_ms': avgResponseTimeMs,
        'completed_at': completedAt.toIso8601String(),
        'raw_metrics': rawMetrics.toString(),
      };

  factory AssessmentResult.fromMap(Map<String, dynamic> map) =>
      AssessmentResult(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        type: map['type'] as String,
        gameId: map['game_id'] as String,
        score: map['score'] as int,
        totalItems: map['total_items'] as int,
        errorCount: map['error_count'] as int,
        avgResponseTimeMs: map['avg_response_time_ms'] as int,
        completedAt: DateTime.parse(map['completed_at'] as String),
      );

  factory AssessmentResult.fromSupabase(Map<String, dynamic> map) =>
      AssessmentResult(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        type: map['type'] as String,
        gameId: map['game_id'] as String,
        score: map['score'] as int,
        totalItems: map['total_items'] as int,
        errorCount: map['error_count'] as int,
        avgResponseTimeMs: map['avg_response_time_ms'] as int,
        completedAt: DateTime.parse(map['completed_at'] as String),
        rawMetrics: (map['raw_metrics'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'child_id': childId,
        'type': type,
        'game_id': gameId,
        'score': score,
        'total_items': totalItems,
        'error_count': errorCount,
        'avg_response_time_ms': avgResponseTimeMs,
        'completed_at': completedAt.toIso8601String(),
        'raw_metrics': rawMetrics,
      };
}
