import 'dart:async';

import 'models/models.dart';
import 'game_event_tracker.dart';

/// Controller for managing game analytics in non-Flame games or Flutter UI.
///
/// This controller provides the same analytics capabilities as
/// [EnhancedGameplayAnalyticsMixin] but for games that don't use Flame,
/// or for managing analytics from Flutter UI code.
///
/// ## Usage:
/// ```dart
/// class MyGameController extends ChangeNotifier {
///   final GameMetricsController _analytics = GameMetricsController();
///
///   void startGame() {
///     _analytics.initialize(
///       gameId: 'memory_game',
///       childId: 'child_123',
///       totalRounds: 10,
///     );
///     _analytics.startSession();
///   }
///
///   void onCorrectAnswer() {
///     _analytics.recordCorrect();
///   }
///
///   void endGame() {
///     _analytics.completeSession();
///     final data = _analytics.toFirestoreMap();
///     // Save to Firestore...
///   }
/// }
/// ```
class GameMetricsController {
  // ── Core Models ───────────────────────────────────────────────────────────

  GameSessionMetrics? _sessionMetrics;
  GameRoundMetrics? _currentRound;
  final GameEventTracker _eventTracker = GameEventTracker();

  // ── State ───────────────────────────────────────────────────────────────────

  DateTime? _stimulusTime;
  DateTime? _firstTouchTime;
  DateTime? _firstValidActionTime;
  DateTime? _lastInteractionTime;
  Timer? _idleTimer;

  final List<double> _responseTimes = [];
  final List<double> _validResponseTimes = [];

  // ── Public Getters ───────────────────────────────────────────────────────────

  /// The session metrics model (null if not initialized).
  GameSessionMetrics? get sessionMetrics => _sessionMetrics;

  /// The current round metrics (null if no active round).
  GameRoundMetrics? get currentRound => _currentRound;

  /// The event tracker for detailed logging.
  GameEventTracker get eventTracker => _eventTracker;

  /// Whether a session is currently active.
  bool get isSessionActive => _sessionMetrics != null && _sessionMetrics!.startTime != null;

  /// Whether a round is currently active.
  bool get isRoundActive => _currentRound != null && _currentRound!.startTime != null;

  /// Current session ID (null if no session).
  String? get sessionId => _sessionMetrics?.sessionId;

  // ── Initialization ───────────────────────────────────────────────────────────

  /// Initializes the analytics controller.
  ///
  /// [gameId] - Unique game type identifier (e.g., 'do_what_i_say', 'my_turn_your_turn')
  /// [childId] - Unique child identifier
  /// [totalRounds] - Expected number of rounds in this session
  /// [gameVersion] - Optional game version string
  void initialize({
    required String gameId,
    required String childId,
    required int totalRounds,
    String? gameVersion,
    String? deviceInfo,
  }) {
    final sessionId = '${gameId}_${childId}_${DateTime.now().millisecondsSinceEpoch}';

    _sessionMetrics = GameSessionMetrics(
      gameId: gameId,
      sessionId: sessionId,
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

  // ── Session Lifecycle ───────────────────────────────────────────────────────────

  /// Starts the analytics session.
  ///
  /// Call when the game begins.
  void startSession() {
    if (_sessionMetrics == null) {
      throw StateError('initialize() must be called before startSession()');
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
  void completeSession() {
    if (_sessionMetrics == null) return;

    _stopIdleDetection();

    // Finalize current round if active
    if (_currentRound != null && _currentRound!.endTime == null) {
      completeRound(successful: false);
    }

    // Update session with calculated metrics
    _sessionMetrics!.avgResponseTime = _calculateAvgResponseTime();
    _sessionMetrics!.avgValidResponseTime = _calculateAvgValidResponseTime();
    _sessionMetrics!.timeToFirstTouch = _calculateTimeToFirstTouch();
    _sessionMetrics!.timeToFirstValidAction = _calculateTimeToFirstValidAction();

    _sessionMetrics!.endSession();
    _eventTracker.endSession();
  }

  /// Records an early exit.
  void recordEarlyExit() {
    if (_sessionMetrics == null) return;
    _sessionMetrics!.markEarlyExit();
    _eventTracker.trackEarlyExit();
    completeSession();
  }

  // ── Round Lifecycle ───────────────────────────────────────────────────────────────

  /// Starts a new round.
  ///
  /// [roundNumber] - Optional round number (auto-increments if not provided)
  /// [roundId] - Optional round identifier
  GameRoundMetrics startRound({int? roundNumber, String? roundId}) {
    if (_sessionMetrics == null) {
      throw StateError('initialize() must be called before startRound()');
    }

    // Complete previous round if exists
    if (_currentRound != null && _currentRound!.endTime == null) {
      completeRound(successful: false);
    }

    _currentRound = _sessionMetrics!.startRound(roundNumber: roundNumber);
    if (roundId != null) {
      _currentRound!.roundId = roundId;
    }

    _stimulusTime = null;
    _eventTracker.startRound(_currentRound!.roundNumber);

    return _currentRound!;
  }

  /// Completes the current round.
  ///
  /// [successful] - Whether the round was completed successfully
  void completeRound({required bool successful}) {
    if (_sessionMetrics == null || _currentRound == null) return;

    _sessionMetrics!.completeRound(successful: successful);

    if (successful) {
      _eventTracker.completeRound();
    } else {
      _eventTracker.abandonRound();
    }

    _currentRound = null;
  }

  /// Marks the session as completed.
  void markCompleted() {
    _sessionMetrics?.markCompleted();
  }

  // ── Stimulus & Response ───────────────────────────────────────────────────────────

  /// Records when a stimulus is presented.
  void showStimulus() {
    _stimulusTime = DateTime.now();
    _sessionMetrics?.recordStimulus();
    _currentRound?.recordStimulus();
    _eventTracker.trackStimulus();
  }

  /// Records any screen touch.
  ///
  /// [x], [y] - Screen coordinates
  /// [isValid] - Whether this is a task-related touch
  void recordTouch(double x, double y, {bool isValid = false}) {
    _resetIdleTimer();

    final now = DateTime.now();

    if (_firstTouchTime == null) {
      _firstTouchTime = now;
    }

    if (_stimulusTime != null) {
      final responseTime = now.difference(_stimulusTime!).inMilliseconds / 1000.0;
      _responseTimes.add(responseTime);
    }

    // Track in session metrics and round metrics
    _sessionMetrics?.recordTouch(x: x, y: y, isValid: isValid);
    _currentRound?.recordTouch(isValid: isValid);

    _eventTracker.trackTouchDown(x, y, isValid: isValid);
  }

  /// Records a valid task-related action.
  void recordValidAction() {
    _resetIdleTimer();

    final now = DateTime.now();

    if (_firstValidActionTime == null) {
      _firstValidActionTime = now;
    }

    if (_stimulusTime != null && _firstValidActionTime == now) {
      final responseTime = now.difference(_stimulusTime!).inMilliseconds / 1000.0;
      _validResponseTimes.add(responseTime);
    }

    _sessionMetrics?.recordValidAction();
    _currentRound?.recordValidAction();
    _eventTracker.trackValidAction();
  }

  // ── Performance Recording ─────────────────────────────────────────────────────────

  /// Records a correct response.
  void recordCorrect({Map<String, dynamic>? extraData}) {
    _resetIdleTimer();
    _sessionMetrics?.recordCorrect();
    _currentRound?.recordCorrect();
    _eventTracker.trackCorrect(extra: extraData);
    recordValidAction();
  }

  /// Records an incorrect response.
  void recordWrong({Map<String, dynamic>? extraData}) {
    _resetIdleTimer();
    _sessionMetrics?.recordWrong();
    _currentRound?.recordWrong();
    _eventTracker.trackIncorrect(extra: extraData);
  }

  /// Records a retry.
  void recordRetry() {
    _sessionMetrics?.recordRetry();
    _currentRound?.recordRetry();
    _eventTracker.trackRetry();
  }

  /// Records when a hint is provided.
  void recordHint({String? hintType}) {
    _sessionMetrics?.recordHint();
    _currentRound?.recordHint();
    _eventTracker.trackHint(hintType: hintType);
  }

  /// Records when a prompt is given.
  void recordPrompt({String? promptType}) {
    _sessionMetrics?.recordPrompt();
    _currentRound?.recordPrompt();
    _eventTracker.trackPrompt(promptType: promptType);
  }

  /// Records idle time.
  void recordIdleTime(int seconds) {
    _sessionMetrics?.recordIdleTime(seconds);
    _currentRound?.recordIdleTime(seconds);
    _eventTracker.trackIdlePeriod(seconds);
  }

  /// Records an off-task action.
  void recordOffTaskAction({String? actionType}) {
    _sessionMetrics?.recordOffTaskAction();
    _currentRound?.recordOffTaskAction();
    _eventTracker.trackOffTaskBehavior(behavior: actionType);
  }

  // ── Game-Specific Metrics ─────────────────────────────────────────────────────────

  /// Adds a game-specific metric.
  void addGameSpecificMetric(String key, dynamic value) {
    _sessionMetrics?.gameSpecificMetrics[key] = value;
  }

  /// Adds round-specific data.
  void addRoundData(String key, dynamic value) {
    _currentRound?.gameSpecificData[key] = value;
  }

  // ── Serialization ───────────────────────────────────────────────────────────────

  /// Returns the session metrics as a Firestore-compatible map.
  Map<String, dynamic> toFirestoreMap() {
    if (_sessionMetrics == null) return {};
    return _sessionMetrics!.toFirestoreMap();
  }

  /// Returns the session metrics as an XGBoost-ready map.
  Map<String, dynamic> toXgboostMap() {
    if (_sessionMetrics == null) return {};
    return _sessionMetrics!.toXgboostMap();
  }

  /// Returns all tracked events.
  List<Map<String, dynamic>> exportEvents() {
    return _eventTracker.exportEvents();
  }

  // ── Private Helpers ───────────────────────────────────────────────────────────────

  double _calculateAvgResponseTime() {
    if (_responseTimes.isEmpty) return 0.0;
    return _responseTimes.reduce((a, b) => a + b) / _responseTimes.length;
  }

  double _calculateAvgValidResponseTime() {
    if (_validResponseTimes.isEmpty) return 0.0;
    return _validResponseTimes.reduce((a, b) => a + b) / _validResponseTimes.length;
  }

  double _calculateTimeToFirstTouch() {
    if (_sessionMetrics?.startTime == null || _firstTouchTime == null) return 0.0;
    return _firstTouchTime!.difference(DateTime.parse(_sessionMetrics!.startTime!)).inMilliseconds / 1000.0;
  }

  double _calculateTimeToFirstValidAction() {
    if (_sessionMetrics?.startTime == null || _firstValidActionTime == null) return 0.0;
    return _firstValidActionTime!.difference(DateTime.parse(_sessionMetrics!.startTime!)).inMilliseconds / 1000.0;
  }

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

  /// Resets all analytics state.
  void reset() {
    _stopIdleDetection();
    _sessionMetrics = null;
    _currentRound = null;
    _stimulusTime = null;
    _firstTouchTime = null;
    _firstValidActionTime = null;
    _lastInteractionTime = null;
    _responseTimes.clear();
    _validResponseTimes.clear();
    _eventTracker.clear();
  }
}
