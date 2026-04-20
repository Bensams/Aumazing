import 'dart:async';
import 'dart:math';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import 'models/models.dart';
import 'game_event_tracker.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Re-exports for backward compatibility
// ──────────────────────────────────────────────────────────────────────────────

export 'models/models.dart' show AssistanceLevel;
export 'game_event_tracker.dart' show GameEventTracker, GameEventType, GameEvent;

// ──────────────────────────────────────────────────────────────────────────────
// Enhanced Gameplay Analytics Mixin
// ──────────────────────────────────────────────────────────────────────────────

/// Enhanced mixin that instruments any [FlameGame] with comprehensive XGBoost-ready
/// gameplay analytics.
///
/// ## Tracked Indicators (All XGBoost-Ready)
///
/// | Category | Metric | Description |
/// |------------|--------|-------------|
/// | **Identification** | gameId, sessionId, childId | Session identifiers |
/// | **Timing** | durationSeconds, startTime, endTime | Session timing |
/// | **Performance** | accuracy, taskCompletionRate, correctCount, wrongCount | Core metrics |
/// | **Assistance** | hintCount, promptCount, retryCount, promptDependencyScore | Help needed |
/// | **Assistance Level** | independent/minimal/guided | Classification |
/// | **Response Times** | avgResponseTime, avgValidResponseTime | Speed metrics |
/// | **First Actions** | timeToFirstTouch, timeToFirstValidAction | Engagement |
/// | **Completion** | timeToCompletion | Total task time |
/// | **Engagement** | idleTimeSeconds, randomTouchCount, offTaskActionCount | Behavior |
/// | **Progress** | improvementScore, consistencyScore | Learning indicators |
///
/// ## Usage:
/// ```dart
/// class MyGame extends FlameGame
///     with TapCallbacks, DragCallbacks, EnhancedGameplayAnalyticsMixin {
///
///   @override
///   Future<void> onLoad() async {
///     await super.onLoad();
///     analyticsInitialize(
///       gameId: 'match_it',
///       childId: 'child_123',
///       totalRounds: 5,
///     );
///     analyticsStartSession();
///   }
///
///   void onStimulus() {
///     analyticsShowStimulus();  // Records timeToFirstTouch baseline
///   }
///
///   void onCorrect() {
///     analyticsRecordCorrect();    // Also records valid action
///     analyticsRecordValidAction();  // Explicit valid action
///   }
///
///   void onWrong() {
///     analyticsRecordWrong();
///   }
///
///   void onGameComplete() {
///     analyticsCompleteSession();  // Calculates all derived metrics
///     final firestoreData = analyticsToFirestoreMap();
///     // Send to Firestore...
///   }
/// }
/// ```
mixin EnhancedGameplayAnalyticsMixin on FlameGame {
  // ── Core Models ───────────────────────────────────────────────────────────

  GameSessionMetrics? _sessionMetrics;
  GameRoundMetrics? _currentRound;
  late final GameEventTracker _eventTracker = GameEventTracker();

  // ── Timing State ──────────────────────────────────────────────────────────

  DateTime? _stimulusTime;
  DateTime? _firstTouchTime;
  DateTime? _firstValidActionTime;
  DateTime? _lastInteractionTime;
  Timer? _idleTimer;

  final List<double> _responseTimes = [];
  final List<double> _validResponseTimes = [];

  // ── Touch Tracking ──────────────────────────────────────────────────────────

  int _totalTouches = 0;
  int _validTouches = 0;
  final List<Offset> _touchPositions = [];

  // ── Configuration ───────────────────────────────────────────────────────────
  // Stored in _sessionMetrics, no need for separate fields

  // ── Public Getters ───────────────────────────────────────────────────────────

  /// The session metrics model (null if not initialized).
  GameSessionMetrics? get analyticsSession => _sessionMetrics;

  /// The current round metrics (null if no active round).
  GameRoundMetrics? get analyticsCurrentRound => _currentRound;

  /// The event tracker for detailed logging.
  GameEventTracker get analyticsEventTracker => _eventTracker;

  /// Whether a session is currently active.
  bool get analyticsIsSessionActive => _sessionMetrics != null && _sessionMetrics!.startTime != null;

  /// Whether a round is currently active.
  bool get analyticsIsRoundActive => _currentRound != null && _currentRound!.startTime != null;

  // ── Core Timing Metrics ──────────────────────────────────────────────────────

  /// Average response time from stimulus to any touch (seconds).
  double get analyticsAvgResponseTime {
    if (_responseTimes.isEmpty) return 0.0;
    return _responseTimes.reduce((a, b) => a + b) / _responseTimes.length;
  }

  /// Average response time from stimulus to valid action (seconds).
  double get analyticsAvgValidResponseTime {
    if (_validResponseTimes.isEmpty) return 0.0;
    return _validResponseTimes.reduce((a, b) => a + b) / _validResponseTimes.length;
  }

  /// Time from session start to first touch (seconds).
  double get analyticsTimeToFirstTouch {
    if (_sessionMetrics?.startTime == null || _firstTouchTime == null) return 0.0;
    return _firstTouchTime!.difference(DateTime.parse(_sessionMetrics!.startTime!)).inMilliseconds / 1000.0;
  }

  /// Time from session start to first valid action (seconds).
  double get analyticsTimeToFirstValidAction {
    if (_sessionMetrics?.startTime == null || _firstValidActionTime == null) return 0.0;
    return _firstValidActionTime!.difference(DateTime.parse(_sessionMetrics!.startTime!)).inMilliseconds / 1000.0;
  }

  // ── Derived Metrics ───────────────────────────────────────────────────────────

  /// Total number of touches recorded.
  int get analyticsTotalTouches => _totalTouches;

  /// Number of valid (task-related) touches.
  int get analyticsValidTouches => _validTouches;

  /// Ratio of valid touches to total touches.
  double get analyticsTouchValidityRatio => _totalTouches > 0 ? _validTouches / _totalTouches : 0.0;

  /// Current accumulated idle time in seconds.
  int get analyticsIdleTimeSeconds => _sessionMetrics?.idleTimeSeconds ?? 0;

  // ── Initialization ─────────────────────────────────────────────────────────────

  /// Initializes the analytics system.
  ///
  /// Must be called before [analyticsStartSession].
  /// [gameId] - Unique game type identifier (e.g., 'copy_me', 'match_it')
  /// [childId] - Unique child identifier
  /// [totalRounds] - Expected number of rounds in this session
  /// [gameVersion] - Optional game version string
  void analyticsInitialize({
    required String gameId,
    required String childId,
    required int totalRounds,
    String? gameVersion,
    String? deviceInfo,
  }) {
    _sessionMetrics = GameSessionMetrics(
      gameId: gameId,
      sessionId: _generateSessionId(gameId, childId),
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion,
      deviceInfo: deviceInfo,
    );

    _eventTracker.startSession(metadata: {
      'game_id': gameId,
      'child_id': childId,
      'total_rounds': totalRounds,
    });
  }

  String _generateSessionId(String gameId, String childId) {
    return '${gameId}_${childId}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  // ── Session Lifecycle ──────────────────────────────────────────────────────────

  /// Starts the analytics session.
  ///
  /// Call when the game begins (typically in [onLoad]).
  void analyticsStartSession() {
    if (_sessionMetrics == null) {
      throw StateError('analyticsInitialize() must be called before analyticsStartSession()');
    }

    _sessionMetrics!.startSession();
    _startIdleDetection();

    _eventTracker.startSession(metadata: {
      'session_id': _sessionMetrics!.sessionId,
    });
  }

  /// Completes and ends the session.
  ///
  /// Call when the game finishes normally. Calculates all derived metrics.
  void analyticsCompleteSession() {
    if (_sessionMetrics == null) return;

    _stopIdleDetection();

    // Finalize current round if active
    if (_currentRound != null && _currentRound!.endTime == null) {
      analyticsCompleteRound(successful: false);
    }

    // Update session with calculated metrics
    _sessionMetrics!.avgResponseTime = analyticsAvgResponseTime;
    _sessionMetrics!.avgValidResponseTime = analyticsAvgValidResponseTime;
    _sessionMetrics!.timeToFirstTouch = analyticsTimeToFirstTouch;
    _sessionMetrics!.timeToFirstValidAction = analyticsTimeToFirstValidAction;

    _sessionMetrics!.endSession();
    _eventTracker.endSession();
  }

  /// Records an early exit from the session.
  void analyticsRecordExit() {
    if (_sessionMetrics == null) return;

    _sessionMetrics!.markEarlyExit();
    _eventTracker.trackEarlyExit();
    analyticsCompleteSession();
  }

  // ── Round Lifecycle ───────────────────────────────────────────────────────────

  /// Starts a new round.
  ///
  /// [roundNumber] - Optional round number (auto-increments if not provided)
  /// [roundId] - Optional round identifier
  void analyticsStartRound({int? roundNumber, String? roundId}) {
    if (_sessionMetrics == null) return;

    // Complete previous round if exists
    if (_currentRound != null && _currentRound!.endTime == null) {
      analyticsCompleteRound(successful: false);
    }

    _currentRound = _sessionMetrics!.startRound(roundNumber: roundNumber);
    if (roundId != null) {
      _currentRound!.roundId = roundId;
    }

    _stimulusTime = null; // Reset for new round
    _eventTracker.startRound(_currentRound!.roundNumber);
  }

  /// Completes the current round.
  ///
  /// [successful] - Whether the round was completed successfully
  void analyticsCompleteRound({required bool successful}) {
    if (_sessionMetrics == null || _currentRound == null) return;

    _sessionMetrics!.completeRound(successful: successful);

    if (successful) {
      _eventTracker.completeRound();
    } else {
      _eventTracker.abandonRound(reason: 'Round completed without success');
    }

    _currentRound = null;
  }

  /// Marks the entire session as completed.
  void analyticsMarkCompleted() {
    if (_sessionMetrics == null) return;
    _sessionMetrics!.markCompleted();
  }

  // ── Stimulus & Response ───────────────────────────────────────────────────────

  /// Records when a stimulus is presented.
  ///
  /// This resets the response timing baseline for measuring
  /// timeToFirstTouch and timeToFirstValidAction.
  void analyticsShowStimulus() {
    _stimulusTime = DateTime.now();
    _sessionMetrics?.recordStimulus();
    _currentRound?.recordStimulus();
    _eventTracker.trackStimulus();
  }

  /// Records any screen touch (valid or random).
  ///
  /// [position] - Screen coordinates
  /// [isValid] - Whether this is a task-related touch (true) or random touch (false)
  void analyticsRecordTouch(Offset position, {bool isValid = false}) {
    _resetIdleTimer();
    _totalTouches++;

    final now = DateTime.now();

    // Track first touch of session
    if (_firstTouchTime == null) {
      _firstTouchTime = now;
    }

    // Track response time from stimulus
    if (_stimulusTime != null) {
      final responseTime = now.difference(_stimulusTime!).inMilliseconds / 1000.0;
      _responseTimes.add(responseTime);
    }

    if (isValid) {
      _validTouches++;
    } else {
      _sessionMetrics?.recordTouch(x: position.dx, y: position.dy, isValid: false);
      _currentRound?.recordTouch(isValid: false);
    }

    _touchPositions.add(position);
    _eventTracker.trackTouchDown(position.dx, position.dy, isValid: isValid);
  }

  /// Records a valid task-related action.
  ///
  /// Call when the child performs an action that progresses toward the goal.
  /// This differs from [analyticsRecordTouch] which records all screen touches.
  void analyticsRecordValidAction() {
    _resetIdleTimer();

    final now = DateTime.now();

    // Track first valid action of session
    if (_firstValidActionTime == null) {
      _firstValidActionTime = now;
    }

    // Track valid response time from stimulus
    if (_stimulusTime != null && _firstValidActionTime == now) {
      final responseTime = now.difference(_stimulusTime!).inMilliseconds / 1000.0;
      _validResponseTimes.add(responseTime);
    }

    _sessionMetrics?.recordValidAction();
    _currentRound?.recordValidAction();
    _eventTracker.trackValidAction();
  }

  // ── Performance Recording ──────────────────────────────────────────────────────

  /// Records a correct response/action.
  void analyticsRecordCorrect({Map<String, dynamic>? extraData}) {
    _resetIdleTimer();
    _sessionMetrics?.recordCorrect();
    _currentRound?.recordCorrect();
    _eventTracker.trackCorrect(extra: extraData);

    // Also count as valid action
    analyticsRecordValidAction();
  }

  /// Records an incorrect response/action.
  void analyticsRecordWrong({Map<String, dynamic>? extraData}) {
    _resetIdleTimer();
    _sessionMetrics?.recordWrong();
    _currentRound?.recordWrong();
    _eventTracker.trackIncorrect(extra: extraData);
  }

  /// Records a retry/reset action.
  void analyticsRecordRetry() {
    _sessionMetrics?.recordRetry();
    _currentRound?.recordRetry();
    _eventTracker.trackRetry();
  }

  /// Records when a hint is provided.
  void analyticsRecordHint({String? hintType}) {
    _sessionMetrics?.recordHint();
    _currentRound?.recordHint();
    _eventTracker.trackHint(hintType: hintType);
  }

  /// Records when a prompt is given.
  void analyticsRecordPrompt({String? promptType}) {
    _sessionMetrics?.recordPrompt();
    _currentRound?.recordPrompt();
    _eventTracker.trackPrompt(promptType: promptType);
  }

  /// Records accumulated idle time.
  void analyticsRecordIdleTime(int seconds) {
    _sessionMetrics?.recordIdleTime(seconds);
    _currentRound?.recordIdleTime(seconds);
    _eventTracker.trackIdlePeriod(seconds);
  }

  /// Records an off-task action.
  void analyticsRecordOffTaskAction({String? actionType}) {
    _sessionMetrics?.recordOffTaskAction();
    _currentRound?.recordOffTaskAction();
    _eventTracker.trackOffTaskBehavior(behavior: actionType);
  }

  // ── Game-Specific Metrics ──────────────────────────────────────────────────────

  /// Adds a game-specific metric to the session.
  ///
  /// Use for game-type unique indicators that don't fit standard metrics.
  /// Example for CopyMe: analyticsAddGameSpecificMetric('imitation_success', 0.8)
  void analyticsAddGameSpecificMetric(String key, dynamic value) {
    _sessionMetrics?.gameSpecificMetrics[key] = value;
  }

  /// Adds game-specific data to the current round.
  void analyticsAddRoundData(String key, dynamic value) {
    _currentRound?.gameSpecificData[key] = value;
  }

  // ── Flame Input Integration ────────────────────────────────────────────────────

  /// Call from [onTapDown] to automatically track touches.
  ///
  /// Games using TapCallbacks should call this from their onTapDown:
  /// ```dart
  /// @override
  /// void onTapDown(TapDownEvent event) {
  ///   analyticsHandleTapDown(event);  // Track the touch
  ///   // ... your hit testing logic ...
  /// }
  /// ```
  void analyticsHandleTapDown(TapDownEvent event) {
    analyticsRecordTouch(
      Offset(event.localPosition.x, event.localPosition.y),
      isValid: false,
    );
  }

  /// Call from [onDragUpdate] to track drag events.
  ///
  /// Games using DragCallbacks should call this from their onDragUpdate.
  void analyticsHandleDragUpdate(DragUpdateEvent event) {
    _eventTracker.trackDragUpdate(
      event.localEndPosition.x,
      event.localEndPosition.y,
    );
  }

  // ── Serialization ──────────────────────────────────────────────────────────────

  /// Converts session metrics to a Firestore-compatible map.
  Map<String, dynamic> analyticsToFirestoreMap() {
    if (_sessionMetrics == null) return {};
    return _sessionMetrics!.toFirestoreMap();
  }

  /// Converts session metrics to an XGBoost-ready flat map.
  Map<String, dynamic> analyticsToXgboostMap() {
    if (_sessionMetrics == null) return {};
    return _sessionMetrics!.toXgboostMap();
  }

  /// Returns the complete event log.
  List<Map<String, dynamic>> analyticsExportEvents() {
    return _eventTracker.exportEvents();
  }

  // ── Reset ──────────────────────────────────────────────────────────────────────

  /// Resets all analytics state.
  ///
  /// Useful for "Play Again" functionality.
  void analyticsReset() {
    _stopIdleDetection();
    _sessionMetrics = null;
    _currentRound = null;
    _stimulusTime = null;
    _firstTouchTime = null;
    _firstValidActionTime = null;
    _lastInteractionTime = null;
    _responseTimes.clear();
    _validResponseTimes.clear();
    _totalTouches = 0;
    _validTouches = 0;
    _touchPositions.clear();
    _eventTracker.clear();
  }

  // ── Private Methods ───────────────────────────────────────────────────────────

  void _startIdleDetection() {
    _lastInteractionTime = DateTime.now();
    _idleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkIdleTime();
    });
  }

  void _stopIdleDetection() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _resetIdleTimer() {
    _lastInteractionTime = DateTime.now();
  }

  void _checkIdleTime() {
    if (_lastInteractionTime == null || _sessionMetrics == null) return;

    final idleDuration = DateTime.now().difference(_lastInteractionTime!);
    if (idleDuration.inSeconds >= 5) {
      _sessionMetrics!.idleTimeSeconds++;
      _currentRound?.idleTimeSeconds++;
    }
  }

  @override
  void onRemove() {
    _stopIdleDetection();
    if (_sessionMetrics != null && _sessionMetrics!.endTime == null) {
      analyticsRecordExit();
    }
    super.onRemove();
  }
}
