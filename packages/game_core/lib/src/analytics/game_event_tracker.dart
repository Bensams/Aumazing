import 'dart:async';
import 'dart:math';

/// Types of events that can be tracked during gameplay.
///
/// These events provide granular visibility into child interactions
/// for ML analysis and debugging.
enum GameEventType {
  // Session events
  sessionStarted,
  sessionEnded,

  // Round events
  roundStarted,
  roundCompleted,
  roundAbandoned,

  // Stimulus events
  stimulusPresented,

  // Interaction events
  touchDown,
  touchUp,
  dragStart,
  dragUpdate,
  dragEnd,

  // Action events
  validAction,
  invalidAction,
  correctResponse,
  incorrectResponse,

  // Assistance events
  hintProvided,
  promptProvided,
  demonstrationProvided,

  // State events
  retryInitiated,
  idlePeriodDetected,
  offTaskBehavior,
  earlyExit,

  // Game-specific (extensible)
  custom,
}

/// A recorded gameplay event with timing and metadata.
///
/// This is a lightweight event record used for detailed
/// chronological analysis and replay.
class GameEvent {
  final String id;
  final GameEventType type;
  final DateTime timestamp;
  final int? roundNumber;
  final String? category;
  final Map<String, dynamic> properties;

  GameEvent({
    required this.type,
    DateTime? timestamp,
    this.roundNumber,
    this.category,
    this.properties = const {},
  })  : id = _generateId(),
        timestamp = timestamp ?? DateTime.now();

  static String _generateId() {
    return 'evt_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(100000)}';
  }

  /// Duration in milliseconds since another event.
  int timeSince(GameEvent other) {
    return timestamp.difference(other.timestamp).inMilliseconds;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'round_number': roundNumber,
      'category': category,
      'properties': properties,
    };
  }

  @override
  String toString() {
    return 'GameEvent($type, round: $roundNumber, at: ${timestamp.toIso8601String()})';
  }
}

/// Tracker for detailed gameplay events.
///
/// Provides fine-grained event logging for:
/// - ML feature extraction
/// - Replay and debugging
/// - Behavioral analysis
/// - Parent/therapist reporting
///
/// ## Usage:
/// ```dart
/// class MyGame {
///   final _tracker = GameEventTracker();
///
///   void onRoundStart() {
///     _tracker.startRound(1);
///     _tracker.trackStimulus();
///   }
///
///   void onCorrect() {
///     _tracker.trackCorrect(extra: {'item': 'circle'});
///   }
/// }
/// ```
class GameEventTracker {
  // ── Event Storage ──────────────────────────────────────────────────────────

  final List<GameEvent> _events = [];
  final StreamController<GameEvent> _eventStream = StreamController<GameEvent>.broadcast();

  /// Stream of all tracked events for real-time processing.
  Stream<GameEvent> get eventStream => _eventStream.stream;

  // ── State Tracking ──────────────────────────────────────────────────────────

  int? _currentRoundNumber;
  DateTime? _sessionStartTime;
  DateTime? _roundStartTime;
  DateTime? _lastStimulusTime;

  // ── Statistics ─────────────────────────────────────────────────────────────

  int _totalTouches = 0;
  int _validTouches = 0;
  int _totalRounds = 0;
  int _completedRounds = 0;

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Maximum number of events to keep in memory (for memory management).
  final int maxEventsInMemory;

  /// Whether to buffer events for batch processing.
  final bool enableBuffering;

  GameEventTracker({
    this.maxEventsInMemory = 10000,
    this.enableBuffering = true,
  });

  // ── Session Lifecycle ────────────────────────────────────────────────────────

  /// Starts a new session.
  void startSession({Map<String, dynamic>? metadata}) {
    _sessionStartTime = DateTime.now();
    _currentRoundNumber = null;
    _events.clear();

    _track(GameEventType.sessionStarted, properties: {
      'session_start': _sessionStartTime!.toIso8601String(),
      ...?metadata,
    });
  }

  /// Ends the current session.
  void endSession({Map<String, dynamic>? summary}) {
    _track(GameEventType.sessionEnded, properties: {
      'session_end': DateTime.now().toIso8601String(),
      'total_events': _events.length,
      'total_rounds': _totalRounds,
      'completed_rounds': _completedRounds,
      ...?summary,
    });

    if (!_eventStream.isClosed) {
      _eventStream.close();
    }
  }

  // ── Round Lifecycle ──────────────────────────────────────────────────────────

  /// Starts tracking a new round.
  void startRound(int roundNumber, {Map<String, dynamic>? roundData}) {
    _currentRoundNumber = roundNumber;
    _roundStartTime = DateTime.now();
    _totalRounds++;

    _track(GameEventType.roundStarted, properties: {
      'round_number': roundNumber,
      'round_start': _roundStartTime!.toIso8601String(),
      ...?roundData,
    });
  }

  /// Marks the current round as completed.
  void completeRound({bool successful = true, Map<String, dynamic>? result}) {
    _completedRounds++;

    _track(GameEventType.roundCompleted, properties: {
      'successful': successful,
      'round_end': DateTime.now().toIso8601String(),
      ...?result,
    });
  }

  /// Marks the current round as abandoned.
  void abandonRound({String? reason}) {
    _track(GameEventType.roundAbandoned, properties: {
      'reason': reason,
      'abandon_time': DateTime.now().toIso8601String(),
    });
  }

  // ── Stimulus Tracking ──────────────────────────────────────────────────────────

  /// Records when a stimulus is presented.
  void trackStimulus({String? stimulusType, String? stimulusId, Map<String, dynamic>? data}) {
    _lastStimulusTime = DateTime.now();

    _track(GameEventType.stimulusPresented, properties: {
      'stimulus_type': stimulusType,
      'stimulus_id': stimulusId,
      ...?data,
    });
  }

  // ── Touch & Interaction Tracking ───────────────────────────────────────────────

  /// Records a touch down event.
  void trackTouchDown(double x, double y, {bool isValid = false, String? targetId}) {
    _totalTouches++;
    if (isValid) _validTouches++;

    final now = DateTime.now();

    // Calculate time since stimulus
    int? timeSinceStimulusMs;
    if (_lastStimulusTime != null) {
      timeSinceStimulusMs = now.difference(_lastStimulusTime!).inMilliseconds;
    }

    _track(GameEventType.touchDown, properties: {
      'x': x,
      'y': y,
      'is_valid': isValid,
      'target_id': targetId,
      'time_since_stimulus_ms': timeSinceStimulusMs,
    });
  }

  /// Records a touch up event.
  void trackTouchUp(double x, double y, {String? targetId}) {
    _track(GameEventType.touchUp, properties: {
      'x': x,
      'y': y,
      'target_id': targetId,
    });
  }

  /// Records drag events.
  void trackDragStart(double x, double y) {
    _track(GameEventType.dragStart, properties: {'x': x, 'y': y});
  }

  void trackDragUpdate(double x, double y, {double? velocity}) {
    _track(GameEventType.dragUpdate, properties: {
      'x': x,
      'y': y,
      'velocity': velocity,
    });
  }

  void trackDragEnd(double x, double y, {bool completed = false}) {
    _track(GameEventType.dragEnd, properties: {
      'x': x,
      'y': y,
      'completed': completed,
    });
  }

  // ── Action Tracking ────────────────────────────────────────────────────────────

  /// Records a valid task-related action.
  void trackValidAction({String? actionType, Map<String, dynamic>? details}) {
    _track(GameEventType.validAction, properties: {
      'action_type': actionType,
      ...?details,
    });
  }

  /// Records an invalid/off-task action.
  void trackInvalidAction({String? reason, Map<String, dynamic>? details}) {
    _track(GameEventType.invalidAction, properties: {
      'reason': reason,
      ...?details,
    });
  }

  /// Records a correct response.
  void trackCorrect({Map<String, dynamic>? extra}) {
    _track(GameEventType.correctResponse, properties: extra ?? {});
    trackValidAction(actionType: 'correct_response');
  }

  /// Records an incorrect response.
  void trackIncorrect({String? expected, String? actual, Map<String, dynamic>? extra}) {
    _track(GameEventType.incorrectResponse, properties: {
      'expected': expected,
      'actual': actual,
      ...?extra,
    });
  }

  // ── Assistance Tracking ────────────────────────────────────────────────────────

  /// Records when a hint is provided.
  void trackHint({String? hintType, String? content}) {
    _track(GameEventType.hintProvided, properties: {
      'hint_type': hintType,
      'content': content,
    });
  }

  /// Records when a prompt is given.
  void trackPrompt({String? promptType, String? content, int? repeatCount}) {
    _track(GameEventType.promptProvided, properties: {
      'prompt_type': promptType,
      'content': content,
      'repeat_count': repeatCount,
    });
  }

  /// Records when a demonstration is shown.
  void trackDemonstration({String? demoType, int? durationMs}) {
    _track(GameEventType.demonstrationProvided, properties: {
      'demo_type': demoType,
      'duration_ms': durationMs,
    });
  }

  // ── State Tracking ─────────────────────────────────────────────────────────────

  /// Records a retry action.
  void trackRetry({String? retryReason}) {
    _track(GameEventType.retryInitiated, properties: {
      'retry_reason': retryReason,
    });
  }

  /// Records detected idle time.
  void trackIdlePeriod(int seconds, {String? context}) {
    _track(GameEventType.idlePeriodDetected, properties: {
      'idle_seconds': seconds,
      'context': context,
    });
  }

  /// Records off-task behavior.
  void trackOffTaskBehavior({String? behavior, String? trigger}) {
    _track(GameEventType.offTaskBehavior, properties: {
      'behavior': behavior,
      'trigger': trigger,
    });
  }

  /// Records an early exit.
  void trackEarlyExit({String? reason, int? roundsCompleted}) {
    _track(GameEventType.earlyExit, properties: {
      'reason': reason,
      'rounds_completed': roundsCompleted,
    });
  }

  // ── Custom Events ──────────────────────────────────────────────────────────────

  /// Records a custom event type.
  void trackCustom(String category, {Map<String, dynamic>? data}) {
    _track(GameEventType.custom, category: category, properties: data ?? {});
  }

  // ── Data Access ────────────────────────────────────────────────────────────────

  /// Returns all recorded events.
  List<GameEvent> getAllEvents() => List.unmodifiable(_events);

  /// Returns events for a specific round.
  List<GameEvent> getRoundEvents(int roundNumber) {
    return _events.where((e) => e.roundNumber == roundNumber).toList();
  }

  /// Returns events of a specific type.
  List<GameEvent> getEventsByType(GameEventType type) {
    return _events.where((e) => e.type == type).toList();
  }

  /// Returns events within a time range.
  List<GameEvent> getEventsInRange(DateTime start, DateTime end) {
    return _events.where((e) => e.timestamp.isAfter(start) && e.timestamp.isBefore(end)).toList();
  }

  /// Returns statistics about the tracked events.
  Map<String, dynamic> getStatistics() {
    return {
      'total_events': _events.length,
      'total_touches': _totalTouches,
      'valid_touches': _validTouches,
      'total_rounds': _totalRounds,
      'completed_rounds': _completedRounds,
      'touch_accuracy': _totalTouches > 0 ? _validTouches / _totalTouches : 0.0,
      'round_completion_rate': _totalRounds > 0 ? _completedRounds / _totalRounds : 0.0,
    };
  }

  /// Exports all events as a list of maps (for Firestore/JSON).
  List<Map<String, dynamic>> exportEvents() {
    return _events.map((e) => e.toMap()).toList();
  }

  /// Clears all events (use with caution).
  void clear() {
    _events.clear();
    _totalTouches = 0;
    _validTouches = 0;
    _totalRounds = 0;
    _completedRounds = 0;
  }

  // ── Private Methods ────────────────────────────────────────────────────────────

  void _track(GameEventType type, {String? category, Map<String, dynamic>? properties}) {
    // Manage memory by removing old events if limit exceeded
    if (_events.length >= maxEventsInMemory && enableBuffering) {
      _events.removeAt(0);
    }

    final event = GameEvent(
      type: type,
      roundNumber: _currentRoundNumber,
      category: category,
      properties: properties ?? {},
    );

    _events.add(event);

    if (!_eventStream.isClosed) {
      _eventStream.add(event);
    }
  }
}
