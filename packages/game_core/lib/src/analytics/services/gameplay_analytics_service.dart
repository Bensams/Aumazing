import 'dart:async';
import 'dart:math';
import 'dart:ui';

import '../models/models.dart';

/// Event types for detailed gameplay logging.
///
/// Used to create a chronological event stream for replay and analysis.
enum GameplayEventType {
  sessionStart,
  sessionEnd,
  roundStart,
  roundEnd,
  stimulusShown,
  touchRecorded,
  validAction,
  correctAction,
  wrongAction,
  hintShown,
  promptGiven,
  retryTriggered,
  idleTimeRecorded,
  offTaskAction,
  earlyExit,
}

/// A single gameplay event record.
///
/// Part of the detailed event log for session reconstruction and analysis.
class GameplayEvent {
  final String id;
  final GameplayEventType type;
  final DateTime timestamp;
  final int? roundNumber;
  final Map<String, dynamic> data;

  GameplayEvent({
    required this.type,
    required this.timestamp,
    this.roundNumber,
    this.data = const {},
  }) : id = _generateEventId();

  static String _generateEventId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'round_number': roundNumber,
      'data': data,
    };
  }
}

/// Service for centralized gameplay analytics tracking.
///
/// Provides a single point of control for all game analytics, supporting:
/// - Session and round lifecycle management
/// - Event logging with timestamps
/// - Real-time metric calculation
/// - Firestore integration hooks
/// - XGBoost-ready data export
///
/// ## Usage:
/// ```dart
/// class MyGame extends FlameGame {
///   late final GameplayAnalyticsService _analytics;
///
///   @override
///   Future<void> onLoad() async {
///     _analytics = GameplayAnalyticsService(
///       gameId: 'match_it',
///       childId: 'child_123',
///       totalRounds: 5,
///     );
///     _analytics.startSession();
///   }
///
///   void onCorrectAnswer() {
///     _analytics.recordCorrect();
///     _analytics.recordValidAction();
///   }
///
///   void onGameComplete() {
///     _analytics.endSession();
///     final data = _analytics.getSessionMetrics().toFirestoreMap();
///     // Send to Firestore
///   }
/// }
/// ```
class GameplayAnalyticsService {
  // ── Configuration ─────────────────────────────────────────────────────────

  final String gameId;
  final String childId;
  final int totalRounds;
  final String? gameVersion;
  final String? deviceInfo;

  // ── Session State ───────────────────────────────────────────────────────────

  late final GameSessionMetrics _session;
  GameRoundMetrics? _currentRound;
  bool _isSessionActive = false;
  bool _isRoundActive = false;

  // ── Event Logging ───────────────────────────────────────────────────────────

  final List<GameplayEvent> _events = [];
  final StreamController<GameplayEvent> _eventController = StreamController<GameplayEvent>.broadcast();

  /// Stream of gameplay events for real-time monitoring.
  Stream<GameplayEvent> get eventStream => _eventController.stream;

  // ── Idle Detection ───────────────────────────────────────────────────────────

  Timer? _idleTimer;
  DateTime? _lastInteractionTime;
  static const int _idleThresholdSeconds = 5;
  int _accumulatedIdleSeconds = 0;

  // ── Touch Tracking ───────────────────────────────────────────────────────────

  final List<TouchRecord> _touchHistory = [];
  DateTime? _sessionFirstTouchTime;
  DateTime? _sessionFirstValidActionTime;

  // ── Constructor ─────────────────────────────────────────────────────────────

  GameplayAnalyticsService({
    required this.gameId,
    required this.childId,
    required this.totalRounds,
    this.gameVersion,
    this.deviceInfo,
  }) {
    _session = GameSessionMetrics(
      gameId: gameId,
      sessionId: _generateSessionId(),
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion,
      deviceInfo: deviceInfo,
    );
  }

  String _generateSessionId() {
    return '${gameId}_${childId}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  // ── Session Lifecycle ────────────────────────────────────────────────────────

  /// Starts a new analytics session.
  ///
  /// Call when the game begins. Initializes timing and starts idle detection.
  void startSession() {
    if (_isSessionActive) return;

    _isSessionActive = true;
    _session.startSession();
    _startIdleDetection();

    _logEvent(GameplayEventType.sessionStart);
  }

  /// Ends the current analytics session.
  ///
  /// Call when the game completes normally. Calculates all derived metrics.
  void endSession() {
    if (!_isSessionActive) return;

    _stopIdleDetection();
    _session.endSession();
    _isSessionActive = false;

    _logEvent(GameplayEventType.sessionEnd, data: {
      'duration_seconds': _session.durationSeconds,
      'completed_rounds': _session.completedRounds,
    });

    _eventController.close();
  }

  /// Records an early exit.
  ///
  /// Call when the child exits before completing all rounds.
  void recordEarlyExit() {
    if (!_isSessionActive) return;

    _session.markEarlyExit();
    _logEvent(GameplayEventType.earlyExit);
    endSession();
  }

  // ── Round Lifecycle ──────────────────────────────────────────────────────────

  /// Starts a new round.
  ///
  /// Returns the round metrics object for reference.
  GameRoundMetrics startRound({int? roundNumber, String? roundId}) {
    if (_isRoundActive && _currentRound != null) {
      // Auto-complete previous round as abandoned
      completeRound(successful: false);
    }

    _currentRound = _session.startRound(roundNumber: roundNumber);
    if (roundId != null) {
      _currentRound!.roundId = roundId;
    }
    _isRoundActive = true;

    _logEvent(GameplayEventType.roundStart, roundNumber: _currentRound!.roundNumber);

    return _currentRound!;
  }

  /// Completes the current round.
  ///
  /// [successful] indicates whether the round was completed correctly.
  void completeRound({required bool successful}) {
    if (!_isRoundActive || _currentRound == null) return;

    _session.completeRound(successful: successful);
    _isRoundActive = false;

    _logEvent(GameplayEventType.roundEnd, roundNumber: _currentRound!.roundNumber, data: {
      'successful': successful,
      'accuracy': _currentRound!.accuracy,
    });

    _currentRound = null;
  }

  /// Marks the entire session as completed.
  ///
  /// Call when all rounds are successfully finished.
  void markSessionCompleted() {
    _session.markCompleted();
  }

  // ── Stimulus & Response Tracking ───────────────────────────────────────────────

  /// Records when a stimulus is presented.
  ///
  /// Call when showing instructions, prompts, or new tasks.
  void recordStimulusShown() {
    _session.recordStimulus();
    if (_currentRound != null) {
      _currentRound!.recordStimulus();
    }

    _logEvent(GameplayEventType.stimulusShown, roundNumber: _currentRound?.roundNumber);
  }

  /// Records any screen touch (valid or invalid).
  ///
  /// [position] - Screen coordinates of the touch
  /// [isValid] - Whether this touch contributes to task completion
  void recordTouch({required Offset position, required bool isValid}) {
    _resetIdleTimer();

    final now = DateTime.now();
    _touchHistory.add(TouchRecord(
      timestamp: now,
      x: position.dx,
      y: position.dy,
      isValid: isValid,
    ));

    // Track session-level first touch
    if (_sessionFirstTouchTime == null) {
      _sessionFirstTouchTime = now;
    }

    _session.recordTouch(x: position.dx, y: position.dy, isValid: isValid);
    if (_currentRound != null) {
      _currentRound!.recordTouch(isValid: isValid);
    }

    _logEvent(GameplayEventType.touchRecorded, roundNumber: _currentRound?.roundNumber, data: {
      'x': position.dx,
      'y': position.dy,
      'is_valid': isValid,
    });

    // Track first valid action at session level
    if (isValid && _sessionFirstValidActionTime == null) {
      _sessionFirstValidActionTime = now;
    }
  }

  /// Records a valid task-related action.
  ///
  /// Call when the child performs an action that progresses toward the goal.
  void recordValidAction() {
    _resetIdleTimer();

    _session.recordValidAction();
    if (_currentRound != null) {
      _currentRound!.recordValidAction();
    }

    _logEvent(GameplayEventType.validAction, roundNumber: _currentRound?.roundNumber);
  }

  // ── Performance Tracking ───────────────────────────────────────────────────────

  /// Records a correct action.
  ///
  /// Also records as a valid action automatically.
  void recordCorrect({Map<String, dynamic>? extraData}) {
    _resetIdleTimer();

    _session.recordCorrect();
    if (_currentRound != null) {
      _currentRound!.recordCorrect();
    }

    _logEvent(GameplayEventType.correctAction, roundNumber: _currentRound?.roundNumber, data: extraData);
    recordValidAction();
  }

  /// Records an incorrect/wrong action.
  void recordWrong({Map<String, dynamic>? extraData}) {
    _resetIdleTimer();

    _session.recordWrong();
    if (_currentRound != null) {
      _currentRound!.recordWrong();
    }

    _logEvent(GameplayEventType.wrongAction, roundNumber: _currentRound?.roundNumber, data: extraData);
  }

  /// Records a retry action.
  void recordRetry() {
    _session.recordRetry();
    if (_currentRound != null) {
      _currentRound!.recordRetry();
    }

    _logEvent(GameplayEventType.retryTriggered, roundNumber: _currentRound?.roundNumber);
  }

  // ── Assistance Tracking ────────────────────────────────────────────────────────

  /// Records when a hint is provided to the child.
  void recordHint({String? hintType}) {
    _session.recordHint();
    if (_currentRound != null) {
      _currentRound!.recordHint();
    }

    _logEvent(GameplayEventType.hintShown, roundNumber: _currentRound?.roundNumber, data: {
      'hint_type': hintType,
    });
  }

  /// Records when a prompt is given to the child.
  void recordPrompt({String? promptType}) {
    _session.recordPrompt();
    if (_currentRound != null) {
      _currentRound!.recordPrompt();
    }

    _logEvent(GameplayEventType.promptGiven, roundNumber: _currentRound?.roundNumber, data: {
      'prompt_type': promptType,
    });
  }

  // ── Engagement Tracking ────────────────────────────────────────────────────────

  /// Records an off-task action.
  void recordOffTaskAction({String? actionType}) {
    _session.recordOffTaskAction();
    if (_currentRound != null) {
      _currentRound!.recordOffTaskAction();
    }

    _logEvent(GameplayEventType.offTaskAction, roundNumber: _currentRound?.roundNumber, data: {
      'action_type': actionType,
    });
  }

  // ── Game-Specific Metrics ──────────────────────────────────────────────────────

  /// Adds a game-specific metric to the current session.
  ///
  /// Use this for game-type unique indicators.
  /// Example for CopyMe: addGameSpecificMetric('imitation_success', 0.8)
  void addGameSpecificMetric(String key, dynamic value) {
    _session.gameSpecificMetrics[key] = value;
  }

  /// Adds game-specific data to the current round.
  void addRoundSpecificData(String key, dynamic value) {
    if (_currentRound != null) {
      _currentRound!.gameSpecificData[key] = value;
    }
  }

  // ── Data Access ────────────────────────────────────────────────────────────────

  /// Returns the complete session metrics.
  GameSessionMetrics getSessionMetrics() => _session;

  /// Returns the current round metrics (null if no active round).
  GameRoundMetrics? getCurrentRoundMetrics() => _currentRound;

  /// Returns all recorded events.
  List<GameplayEvent> getEventLog() => List.unmodifiable(_events);

  /// Returns the touch history.
  List<TouchRecord> getTouchHistory() => List.unmodifiable(_touchHistory);

  /// Returns true if a session is currently active.
  bool get isSessionActive => _isSessionActive;

  /// Returns true if a round is currently active.
  bool get isRoundActive => _isRoundActive;

  // ── Firestore Integration ──────────────────────────────────────────────────────

  /// Returns the session metrics as a Firestore-ready map.
  Map<String, dynamic> toFirestoreMap() => _session.toFirestoreMap();

  /// Returns the session metrics as an XGBoost-ready map.
  Map<String, dynamic> toXgboostMap() => _session.toXgboostMap();

  // ── Private Methods ──────────────────────────────────────────────────────────

  void _logEvent(GameplayEventType type, {int? roundNumber, Map<String, dynamic>? data}) {
    final event = GameplayEvent(
      type: type,
      timestamp: DateTime.now(),
      roundNumber: roundNumber,
      data: data ?? {},
    );
    _events.add(event);
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  // ── Idle Detection ─────────────────────────────────────────────────────────────

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
    if (_lastInteractionTime == null) return;

    final idleDuration = DateTime.now().difference(_lastInteractionTime!);
    if (idleDuration.inSeconds >= _idleThresholdSeconds) {
      _accumulatedIdleSeconds++;
      _session.recordIdleTime(1);
      if (_currentRound != null) {
        _currentRound!.recordIdleTime(1);
      }

      _logEvent(GameplayEventType.idleTimeRecorded, roundNumber: _currentRound?.roundNumber, data: {
        'accumulated_idle_seconds': _accumulatedIdleSeconds,
      });
    }
  }
}

/// Record of a single touch event.
class TouchRecord {
  final DateTime timestamp;
  final double x;
  final double y;
  final bool isValid;

  TouchRecord({
    required this.timestamp,
    required this.x,
    required this.y,
    required this.isValid,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'x': x,
      'y': y,
      'is_valid': isValid,
    };
  }
}
