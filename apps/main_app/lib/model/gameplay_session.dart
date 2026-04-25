/// A single gameplay session — one play-through of one mini-game.
/// Stored locally in SQLite with a [synced] flag for later upload.
class GameplaySession {
  final String id;
  final String childId;

  /// The assessment run this session belongs to (null for practice sessions).
  final String? assessmentRunId;

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

  /// Number of prompts given during the session.
  final int promptCount;

  /// Total idle time in seconds (no interaction detected).
  final double idleTimeSeconds;

  /// Number of random/off-target touches during the session.
  final int randomTouchCount;

  /// Average time (seconds) from stimulus to first touch (any screen touch).
  final double avgResponseTime;

  /// Average time (seconds) from stimulus to first valid task action.
  final double avgValidResponseTime;

  /// Number of actions that don't contribute to task completion.
  final int offTaskActionCount;

  /// Score representing improvement during the session (-1.0 to 1.0).
  final double improvementScore;

  /// Score representing consistency of performance (0.0 to 1.0).
  final double consistencyScore;

  /// Whether background music was enabled during this session.
  final bool bgMusicEnabled;

  /// Whether haptic feedback was enabled during this session.
  final bool hapticFeedbackEnabled;

  // ── Rubric telemetry fields ──────────────────────────────────────────

  /// Fraction of tasks completed successfully (0.0–1.0).
  final double? taskCompletionRate;

  /// Score representing dependency on prompts (0.0–1.0).
  final double? promptDependencyScore;

  /// Success rate of turn-taking interactions (0.0–1.0).
  final double? turnTakingSuccessRate;

  /// Number of interruptions during the session.
  final int? interruptionCount;

  /// How long the child tolerated waiting (seconds).
  final double? waitingToleranceSeconds;

  /// Time from stimulus to first screen touch (seconds).
  final double? timeToFirstTouch;

  /// Time from stimulus to first valid task action (seconds).
  final double? timeToFirstValidAction;

  /// Total time to complete the session (seconds).
  final double? timeToCompletion;

  /// Sensory condition active during the session.
  final String? sensoryCondition;

  final DateTime startedAt;
  final DateTime endedAt;

  /// Whether this session has been synced to Supabase.
  final bool synced;

  const GameplaySession({
    required this.id,
    required this.childId,
    this.assessmentRunId,
    required this.gameId,
    required this.context,
    required this.score,
    required this.totalItems,
    required this.errorCount,
    required this.totalResponseTimeMs,
    this.retryCount = 0,
    this.hintCount = 0,
    this.promptCount = 0,
    this.idleTimeSeconds = 0.0,
    this.randomTouchCount = 0,
    this.avgResponseTime = 0.0,
    this.avgValidResponseTime = 0.0,
    this.offTaskActionCount = 0,
    this.improvementScore = 0.0,
    this.consistencyScore = 0.0,
    this.bgMusicEnabled = true,
    this.hapticFeedbackEnabled = true,
    this.taskCompletionRate,
    this.promptDependencyScore,
    this.turnTakingSuccessRate,
    this.interruptionCount,
    this.waitingToleranceSeconds,
    this.timeToFirstTouch,
    this.timeToFirstValidAction,
    this.timeToCompletion,
    this.sensoryCondition,
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
        assessmentRunId: assessmentRunId,
        gameId: gameId,
        context: context,
        score: score,
        totalItems: totalItems,
        errorCount: errorCount,
        totalResponseTimeMs: totalResponseTimeMs,
        retryCount: retryCount,
        hintCount: hintCount,
        promptCount: promptCount,
        idleTimeSeconds: idleTimeSeconds,
        randomTouchCount: randomTouchCount,
        avgResponseTime: avgResponseTime,
        avgValidResponseTime: avgValidResponseTime,
        offTaskActionCount: offTaskActionCount,
        improvementScore: improvementScore,
        consistencyScore: consistencyScore,
        bgMusicEnabled: bgMusicEnabled,
        hapticFeedbackEnabled: hapticFeedbackEnabled,
        taskCompletionRate: taskCompletionRate,
        promptDependencyScore: promptDependencyScore,
        turnTakingSuccessRate: turnTakingSuccessRate,
        interruptionCount: interruptionCount,
        waitingToleranceSeconds: waitingToleranceSeconds,
        timeToFirstTouch: timeToFirstTouch,
        timeToFirstValidAction: timeToFirstValidAction,
        timeToCompletion: timeToCompletion,
        sensoryCondition: sensoryCondition,
        startedAt: startedAt,
        endedAt: endedAt,
        synced: true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'child_id': childId,
        'assessment_run_id': assessmentRunId,
        'game_id': gameId,
        'context': context,
        'score': score,
        'total_items': totalItems,
        'error_count': errorCount,
        'total_response_time_ms': totalResponseTimeMs,
        'retry_count': retryCount,
        'hint_count': hintCount,
        'prompt_count': promptCount,
        'idle_time_seconds': idleTimeSeconds,
        'random_touch_count': randomTouchCount,
        'avg_response_time': avgResponseTime,
        'avg_valid_response_time': avgValidResponseTime,
        'off_task_action_count': offTaskActionCount,
        'improvement_score': improvementScore,
        'consistency_score': consistencyScore,
        'bg_music_enabled': bgMusicEnabled ? 1 : 0,
        'haptic_feedback_enabled': hapticFeedbackEnabled ? 1 : 0,
        'task_completion_rate': taskCompletionRate,
        'prompt_dependency_score': promptDependencyScore,
        'turn_taking_success_rate': turnTakingSuccessRate,
        'interruption_count': interruptionCount,
        'waiting_tolerance_seconds': waitingToleranceSeconds,
        'time_to_first_touch': timeToFirstTouch,
        'time_to_first_valid_action': timeToFirstValidAction,
        'time_to_completion': timeToCompletion,
        'sensory_condition': sensoryCondition,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'synced': synced ? 1 : 0,
      };

  factory GameplaySession.fromMap(Map<String, dynamic> map) => GameplaySession(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        assessmentRunId: map['assessment_run_id'] as String?,
        gameId: map['game_id'] as String,
        context: map['context'] as String,
        score: map['score'] as int,
        totalItems: map['total_items'] as int,
        errorCount: map['error_count'] as int,
        totalResponseTimeMs: map['total_response_time_ms'] as int,
        retryCount: (map['retry_count'] as int?) ?? 0,
        hintCount: (map['hint_count'] as int?) ?? 0,
        promptCount: (map['prompt_count'] as int?) ?? 0,
        idleTimeSeconds: (map['idle_time_seconds'] as num?)?.toDouble() ?? 0.0,
        randomTouchCount: (map['random_touch_count'] as int?) ?? 0,
        avgResponseTime: (map['avg_response_time'] as num?)?.toDouble() ?? 0.0,
        avgValidResponseTime: (map['avg_valid_response_time'] as num?)?.toDouble() ?? 0.0,
        offTaskActionCount: (map['off_task_action_count'] as int?) ?? 0,
        improvementScore: (map['improvement_score'] as num?)?.toDouble() ?? 0.0,
        consistencyScore: (map['consistency_score'] as num?)?.toDouble() ?? 0.0,
        bgMusicEnabled: (map['bg_music_enabled'] as int?) == 1,
        hapticFeedbackEnabled: (map['haptic_feedback_enabled'] as int?) == 1,
        taskCompletionRate: (map['task_completion_rate'] as num?)?.toDouble(),
        promptDependencyScore: (map['prompt_dependency_score'] as num?)?.toDouble(),
        turnTakingSuccessRate: (map['turn_taking_success_rate'] as num?)?.toDouble(),
        interruptionCount: map['interruption_count'] as int?,
        waitingToleranceSeconds: (map['waiting_tolerance_seconds'] as num?)?.toDouble(),
        timeToFirstTouch: (map['time_to_first_touch'] as num?)?.toDouble(),
        timeToFirstValidAction: (map['time_to_first_valid_action'] as num?)?.toDouble(),
        timeToCompletion: (map['time_to_completion'] as num?)?.toDouble(),
        sensoryCondition: map['sensory_condition'] as String?,
        startedAt: DateTime.parse(map['started_at'] as String),
        endedAt: DateTime.parse(map['ended_at'] as String),
        synced: (map['synced'] ?? 0) == 1,
      );

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'child_id': childId,
        'assessment_run_id': assessmentRunId,
        'game_id': gameId,
        'context': context,
        'score': score,
        'total_items': totalItems,
        'error_count': errorCount,
        'total_response_time_ms': totalResponseTimeMs,
        'retry_count': retryCount,
        'hint_count': hintCount,
        'prompt_count': promptCount,
        'idle_time_seconds': idleTimeSeconds,
        'random_touch_count': randomTouchCount,
        'avg_response_time': avgResponseTime,
        'avg_valid_response_time': avgValidResponseTime,
        'off_task_action_count': offTaskActionCount,
        'improvement_score': improvementScore,
        'consistency_score': consistencyScore,
        'bg_music_enabled': bgMusicEnabled,
        'haptic_feedback_enabled': hapticFeedbackEnabled,
        'task_completion_rate': taskCompletionRate,
        'prompt_dependency_score': promptDependencyScore,
        'turn_taking_success_rate': turnTakingSuccessRate,
        'interruption_count': interruptionCount,
        'waiting_tolerance_seconds': waitingToleranceSeconds,
        'time_to_first_touch': timeToFirstTouch,
        'time_to_first_valid_action': timeToFirstValidAction,
        'time_to_completion': timeToCompletion,
        'sensory_condition': sensoryCondition,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
      };

  factory GameplaySession.fromSupabase(Map<String, dynamic> map) =>
      GameplaySession(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        assessmentRunId: map['assessment_run_id'] as String?,
        gameId: map['game_id'] as String,
        context: map['context'] as String,
        score: map['score'] as int,
        totalItems: map['total_items'] as int,
        errorCount: map['error_count'] as int,
        totalResponseTimeMs: map['total_response_time_ms'] as int,
        retryCount: (map['retry_count'] as int?) ?? 0,
        hintCount: (map['hint_count'] as int?) ?? 0,
        promptCount: (map['prompt_count'] as int?) ?? 0,
        idleTimeSeconds: (map['idle_time_seconds'] as num?)?.toDouble() ?? 0.0,
        randomTouchCount: (map['random_touch_count'] as int?) ?? 0,
        avgResponseTime:
            (map['avg_response_time'] as num?)?.toDouble() ?? 0.0,
        avgValidResponseTime:
            (map['avg_valid_response_time'] as num?)?.toDouble() ?? 0.0,
        offTaskActionCount: (map['off_task_action_count'] as int?) ?? 0,
        improvementScore:
            (map['improvement_score'] as num?)?.toDouble() ?? 0.0,
        consistencyScore:
            (map['consistency_score'] as num?)?.toDouble() ?? 0.0,
        bgMusicEnabled: map['bg_music_enabled'] as bool? ?? true,
        hapticFeedbackEnabled:
            map['haptic_feedback_enabled'] as bool? ?? true,
        taskCompletionRate:
            (map['task_completion_rate'] as num?)?.toDouble(),
        promptDependencyScore:
            (map['prompt_dependency_score'] as num?)?.toDouble(),
        turnTakingSuccessRate:
            (map['turn_taking_success_rate'] as num?)?.toDouble(),
        interruptionCount: map['interruption_count'] as int?,
        waitingToleranceSeconds:
            (map['waiting_tolerance_seconds'] as num?)?.toDouble(),
        timeToFirstTouch:
            (map['time_to_first_touch'] as num?)?.toDouble(),
        timeToFirstValidAction:
            (map['time_to_first_valid_action'] as num?)?.toDouble(),
        timeToCompletion:
            (map['time_to_completion'] as num?)?.toDouble(),
        sensoryCondition: map['sensory_condition'] as String?,
        startedAt: DateTime.parse(map['started_at'] as String),
        endedAt: DateTime.parse(map['ended_at'] as String),
      );
}
