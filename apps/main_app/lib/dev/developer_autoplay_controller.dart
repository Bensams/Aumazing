import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';

import 'developer_automation_registry.dart';
import 'developer_tools_config.dart';

/// How fast automation acts. Even [veryFast] yields between actions, so the
/// UI still renders each meaningful state rather than jumping to the end.
enum AutoPlaySpeed {
  normal('Normal', Duration(milliseconds: 700)),
  fast('Fast', Duration(milliseconds: 280)),
  veryFast('Very Fast', Duration(milliseconds: 60));

  const AutoPlaySpeed(this.label, this.actionDelay);

  final String label;

  /// Pause between two valid actions.
  final Duration actionDelay;
}

/// What the controller was asked to do.
enum AutoPlayMode {
  preAssessment('Pre-Assessment'),
  postAssessment('Post-Assessment'),
  nextModule('Next Module'),
  currentGame('Current Game'),
  skipRemaining('Skip Remaining');

  const AutoPlayMode(this.label);

  final String label;
}

enum AutoPlayStatus { idle, running, paused, finished, failed }

/// Drives real game screens by performing valid in-game actions.
///
/// Reactive rather than scripted: it drives whatever the
/// [DeveloperAutomationRegistry] currently holds, and does nothing while the
/// registry is empty. That is what makes it safe across rewards, dialogs and
/// unexpected route changes — if the flow leaves, there is simply nothing to
/// act on, and the stall timeout ends the run.
class DeveloperAutoPlayController extends ChangeNotifier {
  DeveloperAutoPlayController._();

  static final DeveloperAutoPlayController instance =
      DeveloperAutoPlayController._();

  /// How long to wait with nothing to drive before giving up. Generous: a
  /// game's demo phase, a reward overlay and a transition can easily add up
  /// to twenty seconds of legitimately idle time.
  static const Duration stallTimeout = Duration(seconds: 45);

  /// Polling interval while waiting for a game to become ready.
  static const Duration _pollInterval = Duration(milliseconds: 50);

  AutoPlayStatus _status = AutoPlayStatus.idle;
  AutoPlaySpeed _speed = AutoPlaySpeed.fast;
  AutoPlayMode? _mode;
  String? _message;
  String? _currentGameId;

  /// Game ids whose sessions this run has already driven to completion.
  final List<String> _completedGameIds = [];

  /// How many games the run expects to play, when it knows (4 for an
  /// assessment); null for open-ended runs.
  int? _expectedGameCount;

  Completer<void>? _resumeSignal;
  bool _stopRequested = false;
  Future<void>? _loop;

  AutoPlayStatus get status => _status;
  AutoPlaySpeed get speed => _speed;
  AutoPlayMode? get mode => _mode;

  /// The last outcome or error, for display.
  String? get message => _message;

  bool get isActive =>
      _status == AutoPlayStatus.running || _status == AutoPlayStatus.paused;

  /// Games finished so far in this run.
  int get completedCount => _completedGameIds.length;

  /// The status line, e.g. `DEV AUTO: Pre-Assessment — Game 2 of 4`.
  ///
  /// Position comes from the flow the app is actually in when there is one,
  /// so the number matches the progress dots the child can see; otherwise it
  /// falls back to counting what this run has finished.
  String? get statusLine {
    final mode = _mode;
    if (mode == null || !isActive) return null;

    final registry = DeveloperAutomationRegistry.instance;
    final flowIndex = registry.flowGameIndex;
    final flowCount = registry.flowGameCount;

    final String progress;
    if (flowIndex != null && flowCount != null) {
      progress = 'Game ${(flowIndex + 1).clamp(1, flowCount)} of $flowCount';
    } else if (_expectedGameCount != null) {
      final position = _completedGameIds.length + 1;
      progress =
          'Game ${position.clamp(1, _expectedGameCount!)} of $_expectedGameCount';
    } else {
      progress = 'Game ${_completedGameIds.length + 1}';
    }

    final label = registry.flowLabel ?? mode.label;
    final paused = _status == AutoPlayStatus.paused ? ' (paused)' : '';
    return 'DEV AUTO: $label — $progress$paused';
  }

  // ── Skip controls ────────────────────────────────────────────────────

  /// Plays the game currently on screen through to its natural completion at
  /// the chosen [speed], then stops.
  ///
  /// This is the one helper behind both "Auto-play Current Game" (at the
  /// developer's speed) and "Skip Current Game" (at [AutoPlaySpeed.veryFast]),
  /// so a skipped game and a played one produce the same session, the same
  /// reward and the same advance.
  Future<void> playCurrentGame({AutoPlaySpeed? speed}) => start(
        mode: AutoPlayMode.currentGame,
        expectedGameCount: 1,
        speed: speed,
      );

  /// Completes the current game and every game left in the active flow.
  ///
  /// The count comes from the flow itself, so it finishes exactly the games
  /// that have not been played and then hands over to the flow's own ending —
  /// the child-to-parent hand-off for an assessment.
  Future<void> skipRemainingGames() => start(
        mode: AutoPlayMode.skipRemaining,
        expectedGameCount: DeveloperAutomationRegistry.instance.flowGamesRemaining,
        speed: AutoPlaySpeed.veryFast,
      );

  void setSpeed(AutoPlaySpeed value) {
    if (_speed == value) return;
    _speed = value;
    notifyListeners();
  }

  /// Starts a run. Returns the future of the run loop, so a test can await it.
  ///
  /// [expectedGameCount] ends the run once that many games have completed;
  /// null runs until stopped or stalled.
  Future<void> start({
    required AutoPlayMode mode,
    int? expectedGameCount,
    AutoPlaySpeed? speed,
  }) {
    if (!DeveloperToolsConfig.isAvailable) return Future.value();
    if (isActive) return _loop ?? Future.value();

    // The game-side hooks stay shut until a run actually needs them.
    DeveloperAutomation.enable();

    _mode = mode;
    _expectedGameCount = expectedGameCount;
    if (speed != null) _speed = speed;
    _completedGameIds.clear();
    _currentGameId = null;
    _message = null;
    _stopRequested = false;
    _resumeSignal = null;
    _status = AutoPlayStatus.running;

    // Completions are pushed, not polled: a flow can register the next game
    // within milliseconds of the last one finishing, and a poll would miss it.
    final registry = DeveloperAutomationRegistry.instance;
    registry.onSessionComplete = (session) => _noteCompleted(session.gameId);

    // A game that finished before the run started is already done; counting
    // it here stops the loop waiting out the stall timeout on a dead screen.
    final active = registry.activeGame;
    if (active != null && active.isComplete) _completedGameIds.add(active.gameId);

    notifyListeners();

    return _loop = _run();
  }

  void pause() {
    if (_status != AutoPlayStatus.running) return;
    _status = AutoPlayStatus.paused;
    _resumeSignal = Completer<void>();
    notifyListeners();
  }

  void resume() {
    if (_status != AutoPlayStatus.paused) return;
    _status = AutoPlayStatus.running;
    _resumeSignal?.complete();
    _resumeSignal = null;
    notifyListeners();
  }

  /// Asks the run to stop. The loop unwinds at its next step, leaving the app
  /// wherever the child's own play would have left it.
  void stop() {
    if (!isActive) return;
    _stopRequested = true;
    // A paused run must wake up to notice it was stopped.
    _resumeSignal?.complete();
    _resumeSignal = null;
    _status = AutoPlayStatus.running;
    notifyListeners();
  }

  Future<void> _run() async {
    final registry = DeveloperAutomationRegistry.instance;
    var idleSince = DateTime.now();

    try {
      while (!_stopRequested) {
        if (_status == AutoPlayStatus.paused) {
          await _resumeSignal?.future;
          continue;
        }

        if (_expectedGameCount != null &&
            _completedGameIds.length >= _expectedGameCount!) {
          _finish('Auto-play finished ${_completedGameIds.length} game(s).');
          return;
        }

        final flow = registry.activeFlow;
        final game = registry.activeGame;

        if (game != null && !game.isComplete) {
          idleSince = DateTime.now();
          if (_currentGameId != game.gameId) {
            _currentGameId = game.gameId;
            notifyListeners();
          }
          if (game.isAwaitingInput) {
            game.performCorrectAction();
            await _delay(_speed.actionDelay);
          } else {
            // Demo phase, animation, buddy's turn — wait it out rather than
            // forcing input the game would score as an error.
            await _delay(_pollInterval);
          }
          continue;
        }

        if (game != null && game.isComplete) {
          // The screen's own reward and transition run from here; the loop
          // waits for the next game to register. The completion itself was
          // already counted by the registry callback.
          idleSince = DateTime.now();
          await _delay(_pollInterval);
          continue;
        }

        if (flow != null) {
          idleSince = DateTime.now();
          flow.launchNow();
          await _delay(_pollInterval);
          continue;
        }

        // Nothing to drive: a reward overlay, a route change, the hand-off.
        if (DateTime.now().difference(idleSince) > stallTimeout) {
          if (_expectedGameCount != null &&
              _completedGameIds.length >= _expectedGameCount!) {
            _finish('Auto-play finished ${_completedGameIds.length} game(s).');
          } else {
            _fail('Auto-play stopped: nothing to drive for '
                '${stallTimeout.inSeconds}s'
                '${_currentGameId == null ? '' : ' (last game: $_currentGameId)'}.');
          }
          return;
        }
        await _delay(_pollInterval);
      }

      _finish('Auto-play stopped after ${_completedGameIds.length} game(s).');
    } catch (e) {
      _fail('Auto-play failed'
          '${_currentGameId == null ? '' : ' during $_currentGameId'}: $e');
    }
  }

  void _noteCompleted(String gameId) {
    _completedGameIds.add(gameId);
    notifyListeners();
  }

  void _finish(String message) {
    _status = AutoPlayStatus.finished;
    _message = message;
    _teardown();
  }

  void _fail(String message) {
    _status = AutoPlayStatus.failed;
    _message = message;
    debugPrint('[DeveloperAutoPlay] $message');
    _teardown();
  }

  /// Leaves no timer, signal, subscription or open hook behind.
  void _teardown() {
    _stopRequested = false;
    _resumeSignal = null;
    _loop = null;
    _currentGameId = null;
    DeveloperAutomationRegistry.instance.onSessionComplete = null;
    DeveloperAutomation.disable();
    notifyListeners();
  }

  Future<void> _delay(Duration duration) => Future<void>.delayed(duration);

  /// Test seam: returns the controller to a clean idle state.
  @visibleForTesting
  void resetForTest() {
    _stopRequested = true;
    _resumeSignal?.complete();
    _resumeSignal = null;
    _status = AutoPlayStatus.idle;
    _mode = null;
    _message = null;
    _currentGameId = null;
    _expectedGameCount = null;
    _completedGameIds.clear();
    _loop = null;
    DeveloperAutomationRegistry.instance.onSessionComplete = null;
    DeveloperAutomation.disable();
  }
}
