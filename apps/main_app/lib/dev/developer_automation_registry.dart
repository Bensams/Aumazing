import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';

import 'developer_tools_config.dart';

/// A game screen that is on-screen right now and can be driven by automation.
///
/// Held by the screen that created it and handed back to
/// [DeveloperAutomationRegistry.unregister] on dispose, so the registry never
/// points at a game whose route has gone.
class DeveloperGameSession {
  DeveloperGameSession._({
    required this.gameId,
    required this.assessmentContext,
    required bool Function() awaitingInput,
    required void Function() performAction,
  })  : _awaitingInput = awaitingInput,
        _performAction = performAction;

  /// Wraps a real game's automation hooks.
  factory DeveloperGameSession._forGame({
    required String gameId,
    required String assessmentContext,
    required DeveloperAutomationHooks game,
  }) =>
      DeveloperGameSession._(
        gameId: gameId,
        assessmentContext: assessmentContext,
        awaitingInput: () => game.debugIsAwaitingInput,
        performAction: game.debugPerformCorrectAction,
      );

  /// Test seam: a session backed by plain callbacks instead of a live Flame
  /// game, so the controller's loop can be driven without mounting one.
  @visibleForTesting
  factory DeveloperGameSession.forTest({
    required String gameId,
    required String assessmentContext,
    required bool Function() awaitingInput,
    required void Function() performAction,
  }) =>
      DeveloperGameSession._(
        gameId: gameId,
        assessmentContext: assessmentContext,
        awaitingInput: awaitingInput,
        performAction: performAction,
      );

  final String gameId;

  /// 'pre_assessment', 'post_assessment' or 'practice' — the context the
  /// screen will record its session under.
  final String assessmentContext;

  final bool Function() _awaitingInput;
  final void Function() _performAction;

  bool _complete = false;

  /// Set by the registry when this session becomes the active one, so a
  /// completion is *pushed* the moment the screen reports it.
  ///
  /// Polling for it was racy: a flow can register the next game within a few
  /// milliseconds of the previous one finishing, and a completion that lands
  /// between two polls would simply never be seen.
  void Function(DeveloperGameSession session)? _onComplete;

  /// True once the screen's completion callback has fired, so automation
  /// stops driving a game that has already finished.
  bool get isComplete => _complete;

  /// Whether the game will accept a valid action right now.
  bool get isAwaitingInput => !_complete && _awaitingInput();

  /// Advances the real game by one correct action.
  void performCorrectAction() {
    if (_complete) return;
    _performAction();
  }

  /// Called by the screen from its own game-complete handler.
  void markComplete() {
    if (_complete) return;
    _complete = true;
    _onComplete?.call(this);
  }
}

/// A flow screen sitting between games (the pre/post-assessment transition
/// with its countdown and Play button) that automation can move along.
class DeveloperFlowSession {
  DeveloperFlowSession._({
    required this.flowLabel,
    required this.gameIndex,
    required this.gameCount,
    required void Function() launchNow,
  }) : _launchNow = launchNow;

  /// 'Pre-Assessment' / 'Post-Assessment' — shown in the status indicator.
  final String flowLabel;

  /// Zero-based index of the game this transition screen is about to start.
  final int gameIndex;
  final int gameCount;

  final void Function() _launchNow;

  bool _launched = false;

  /// Starts the pending game immediately instead of waiting out the
  /// countdown. Safe to call more than once — the screen guards duplicate
  /// launches, and so does this.
  void launchNow() {
    if (_launched) return;
    _launched = true;
    _launchNow();
  }
}

/// Where the automation controller finds whatever is currently on screen.
///
/// Screens register themselves; the controller only ever reacts to what is
/// registered. That is what makes automation safe across unexpected route
/// changes: when a screen goes away it unregisters, and the controller simply
/// has nothing to drive.
///
/// Registration is a no-op — and returns null — unless developer tools are
/// available, so a normal build carries no automation state at all.
class DeveloperAutomationRegistry extends ChangeNotifier {
  DeveloperAutomationRegistry._();

  static final DeveloperAutomationRegistry instance =
      DeveloperAutomationRegistry._();

  /// Games whose Flame class implements [DeveloperAutomationHooks] and whose
  /// screen registers itself, so automation can actually play them.
  ///
  /// The other registered games have no hook yet: their screens never call
  /// [registerGame], so automation would sit waiting for input that never
  /// becomes available. Callers check this first and say so plainly instead
  /// of starting a run that can only time out.
  static const automatableGameIds = <String>{
    'copy_me',
    'do_what_i_say',
    'my_turn_your_turn',
    'match_it',
  };

  /// Whether [gameId] can be driven by auto-play today.
  static bool canAutomate(String gameId) =>
      automatableGameIds.contains(gameId);

  DeveloperGameSession? _activeGame;
  DeveloperFlowSession? _activeFlow;

  String? _flowLabel;
  int? _flowGameIndex;
  int? _flowGameCount;

  /// The game currently on screen, or null.
  DeveloperGameSession? get activeGame => _activeGame;

  /// The transition screen currently on screen, or null.
  DeveloperFlowSession? get activeFlow => _activeFlow;

  /// The multi-game flow the app is in the middle of ('Pre-Assessment' /
  /// 'Post-Assessment'), or null during free practice.
  ///
  /// Held across the hop from a transition screen into the game it launched:
  /// the game screen itself has no idea which step of an assessment it is, and
  /// both the status line and "skip remaining" need to know.
  String? get flowLabel => _flowLabel;

  /// Zero-based position of the current game within [flowLabel]'s sequence.
  int? get flowGameIndex => _flowGameIndex;

  /// How many games [flowLabel] runs in total.
  int? get flowGameCount => _flowGameCount;

  /// Games left to play in the current flow, including the current one.
  /// Null when there is no multi-game flow to count.
  int? get flowGamesRemaining {
    final index = _flowGameIndex;
    final count = _flowGameCount;
    if (index == null || count == null) return null;
    return (count - index).clamp(0, count);
  }

  /// Registers the game [game] belonging to the screen showing [gameId].
  DeveloperGameSession? registerGame({
    required String gameId,
    required String assessmentContext,
    required DeveloperAutomationHooks game,
  }) {
    if (!DeveloperToolsConfig.isAvailable) return null;
    return adoptGame(DeveloperGameSession._forGame(
      gameId: gameId,
      assessmentContext: assessmentContext,
      game: game,
    ));
  }

  /// Makes [session] the active game. Split out so a test can register a
  /// callback-backed session through exactly the same path.
  @visibleForTesting
  DeveloperGameSession? adoptGame(DeveloperGameSession session) {
    if (!DeveloperToolsConfig.isAvailable) return null;
    session._onComplete = _handleSessionComplete;
    _activeGame = session;
    // A game screen replaces whatever transition screen led to it.
    _activeFlow = null;
    // Practice is not part of a counted sequence — leaving a stale
    // assessment position here would misreport "Game 3 of 4" in the lobby.
    if (session.assessmentContext == 'practice') _clearFlowPosition();
    notifyListeners();
    // A session can arrive already finished (a game whose completion fired
    // before it was adopted). Report it now, or a run waiting on it would
    // simply hang until the stall timeout.
    if (session.isComplete) _handleSessionComplete(session);
    return session;
  }

  /// Registers a between-games transition screen.
  DeveloperFlowSession? registerFlow({
    required String flowLabel,
    required int gameIndex,
    required int gameCount,
    required void Function() launchNow,
  }) {
    if (!DeveloperToolsConfig.isAvailable) return null;
    final session = DeveloperFlowSession._(
      flowLabel: flowLabel,
      gameIndex: gameIndex,
      gameCount: gameCount,
      launchNow: launchNow,
    );
    _activeFlow = session;
    _flowLabel = flowLabel;
    _flowGameIndex = gameIndex;
    _flowGameCount = gameCount;
    notifyListeners();
    return session;
  }

  /// Notified the instant a registered game reports completion.
  ///
  /// The auto-play controller subscribes while a run is in flight; nothing
  /// else listens, and it is cleared when the run ends.
  void Function(DeveloperGameSession session)? onSessionComplete;

  void _handleSessionComplete(DeveloperGameSession session) {
    onSessionComplete?.call(session);
    notifyListeners();
  }

  void _clearFlowPosition() {
    _flowLabel = null;
    _flowGameIndex = null;
    _flowGameCount = null;
  }

  /// Clears [session] if it is still the active one.
  ///
  /// Identity-checked so a screen disposing *after* its replacement has
  /// registered cannot wipe the newer registration.
  void unregister(Object? session) {
    if (session == null) return;
    var changed = false;
    if (identical(_activeGame, session)) {
      _activeGame = null;
      changed = true;
    }
    if (identical(_activeFlow, session)) {
      _activeFlow = null;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Test seam: drops everything.
  @visibleForTesting
  void reset() {
    _activeGame = null;
    _activeFlow = null;
    onSessionComplete = null;
    _clearFlowPosition();
    notifyListeners();
  }
}
