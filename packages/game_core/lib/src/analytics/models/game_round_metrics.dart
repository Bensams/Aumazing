/// Detailed metrics for a single game round/task.
///
/// Tracks per-round performance indicators that aggregate into
/// the session-level metrics in [GameSessionMetrics].
///
/// ## Usage:
/// ```dart
/// final round = session.startRound(roundNumber: 1);
/// // ... gameplay ...
/// round.recordCorrect();
/// round.recordWrong();
/// session.completeRound(successful: true);
/// ```
class GameRoundMetrics {
  // ── Identification ─────────────────────────────────────────────────────

  /// Round number within the session (1-indexed).
  final int roundNumber;

  /// Optional round identifier or name.
  String? roundId;

  // ── Timing ─────────────────────────────────────────────────────────────

  /// When the round started (ISO8601 format).
  String? startTime;

  /// When the round ended (ISO8601 format).
  String? endTime;

  /// Round duration in seconds.
  int get durationSeconds {
    if (startTime == null || endTime == null) return 0;
    final start = DateTime.parse(startTime!);
    final end = DateTime.parse(endTime!);
    return end.difference(start).inSeconds;
  }

  // ── Performance ────────────────────────────────────────────────────────

  /// Number of correct actions in this round.
  int correctCount = 0;

  /// Number of incorrect actions in this round.
  int wrongCount = 0;

  /// Total interactions in this round.
  int get totalInteractions => correctCount + wrongCount;

  /// Accuracy for this round: correct / total (0.0 - 1.0).
  double get accuracy {
    if (totalInteractions == 0) return 0.0;
    return correctCount / totalInteractions;
  }

  // ── Response Timing ──────────────────────────────────────────────────────

  /// Time (seconds) from stimulus to first touch in this round.
  double timeToFirstTouch = 0.0;

  /// Time (seconds) from stimulus to first valid action in this round.
  double timeToFirstValidAction = 0.0;

  /// Time (seconds) from stimulus to round completion.
  double timeToCompletion = 0.0;

  // ── Assistance ───────────────────────────────────────────────────────────

  /// Number of hints provided during this round.
  int hintCount = 0;

  /// Number of prompts given during this round.
  int promptCount = 0;

  /// Number of retries in this round.
  int retryCount = 0;

  // ── Engagement ───────────────────────────────────────────────────────────

  /// Time (seconds) the child was idle during this round.
  int idleTimeSeconds = 0;

  /// Number of random/non-task touches in this round.
  int randomTouchCount = 0;

  /// Number of off-task actions in this round.
  int offTaskActionCount = 0;

  // ── Result ───────────────────────────────────────────────────────────────

  /// Whether the round was completed successfully.
  bool isSuccessful = false;

  /// Whether the round was abandoned/ended early.
  bool isAbandoned = false;

  // ── Game-Specific Data ───────────────────────────────────────────────────

  /// Additional metrics specific to the game type.
  /// Example for CopyMe: {'sequenceLength': 3, 'patternCorrect': true}
  Map<String, dynamic> gameSpecificData = {};

  // ── Internal State ───────────────────────────────────────────────────────

  DateTime? _roundStartTime;
  DateTime? _stimulusTime;
  bool _firstTouchRecorded = false;
  bool _firstValidActionRecorded = false;

  // ── Constructor ─────────────────────────────────────────────────────────

  GameRoundMetrics({
    required this.roundNumber,
    this.roundId,
  });

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Starts the round timer.
  void startRound() {
    _roundStartTime = DateTime.now();
    startTime = _roundStartTime!.toIso8601String();
  }

  /// Completes the round.
  void completeRound({bool successful = true}) {
    final end = DateTime.now();
    endTime = end.toIso8601String();
    isSuccessful = successful;

    if (_roundStartTime != null) {
      timeToCompletion = end.difference(_roundStartTime!).inMilliseconds / 1000.0;
    }
  }

  /// Marks the round as abandoned.
  void abandonRound() {
    isAbandoned = true;
    completeRound(successful: false);
  }

  // ── Event Recording ───────────────────────────────────────────────────────

  /// Records when the stimulus is presented for this round.
  void recordStimulus() {
    _stimulusTime = DateTime.now();
    _firstTouchRecorded = false;
    _firstValidActionRecorded = false;
  }

  /// Records any touch in the round.
  void recordTouch({bool isValid = false}) {
    final now = DateTime.now();

    if (!_firstTouchRecorded && _stimulusTime != null) {
      _firstTouchRecorded = true;
      timeToFirstTouch = now.difference(_stimulusTime!).inMilliseconds / 1000.0;
    }

    if (!isValid) {
      randomTouchCount++;
    }
  }

  /// Records a valid action in the round.
  void recordValidAction() {
    final now = DateTime.now();

    if (!_firstValidActionRecorded && _stimulusTime != null) {
      _firstValidActionRecorded = true;
      timeToFirstValidAction = now.difference(_stimulusTime!).inMilliseconds / 1000.0;
    }
  }

  /// Records a correct action.
  void recordCorrect() {
    correctCount++;
    recordValidAction();
  }

  /// Records an incorrect action.
  void recordWrong() {
    wrongCount++;
  }

  /// Records a hint.
  void recordHint() {
    hintCount++;
  }

  /// Records a prompt.
  void recordPrompt() {
    promptCount++;
  }

  /// Records a retry.
  void recordRetry() {
    retryCount++;
  }

  /// Records idle time.
  void recordIdleTime(int seconds) {
    idleTimeSeconds += seconds;
  }

  /// Records an off-task action.
  void recordOffTaskAction() {
    offTaskActionCount++;
  }

  // ── Firestore Serialization ───────────────────────────────────────────────

  /// Converts to a Firestore-compatible map.
  Map<String, dynamic> toFirestoreMap() {
    return {
      'round_number': roundNumber,
      'round_id': roundId,
      'start_time': startTime,
      'end_time': endTime,
      'duration_seconds': durationSeconds,
      'correct_count': correctCount,
      'wrong_count': wrongCount,
      'total_interactions': totalInteractions,
      'accuracy': double.parse(accuracy.toStringAsFixed(4)),
      'time_to_first_touch': double.parse(timeToFirstTouch.toStringAsFixed(3)),
      'time_to_first_valid_action': double.parse(timeToFirstValidAction.toStringAsFixed(3)),
      'time_to_completion': double.parse(timeToCompletion.toStringAsFixed(3)),
      'hint_count': hintCount,
      'prompt_count': promptCount,
      'retry_count': retryCount,
      'idle_time_seconds': idleTimeSeconds,
      'random_touch_count': randomTouchCount,
      'off_task_action_count': offTaskActionCount,
      'is_successful': isSuccessful,
      'is_abandoned': isAbandoned,
      'game_specific': gameSpecificData,
    };
  }

  /// Creates from a Firestore map.
  static GameRoundMetrics fromFirestoreMap(Map<String, dynamic> map) {
    final round = GameRoundMetrics(
      roundNumber: map['round_number'] as int,
      roundId: map['round_id'] as String?,
    );

    round.startTime = map['start_time'] as String?;
    round.endTime = map['end_time'] as String?;
    round.correctCount = map['correct_count'] as int? ?? 0;
    round.wrongCount = map['wrong_count'] as int? ?? 0;
    round.timeToFirstTouch = (map['time_to_first_touch'] as num?)?.toDouble() ?? 0.0;
    round.timeToFirstValidAction = (map['time_to_first_valid_action'] as num?)?.toDouble() ?? 0.0;
    round.timeToCompletion = (map['time_to_completion'] as num?)?.toDouble() ?? 0.0;
    round.hintCount = map['hint_count'] as int? ?? 0;
    round.promptCount = map['prompt_count'] as int? ?? 0;
    round.retryCount = map['retry_count'] as int? ?? 0;
    round.idleTimeSeconds = map['idle_time_seconds'] as int? ?? 0;
    round.randomTouchCount = map['random_touch_count'] as int? ?? 0;
    round.offTaskActionCount = map['off_task_action_count'] as int? ?? 0;
    round.isSuccessful = map['is_successful'] as bool? ?? false;
    round.isAbandoned = map['is_abandoned'] as bool? ?? false;

    if (map['game_specific'] != null) {
      round.gameSpecificData = Map<String, dynamic>.from(map['game_specific'] as Map);
    }

    return round;
  }
}
