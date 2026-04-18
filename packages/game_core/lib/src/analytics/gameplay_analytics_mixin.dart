import 'package:flame/events.dart';
import 'package:flame/game.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Interaction Quality Classification
// ──────────────────────────────────────────────────────────────────────────────

/// Classifies a user's overall interaction quality for a session.
enum InteractionQuality {
  /// Calm, intentional interactions with adequate spacing.
  purposeful,

  /// A mix of fast and slow inputs — typical for younger children.
  mixed,

  /// Rapid, erratic taps suggesting frustration, stimming, or confusion.
  erratic,
}

// ──────────────────────────────────────────────────────────────────────────────
// Raw tap / drag event records
// ──────────────────────────────────────────────────────────────────────────────

/// A lightweight record of a single tap event for post-session analysis.
class _TapRecord {
  final DateTime timestamp;
  final double x;
  final double y;

  const _TapRecord({
    required this.timestamp,
    required this.x,
    required this.y,
  });
}

/// A lightweight record of a single drag-update event.
class _DragRecord {
  final DateTime timestamp;
  final double x;
  final double y;

  const _DragRecord({
    required this.timestamp,
    required this.x,
    required this.y,
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// GameplayAnalyticsMixin
// ──────────────────────────────────────────────────────────────────────────────

/// A reusable mixin that instruments any [FlameGame] with 8 gameplay metrics.
///
/// ## Tracked Indicators
///
/// | # | Metric               | What it measures                                    |
/// |---|----------------------|-----------------------------------------------------|
/// | 1 | **Response Time**    | Time between stimulus and first user input (ms)     |
/// | 2 | **Accuracy**         | correct / total interactions (0.0 – 1.0)            |
/// | 3 | **Errors**           | Count of incorrect choices / miss-taps               |
/// | 4 | **Retries**          | Count of level/round resets                          |
/// | 5 | **Time Spent**       | Wall-clock duration from session start to end (ms)  |
/// | 6 | **Completed**        | Whether the core objective was met                   |
/// | 7 | **Completion Rate**  | completed sub-tasks / total sub-tasks (0.0 – 1.0)  |
/// | 8 | **Interaction**       | Tap/drag quality classification                     |
///
/// ## Usage
///
/// ```dart
/// class MyGame extends FlameGame
///     with TapCallbacks, DragCallbacks, GameplayAnalyticsMixin {
///
///   @override
///   Future<void> onLoad() async {
///     await super.onLoad();
///     analyticsSessionStart(totalSubTasks: 5);
///   }
///
///   void _onCorrectAnswer() {
///     analyticsRecordCorrect();
///     analyticsCompleteSubTask();
///   }
///
///   void _onWrongAnswer() {
///     analyticsRecordError();
///   }
///
///   void _onGameFinished() {
///     analyticsMarkCompleted();
///     analyticsSessionEnd();
///     final payload = toAnalyticsJson();
///     // Push `payload` to Supabase …
///   }
/// }
/// ```
mixin GameplayAnalyticsMixin on FlameGame {
  // ── 1. Response Time ────────────────────────────────────────────────────

  /// Marks the instant a stimulus is presented (e.g. an NPC prompt appears).
  /// Call [analyticsRecordFirstInput] when the child responds.
  DateTime? _analyticsStimulusTime;
  final List<int> _analyticsResponseTimesMs = [];

  /// Call when a game stimulus is shown (prompt, NPC cue, round start, etc.).
  void analyticsPresentStimulus() {
    _analyticsStimulusTime = DateTime.now();
  }

  /// Call on the **first** user input after a stimulus.
  /// Records the elapsed milliseconds and resets the stimulus timer.
  void analyticsRecordFirstInput() {
    if (_analyticsStimulusTime != null) {
      final elapsed =
          DateTime.now().difference(_analyticsStimulusTime!).inMilliseconds;
      _analyticsResponseTimesMs.add(elapsed);
      _analyticsStimulusTime = null; // one-shot per stimulus
    }
  }

  /// Average response time across all recorded stimulus→input pairs (ms).
  double get analyticsAvgResponseTimeMs {
    if (_analyticsResponseTimesMs.isEmpty) return 0;
    final sum = _analyticsResponseTimesMs.reduce((a, b) => a + b);
    return sum / _analyticsResponseTimesMs.length;
  }

  // ── 2. Accuracy ─────────────────────────────────────────────────────────

  int _analyticsCorrectInteractions = 0;
  int _analyticsTotalInteractions = 0;

  /// Record a correct interaction (correct tap, valid match, etc.).
  void analyticsRecordCorrect() {
    _analyticsCorrectInteractions++;
    _analyticsTotalInteractions++;
  }

  /// Record an incorrect interaction.
  /// Also increments [analyticsErrorCount].
  void analyticsRecordError() {
    _analyticsTotalInteractions++;
    _analyticsErrorCount++;
  }

  /// Accuracy ratio: `correct / total`. Returns 0.0 when no interactions.
  double get analyticsAccuracy {
    if (_analyticsTotalInteractions == 0) return 0;
    return _analyticsCorrectInteractions / _analyticsTotalInteractions;
  }

  // ── 3. Errors ───────────────────────────────────────────────────────────

  int _analyticsErrorCount = 0;

  /// Current error count.
  int get analyticsErrorCount => _analyticsErrorCount;

  // ── 4. Retries ──────────────────────────────────────────────────────────

  int _analyticsRetryCount = 0;

  /// Increment when the player triggers a "Try Again" / level reset.
  void analyticsRecordRetry() {
    _analyticsRetryCount++;
  }

  /// Current retry count.
  int get analyticsRetryCount => _analyticsRetryCount;

  // ── 5. Time Spent (session duration) ────────────────────────────────────

  DateTime? _analyticsSessionStartTime;
  DateTime? _analyticsSessionEndTime;

  /// Call once when the level/session begins (typically in [onLoad]).
  /// Also sets [_analyticsTotalSubTasks] when provided.
  void analyticsSessionStart({int totalSubTasks = 0}) {
    _analyticsSessionStartTime = DateTime.now();
    _analyticsSessionEndTime = null;
    if (totalSubTasks > 0) _analyticsTotalSubTasks = totalSubTasks;
  }

  /// Call when the level finishes or the player exits.
  void analyticsSessionEnd() {
    _analyticsSessionEndTime = DateTime.now();
  }

  /// Total session duration in milliseconds. Returns 0 before [analyticsSessionStart].
  int get analyticsTimeSpentMs {
    if (_analyticsSessionStartTime == null) return 0;
    final end = _analyticsSessionEndTime ?? DateTime.now();
    return end.difference(_analyticsSessionStartTime!).inMilliseconds;
  }

  // ── 6. Completed Activities ─────────────────────────────────────────────

  bool _analyticsCompleted = false;

  /// Mark the core objective as completed.
  void analyticsMarkCompleted() {
    _analyticsCompleted = true;
  }

  /// Whether the core game objective was achieved.
  bool get analyticsIsCompleted => _analyticsCompleted;

  // ── 7. Completion Rate ──────────────────────────────────────────────────

  int _analyticsCompletedSubTasks = 0;
  int _analyticsTotalSubTasks = 0;

  /// Set the total number of sub-tasks for the current game instance.
  void analyticsSetTotalSubTasks(int total) {
    _analyticsTotalSubTasks = total;
  }

  /// Increment the completed sub-task counter.
  void analyticsCompleteSubTask() {
    _analyticsCompletedSubTasks++;
  }

  /// Completion rate: `completed / total`. Returns 0.0 when total is 0.
  double get analyticsCompletionRate {
    if (_analyticsTotalSubTasks == 0) return 0;
    return _analyticsCompletedSubTasks / _analyticsTotalSubTasks;
  }

  // ── 8. Interaction Patterns ─────────────────────────────────────────────

  final List<_TapRecord> _analyticsTapRecords = [];
  final List<_DragRecord> _analyticsDragRecords = [];

  /// Threshold (ms) below which consecutive taps are considered "rapid".
  static const int _rapidTapThresholdMs = 250;

  /// Minimum drag points to classify a drag as "smooth".
  static const int _smoothDragMinPoints = 6;

  // ──── Input overrides ──────────────────────────────────────────────────
  // These intercept Flame input events, record analytics data, then
  // delegate to `super` so normal game logic remains unaffected.

  /// Captures tap-down events for interaction pattern analysis.
  /// Games using `TapCallbacks` on the game itself should call `super.onTapDown`.
  void onTapDown(TapDownEvent event) {
    _analyticsTapRecords.add(_TapRecord(
      timestamp: DateTime.now(),
      x: event.localPosition.x,
      y: event.localPosition.y,
    ));

    // Also treat any tap as "first input" if a stimulus is pending.
    analyticsRecordFirstInput();
  }

  /// Captures drag-update events for interaction pattern analysis.
  void onDragUpdate(DragUpdateEvent event) {
    _analyticsDragRecords.add(_DragRecord(
      timestamp: DateTime.now(),
      x: event.localEndPosition.x,
      y: event.localEndPosition.y,
    ));
  }

  // ──── Tap analysis helpers ─────────────────────────────────────────────

  /// Number of "rapid tap" pairs (gap < [_rapidTapThresholdMs]).
  int get _rapidTapCount {
    int count = 0;
    for (var i = 1; i < _analyticsTapRecords.length; i++) {
      final gap = _analyticsTapRecords[i]
          .timestamp
          .difference(_analyticsTapRecords[i - 1].timestamp)
          .inMilliseconds;
      if (gap < _rapidTapThresholdMs) count++;
    }
    return count;
  }

  /// Ratio of rapid taps to total tap intervals.
  double get _rapidTapRatio {
    if (_analyticsTapRecords.length < 2) return 0;
    return _rapidTapCount / (_analyticsTapRecords.length - 1);
  }

  // ──── Drag analysis helpers ────────────────────────────────────────────

  /// Whether drag data suggests smooth, purposeful motion.
  bool get _hasSmoothDrags {
    return _analyticsDragRecords.length >= _smoothDragMinPoints;
  }

  /// Classify overall interaction quality for this session.
  InteractionQuality get analyticsInteractionQuality {
    final tapRatio = _rapidTapRatio;

    // Primarily tap-based sessions
    if (_analyticsTapRecords.length >= 3 && tapRatio > 0.5) {
      return InteractionQuality.erratic;
    }

    // Sessions with smooth drags and low rapid-tap ratio
    if (_hasSmoothDrags && tapRatio < 0.25) {
      return InteractionQuality.purposeful;
    }

    // Default — a mix of both or insufficient data to classify.
    return InteractionQuality.mixed;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Reset
  // ──────────────────────────────────────────────────────────────────────────

  /// Resets **all** analytics state. Useful when replaying the same game
  /// instance or implementing a "Play Again" feature.
  void analyticsReset() {
    _analyticsStimulusTime = null;
    _analyticsResponseTimesMs.clear();
    _analyticsCorrectInteractions = 0;
    _analyticsTotalInteractions = 0;
    _analyticsErrorCount = 0;
    _analyticsRetryCount = 0;
    _analyticsSessionStartTime = null;
    _analyticsSessionEndTime = null;
    _analyticsCompleted = false;
    _analyticsCompletedSubTasks = 0;
    _analyticsTotalSubTasks = 0;
    _analyticsTapRecords.clear();
    _analyticsDragRecords.clear();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Serialisation — Supabase JSONB
  // ──────────────────────────────────────────────────────────────────────────

  /// Bundles every tracked indicator into a single map ready for insertion
  /// into a Supabase `jsonb` column.
  ///
  /// Example output:
  /// ```json
  /// {
  ///   "response_time": {
  ///     "average_ms": 1234.5,
  ///     "samples": [900, 1100, 1350, ...],
  ///     "count": 5
  ///   },
  ///   "accuracy": {
  ///     "ratio": 0.85,
  ///     "correct": 17,
  ///     "total": 20
  ///   },
  ///   "errors": 3,
  ///   "retries": 1,
  ///   "time_spent_ms": 45230,
  ///   "completed": true,
  ///   "completion_rate": {
  ///     "ratio": 1.0,
  ///     "completed_sub_tasks": 5,
  ///     "total_sub_tasks": 5
  ///   },
  ///   "interaction_patterns": {
  ///     "quality": "purposeful",
  ///     "total_taps": 22,
  ///     "rapid_taps": 2,
  ///     "rapid_tap_ratio": 0.095,
  ///     "total_drag_points": 48,
  ///     "has_smooth_drags": true
  ///   },
  ///   "recorded_at": "2026-04-17T14:30:00.000Z"
  /// }
  /// ```
  Map<String, dynamic> toAnalyticsJson() {
    return {
      'response_time': {
        'average_ms': double.parse(analyticsAvgResponseTimeMs.toStringAsFixed(2)),
        'samples': List<int>.from(_analyticsResponseTimesMs),
        'count': _analyticsResponseTimesMs.length,
      },
      'accuracy': {
        'ratio': double.parse(analyticsAccuracy.toStringAsFixed(4)),
        'correct': _analyticsCorrectInteractions,
        'total': _analyticsTotalInteractions,
      },
      'errors': _analyticsErrorCount,
      'retries': _analyticsRetryCount,
      'time_spent_ms': analyticsTimeSpentMs,
      'completed': _analyticsCompleted,
      'completion_rate': {
        'ratio': double.parse(analyticsCompletionRate.toStringAsFixed(4)),
        'completed_sub_tasks': _analyticsCompletedSubTasks,
        'total_sub_tasks': _analyticsTotalSubTasks,
      },
      'interaction_patterns': {
        'quality': analyticsInteractionQuality.name,
        'total_taps': _analyticsTapRecords.length,
        'rapid_taps': _rapidTapCount,
        'rapid_tap_ratio': double.parse(_rapidTapRatio.toStringAsFixed(4)),
        'total_drag_points': _analyticsDragRecords.length,
        'has_smooth_drags': _hasSmoothDrags,
      },
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
