/// Hand-off from the end-of-game "Next" choice back to the lobby.
///
/// Tapping "Next" on a learning-path game no longer swaps straight into the
/// next screen: the dialog parks the launch here and pops home to My Path, so
/// the child watches the spaceship fly to the step they just unlocked before
/// the next game opens. The lobby consumes the slot when the game route pops
/// and fires the launch once the ship docks.
///
/// A static slot rather than a provider: the value makes exactly one hop
/// (dialog → lobby), is always consumed on arrival, and must survive the game
/// route being popped — which is precisely when anything scoped to that route
/// would be torn down.
class PendingPathLaunch {
  PendingPathLaunch._();

  static String? _gameId;
  static int? _difficulty;

  /// Parks a launch for the lobby to pick up when the game screen pops.
  static void set(String gameId, int difficulty) {
    _gameId = gameId;
    _difficulty = difficulty;
  }

  /// The parked launch, if any — consuming it, so a stale "Next" can never
  /// fire twice or leak into an unrelated return to the lobby.
  static (String gameId, int difficulty)? take() {
    final id = _gameId;
    final difficulty = _difficulty;
    _gameId = null;
    _difficulty = null;
    if (id == null || difficulty == null) return null;
    return (id, difficulty);
  }
}
