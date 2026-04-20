import 'game_round_metrics.dart';

/// Assistance level classification for a game session.
///
/// Used by XGBoost models to understand the child's independence level.
enum AssistanceLevel {
  /// Child completed the task without any help.
  independent,

  /// Child needed minimal prompts or hints.
  minimal,

  /// Child required significant guidance to complete.
  guided,
}

/// Core metrics model for a complete game session.
///
/// This model captures all indicators required for XGBoost-based
/// recommendation, difficulty adjustment, and progress analysis.
///
/// ## XGBoost Preprocessing Notes:
/// - All numeric fields are non-null (default to 0)
/// - Categorical fields (assistanceLevel) should be one-hot encoded
/// - Timestamps are stored as ISO8601 strings for Firestore compatibility
/// - Boolean fields should be converted to 0/1 for model training
///
/// ## Usage:
/// ```dart
/// final session = GameSessionMetrics(
///   gameId: 'copy_me',
///   childId: 'child_123',
///   totalRounds: 5,
/// );
/// session.startSession();
/// // ... gameplay ...
/// session.endSession();
/// final firestoreData = session.toFirestoreMap();
/// ```
class GameSessionMetrics {
  // ── Identification ─────────────────────────────────────────────────────

  /// Unique identifier for the game type (e.g., 'copy_me', 'match_it').
  final String gameId;

  /// Unique identifier for this specific play session (UUID v4 recommended).
  final String sessionId;

  /// Unique identifier for the child playing.
  final String childId;

  // ── Timing ─────────────────────────────────────────────────────────────

  /// When the session started (ISO8601 format).
  String? startTime;

  /// When the session ended (ISO8601 format).
  String? endTime;

  /// Total session duration in seconds.
  /// Computed from startTime and endTime.
  int get durationSeconds {
    if (startTime == null || endTime == null) return 0;
    final start = DateTime.parse(startTime!);
    final end = DateTime.parse(endTime!);
    return end.difference(start).inSeconds;
  }

  // ── Performance Core ───────────────────────────────────────────────────

  /// Number of correctly completed tasks/sub-tasks.
  int correctCount = 0;

  /// Number of incorrect attempts.
  int wrongCount = 0;

  /// Total interactions (correct + wrong).
  int get totalInteractions => correctCount + wrongCount;

  /// Accuracy ratio: correct / total interactions (0.0 - 1.0).
  double get accuracy {
    if (totalInteractions == 0) return 0.0;
    return correctCount / totalInteractions;
  }

  /// Task completion rate: completedRounds / totalRounds (0.0 - 1.0).
  double get taskCompletionRate {
    if (totalRounds == 0) return 0.0;
    return completedRounds / totalRounds;
  }

  // ── Assistance & Retries ───────────────────────────────────────────────

  /// Number of times the child restarted a task or round.
  int retryCount = 0;

  /// Number of hints provided to the child.
  int hintCount = 0;

  /// Number of verbal/visual prompts given.
  int promptCount = 0;

  /// Calculated score representing how much assistance was needed.
  /// Higher values indicate more dependency on prompts/hints.
  /// Formula: (hintCount + promptCount * 2) / max(1, totalRounds)
  double get promptDependencyScore {
    if (totalRounds == 0) return 0.0;
    return (hintCount + promptCount * 2) / totalRounds;
  }

  /// Level of assistance required to complete the session.
  AssistanceLevel assistanceLevel = AssistanceLevel.independent;

  // ── Response Timing ────────────────────────────────────────────────────

  /// Average time (seconds) from stimulus to first touch (any screen touch).
  /// This includes both valid and invalid (random) touches.
  double avgResponseTime = 0.0;

  /// Average time (seconds) from stimulus to first valid task action.
  /// Only counts touches that progress toward the task goal.
  double avgValidResponseTime = 0.0;

  /// Time (seconds) from first stimulus to first screen touch.
  double timeToFirstTouch = 0.0;

  /// Time (seconds) from first stimulus to first valid task-related action.
  double timeToFirstValidAction = 0.0;

  /// Time (seconds) from stimulus to task/round completion.
  double timeToCompletion = 0.0;

  // ── Engagement & Behavior ──────────────────────────────────────────────

  /// Total time (seconds) the child was idle (no interaction).
  int idleTimeSeconds = 0;

  /// Number of random/non-task-related screen touches.
  int randomTouchCount = 0;

  /// Number of actions that don't contribute to task completion.
  int offTaskActionCount = 0;

  /// Whether the child exited before completing all rounds.
  bool earlyExit = false;

  // ── Progress Indicators ────────────────────────────────────────────────

  /// Score representing improvement during the session.
  /// Calculated from performance trend across rounds.
  /// Positive values indicate improvement, negative indicate decline.
  double improvementScore = 0.0;

  /// Score representing consistency of performance (0.0 - 1.0).
  /// Higher values mean more consistent response times and accuracy.
  double consistencyScore = 0.0;

  // ── Round Tracking ─────────────────────────────────────────────────────

  /// Total number of rounds planned for this session.
  final int totalRounds;

  /// Number of rounds actually completed.
  int completedRounds = 0;

  /// Whether the main game objective was achieved.
  bool isCompleted = false;

  /// Per-round detailed metrics.
  final List<GameRoundMetrics> rounds = [];

  // ── Metadata ────────────────────────────────────────────────────────────

  /// Game version or build number.
  String? gameVersion;

  /// Device/platform information.
  String? deviceInfo;

  /// Additional game-specific metrics as key-value pairs.
  /// Example for CopyMe: {'imitationSuccess': 0.8, 'demonstrationsNeeded': 2}
  Map<String, dynamic> gameSpecificMetrics = {};

  /// Raw event log for detailed analysis.
  List<Map<String, dynamic>> eventLog = [];

  // ── Internal State ────────────────────────────────────────────────────

  DateTime? _sessionStartTime;
  DateTime? _firstTouchTime;
  DateTime? _firstValidActionTime;
  DateTime? _currentStimulusTime;
  final List<double> _responseTimes = [];
  final List<double> _validResponseTimes = [];
  final List<double> _roundAccuracies = [];

  // ── Constructor ────────────────────────────────────────────────────────

  GameSessionMetrics({
    required this.gameId,
    required this.sessionId,
    required this.childId,
    required this.totalRounds,
    this.gameVersion,
    this.deviceInfo,
  });

  // ── Session Lifecycle ──────────────────────────────────────────────────

  /// Starts the analytics session.
  /// Call when the game begins (typically in onLoad).
  void startSession() {
    _sessionStartTime = DateTime.now();
    startTime = _sessionStartTime!.toIso8601String();
  }

  /// Ends the analytics session.
  /// Call when the game completes or the child exits.
  void endSession() {
    final end = DateTime.now();
    endTime = end.toIso8601String();
    _calculateDerivedMetrics();
  }

  /// Marks the session as having an early exit.
  void markEarlyExit() {
    earlyExit = true;
    endSession();
  }

  // ── Stimulus & Response Tracking ───────────────────────────────────────

  /// Records when a stimulus is presented to the child.
  /// Call when showing instructions, prompts, or new rounds.
  void recordStimulus() {
    _currentStimulusTime = DateTime.now();
    _firstTouchTime = null;
    _firstValidActionTime = null;
  }

  /// Records any screen touch (valid or random).
  /// Call on every tap to track timeToFirstTouch.
  void recordTouch({required double x, required double y, bool isValid = false}) {
    final now = DateTime.now();

    // Track first touch
    if (_firstTouchTime == null && _currentStimulusTime != null) {
      _firstTouchTime = now;
      if (_sessionStartTime != null && startTime != null) {
        // Only calculate if this is the first touch of the entire session
        if (timeToFirstTouch == 0) {
          timeToFirstTouch = now.difference(_sessionStartTime!).inMilliseconds / 1000.0;
        }
      }
    }

    // Track response time
    if (_currentStimulusTime != null) {
      final responseTime = now.difference(_currentStimulusTime!).inMilliseconds / 1000.0;
      _responseTimes.add(responseTime);
    }

    // Track random touches
    if (!isValid) {
      randomTouchCount++;
    }
  }

  /// Records a valid task-related action.
  /// Call when the child performs an action that progresses toward the goal.
  void recordValidAction() {
    final now = DateTime.now();

    // Track first valid action
    if (_firstValidActionTime == null && _currentStimulusTime != null) {
      _firstValidActionTime = now;
      final responseTime = now.difference(_currentStimulusTime!).inMilliseconds / 1000.0;
      _validResponseTimes.add(responseTime);

      // Only set timeToFirstValidAction once per session
      if (timeToFirstValidAction == 0) {
        timeToFirstValidAction = responseTime;
      }
    }
  }

  // ── Performance Tracking ───────────────────────────────────────────────

  /// Records a correct action.
  void recordCorrect() {
    correctCount++;
  }

  /// Records an incorrect/wrong action.
  void recordWrong() {
    wrongCount++;
  }

  /// Records a retry/reset action.
  void recordRetry() {
    retryCount++;
  }

  /// Records when a hint is provided.
  void recordHint() {
    hintCount++;
  }

  /// Records when a prompt is given.
  void recordPrompt() {
    promptCount++;
  }

  /// Records idle time in seconds.
  void recordIdleTime(int seconds) {
    idleTimeSeconds += seconds;
  }

  /// Records an off-task action.
  void recordOffTaskAction() {
    offTaskActionCount++;
  }

  // ── Round Management ───────────────────────────────────────────────────

  /// Starts tracking a new round.
  GameRoundMetrics startRound({int? roundNumber}) {
    final round = GameRoundMetrics(
      roundNumber: roundNumber ?? rounds.length + 1,
    );
    round.startRound();
    rounds.add(round);
    recordStimulus();
    return round;
  }

  /// Completes the current round.
  void completeRound({bool successful = true}) {
    if (rounds.isEmpty) return;

    final round = rounds.last;
    round.completeRound(successful: successful);
    completedRounds++;
    _roundAccuracies.add(round.accuracy);
  }

  /// Marks the entire session as completed successfully.
  void markCompleted() {
    isCompleted = true;
    if (completedRounds == 0) {
      completedRounds = totalRounds;
    }
  }

  // ── Derived Metrics Calculation ────────────────────────────────────────

  void _calculateDerivedMetrics() {
    // Calculate average response times
    if (_responseTimes.isNotEmpty) {
      avgResponseTime = _responseTimes.reduce((a, b) => a + b) / _responseTimes.length;
    }

    if (_validResponseTimes.isNotEmpty) {
      avgValidResponseTime = _validResponseTimes.reduce((a, b) => a + b) / _validResponseTimes.length;
    }

    // Calculate time to completion
    if (_sessionStartTime != null && endTime != null) {
      timeToCompletion = durationSeconds.toDouble();
    }

    // Calculate improvement score
    _calculateImprovementScore();

    // Calculate consistency score
    _calculateConsistencyScore();

    // Determine assistance level
    _determineAssistanceLevel();
  }

  void _calculateImprovementScore() {
    if (_roundAccuracies.length < 2) {
      improvementScore = 0.0;
      return;
    }

    // Compare first half vs second half accuracy
    final mid = _roundAccuracies.length ~/ 2;
    final firstHalf = _roundAccuracies.sublist(0, mid);
    final secondHalf = _roundAccuracies.sublist(mid);

    final firstAvg = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
    final secondAvg = secondHalf.reduce((a, b) => a + b) / secondHalf.length;

    // Scale to -1.0 to 1.0 range
    improvementScore = ((secondAvg - firstAvg) * 2).clamp(-1.0, 1.0);
  }

  void _calculateConsistencyScore() {
    if (_roundAccuracies.length < 2) {
      consistencyScore = 1.0; // Perfect consistency with only one data point
      return;
    }

    // Calculate standard deviation of accuracies
    final mean = _roundAccuracies.reduce((a, b) => a + b) / _roundAccuracies.length;
    final variance = _roundAccuracies
        .map((a) => (a - mean) * (a - mean))
        .reduce((a, b) => a + b) / _roundAccuracies.length;
    final stdDev = variance > 0 ? (variance) : 0.0;

    // Convert to consistency score (inverse of coefficient of variation)
    // Higher score = more consistent
    consistencyScore = (1.0 - (stdDev / (mean + 0.01))).clamp(0.0, 1.0);
  }

  void _determineAssistanceLevel() {
    final dependency = promptDependencyScore;
    if (dependency == 0 && hintCount == 0 && promptCount == 0) {
      assistanceLevel = AssistanceLevel.independent;
    } else if (dependency < 1.0) {
      assistanceLevel = AssistanceLevel.minimal;
    } else {
      assistanceLevel = AssistanceLevel.guided;
    }
  }

  // ── Firestore Serialization ────────────────────────────────────────────

  /// Converts to a Firestore-compatible map.
  ///
  /// All fields are flattened for easy XGBoost preprocessing:
  /// - Numeric fields are non-null doubles/ints
  /// - Categorical fields are strings (to be encoded during preprocessing)
  /// - Nested structures use dot-notation friendly keys
  Map<String, dynamic> toFirestoreMap() {
    return {
      // Identification
      'game_id': gameId,
      'session_id': sessionId,
      'child_id': childId,

      // Timing
      'start_time': startTime,
      'end_time': endTime,
      'duration_seconds': durationSeconds,

      // Performance Core
      'correct_count': correctCount,
      'wrong_count': wrongCount,
      'total_interactions': totalInteractions,
      'accuracy': double.parse(accuracy.toStringAsFixed(4)),
      'task_completion_rate': double.parse(taskCompletionRate.toStringAsFixed(4)),

      // Assistance & Retries
      'retry_count': retryCount,
      'hint_count': hintCount,
      'prompt_count': promptCount,
      'prompt_dependency_score': double.parse(promptDependencyScore.toStringAsFixed(4)),
      'assistance_level': assistanceLevel.name,

      // Response Timing
      'avg_response_time': double.parse(avgResponseTime.toStringAsFixed(3)),
      'avg_valid_response_time': double.parse(avgValidResponseTime.toStringAsFixed(3)),
      'time_to_first_touch': double.parse(timeToFirstTouch.toStringAsFixed(3)),
      'time_to_first_valid_action': double.parse(timeToFirstValidAction.toStringAsFixed(3)),
      'time_to_completion': double.parse(timeToCompletion.toStringAsFixed(3)),

      // Engagement & Behavior
      'idle_time_seconds': idleTimeSeconds,
      'random_touch_count': randomTouchCount,
      'off_task_action_count': offTaskActionCount,
      'early_exit': earlyExit,

      // Progress Indicators
      'improvement_score': double.parse(improvementScore.toStringAsFixed(4)),
      'consistency_score': double.parse(consistencyScore.toStringAsFixed(4)),

      // Round Tracking
      'total_rounds': totalRounds,
      'completed_rounds': completedRounds,
      'is_completed': isCompleted,

      // Round Details (optional, for deep analysis)
      'rounds': rounds.map((r) => r.toFirestoreMap()).toList(),

      // Game-Specific Metrics
      'game_specific': gameSpecificMetrics,

      // Metadata
      'game_version': gameVersion,
      'device_info': deviceInfo,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Creates a GameSessionMetrics from a Firestore map.
  static GameSessionMetrics fromFirestoreMap(Map<String, dynamic> map) {
    final metrics = GameSessionMetrics(
      gameId: map['game_id'] as String,
      sessionId: map['session_id'] as String,
      childId: map['child_id'] as String,
      totalRounds: map['total_rounds'] as int,
      gameVersion: map['game_version'] as String?,
      deviceInfo: map['device_info'] as String?,
    );

    metrics.startTime = map['start_time'] as String?;
    metrics.endTime = map['end_time'] as String?;
    metrics.correctCount = map['correct_count'] as int? ?? 0;
    metrics.wrongCount = map['wrong_count'] as int? ?? 0;
    metrics.retryCount = map['retry_count'] as int? ?? 0;
    metrics.hintCount = map['hint_count'] as int? ?? 0;
    metrics.promptCount = map['prompt_count'] as int? ?? 0;
    metrics.idleTimeSeconds = map['idle_time_seconds'] as int? ?? 0;
    metrics.randomTouchCount = map['random_touch_count'] as int? ?? 0;
    metrics.offTaskActionCount = map['off_task_action_count'] as int? ?? 0;
    metrics.earlyExit = map['early_exit'] as bool? ?? false;
    metrics.avgResponseTime = (map['avg_response_time'] as num?)?.toDouble() ?? 0.0;
    metrics.avgValidResponseTime = (map['avg_valid_response_time'] as num?)?.toDouble() ?? 0.0;
    metrics.timeToFirstTouch = (map['time_to_first_touch'] as num?)?.toDouble() ?? 0.0;
    metrics.timeToFirstValidAction = (map['time_to_first_valid_action'] as num?)?.toDouble() ?? 0.0;
    metrics.timeToCompletion = (map['time_to_completion'] as num?)?.toDouble() ?? 0.0;
    metrics.improvementScore = (map['improvement_score'] as num?)?.toDouble() ?? 0.0;
    metrics.consistencyScore = (map['consistency_score'] as num?)?.toDouble() ?? 0.0;
    metrics.completedRounds = map['completed_rounds'] as int? ?? 0;
    metrics.isCompleted = map['is_completed'] as bool? ?? false;
    metrics.assistanceLevel = AssistanceLevel.values.firstWhere(
      (e) => e.name == map['assistance_level'],
      orElse: () => AssistanceLevel.independent,
    );

    if (map['game_specific'] != null) {
      metrics.gameSpecificMetrics = Map<String, dynamic>.from(map['game_specific'] as Map);
    }

    return metrics;
  }

  // ── XGBoost-Ready CSV Export ───────────────────────────────────────────

  /// Returns a flat map suitable for CSV export and XGBoost training.
  ///
  /// Key differences from toFirestoreMap:
  /// - Boolean fields converted to 0/1
  /// - Categorical fields kept as strings (for one-hot encoding)
  /// - No nested structures
  /// - All numeric fields guaranteed non-null
  Map<String, dynamic> toXgboostMap() {
    final firestoreMap = toFirestoreMap();
    return {
      // Identification
      'game_id': firestoreMap['game_id'],
      'child_id': firestoreMap['child_id'],

      // Target variables (for training)
      'accuracy': firestoreMap['accuracy'],
      'task_completion_rate': firestoreMap['task_completion_rate'],
      'assistance_level': firestoreMap['assistance_level'],

      // Features
      'duration_seconds': firestoreMap['duration_seconds'],
      'correct_count': firestoreMap['correct_count'],
      'wrong_count': firestoreMap['wrong_count'],
      'retry_count': firestoreMap['retry_count'],
      'hint_count': firestoreMap['hint_count'],
      'prompt_count': firestoreMap['prompt_count'],
      'prompt_dependency_score': firestoreMap['prompt_dependency_score'],
      'avg_response_time': firestoreMap['avg_response_time'],
      'avg_valid_response_time': firestoreMap['avg_valid_response_time'],
      'time_to_first_touch': firestoreMap['time_to_first_touch'],
      'time_to_first_valid_action': firestoreMap['time_to_first_valid_action'],
      'time_to_completion': firestoreMap['time_to_completion'],
      'idle_time_seconds': firestoreMap['idle_time_seconds'],
      'random_touch_count': firestoreMap['random_touch_count'],
      'off_task_action_count': firestoreMap['off_task_action_count'],
      'early_exit': earlyExit ? 1 : 0,
      'improvement_score': firestoreMap['improvement_score'],
      'consistency_score': firestoreMap['consistency_score'],
      'total_rounds': firestoreMap['total_rounds'],
      'completed_rounds': firestoreMap['completed_rounds'],
      'is_completed': isCompleted ? 1 : 0,

      // Game-specific features (flattened)
      ..._flattenGameSpecificMetrics(),
    };
  }

  Map<String, dynamic> _flattenGameSpecificMetrics() {
    final flattened = <String, dynamic>{};
    gameSpecificMetrics.forEach((key, value) {
      if (value is num) {
        flattened['gs_$key'] = value;
      } else if (value is bool) {
        flattened['gs_$key'] = value ? 1 : 0;
      } else {
        flattened['gs_$key'] = value.toString();
      }
    });
    return flattened;
  }
}
