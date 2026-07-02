import 'difficulty_profile.dart';

/// Within-session adaptive difficulty stepping.
///
/// Wraps a base [DifficultyProfile] and temporarily steps DOWN one tier for
/// the remainder of the current round when the child struggles (2 consecutive
/// errors), mirroring the prompt-fading / most-to-least prompting practice in
/// ABA intervention. The step is bounded to one tier and resets at the next
/// round, so the parent-visible difficulty stays meaningful.
///
/// Games consult [effective] (not the base profile) when gating hints.
class AdaptiveDifficulty {
  AdaptiveDifficulty(this.base);

  /// The tier selected for this game session (from the AI's per-area level
  /// or the parent's override).
  final DifficultyProfile base;

  /// Consecutive errors triggering a one-tier step-down.
  static const stepDownThreshold = 2;

  int _consecutiveErrors = 0;
  bool _steppedDown = false;

  /// The profile games should follow right now.
  DifficultyProfile get effective => _steppedDown
      ? DifficultyProfile.forLevel(base.level - 1)
      : base;

  /// Whether the current round is running one tier easier than [base].
  bool get isSteppedDown => _steppedDown;

  /// Record a wrong attempt. Returns `true` when this error just triggered
  /// the step-down (so the game can log an analytics event exactly once).
  bool recordError() {
    _consecutiveErrors++;
    if (base.adaptiveSteppingEnabled &&
        !_steppedDown &&
        _consecutiveErrors >= stepDownThreshold &&
        base.level > 1) {
      _steppedDown = true;
      return true;
    }
    return false;
  }

  /// Record a correct attempt (breaks the error streak; an existing
  /// step-down stays in effect until the round ends).
  void recordCorrect() {
    _consecutiveErrors = 0;
  }

  /// Call at the start of every round: the step-down only lasts one round.
  void startRound() {
    _consecutiveErrors = 0;
    _steppedDown = false;
  }
}
