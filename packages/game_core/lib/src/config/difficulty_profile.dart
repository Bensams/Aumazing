/// Hint/guidance policy for one difficulty tier (1–3).
///
/// Mirrors the ABA prompt hierarchy used in ASD intervention:
///
/// - **Level 1 (Easy)** — errorless learning: unlimited hints that escalate
///   (target glow → guided gesture demo) so the child can never stay stuck.
/// - **Level 2 (Medium)** — delayed prompting: a small hint budget per round,
///   given only after a wrong attempt or idle time.
/// - **Level 3 (Hard)** — independence: no answer hints. After long inactivity
///   the instruction voice-over is re-played (re-orientation, not an answer),
///   so the child is never abandoned mid-game.
///
/// Tiers map from the on-device AI's per-area levels:
/// `needs_support` → Easy, `emerging` → Medium, `strength` → Hard
/// (aligned with DSM-5 support levels 3 / 2 / 1 respectively).
class DifficultyProfile {
  const DifficultyProfile({
    required this.level,
    required this.hintsPerRound,
    required this.idleHintDelay,
    required this.guidedDemo,
    required this.reorientDelay,
    this.adaptiveSteppingEnabled = true,
  });

  /// Difficulty tier: 1 (Easy) … 3 (Hard).
  final int level;

  /// Answer hints allowed per round. `null` = unlimited, `0` = none.
  final int? hintsPerRound;

  /// Idle time before an answer hint is offered (Easy/Medium).
  final Duration idleHintDelay;

  /// Whether the ghost-hand gesture demo may be shown (Easy only).
  final bool guidedDemo;

  /// Idle time before the instruction is re-played when answer hints are
  /// unavailable (Hard tier, or a spent Medium budget).
  final Duration reorientDelay;

  /// Whether within-round adaptive stepping may apply (see
  /// AdaptiveDifficulty). Disabled for assessment so hint behaviour stays
  /// constant and never contaminates the scores that drive the AI levels.
  final bool adaptiveSteppingEnabled;

  static const easy = DifficultyProfile(
    level: 1,
    hintsPerRound: null, // unlimited — errorless learning
    idleHintDelay: Duration(seconds: 5),
    guidedDemo: true,
    reorientDelay: Duration(seconds: 20),
  );

  static const medium = DifficultyProfile(
    level: 2,
    hintsPerRound: 3,
    idleHintDelay: Duration(seconds: 8),
    guidedDemo: false,
    reorientDelay: Duration(seconds: 20),
  );

  static const hard = DifficultyProfile(
    level: 3,
    hintsPerRound: 0, // no answer hints
    idleHintDelay: Duration(seconds: 8), // unused when hintsPerRound == 0
    guidedDemo: false,
    reorientDelay: Duration(seconds: 20),
  );

  /// Assessment profile: mirrors the games' original (pre-tier) hint
  /// behaviour — unlimited hints, 10s idle, no gesture demos, no adaptive
  /// stepping — so assessment telemetry stays comparable across children
  /// and unaffected by the practice-mode difficulty system.
  static const assessment = DifficultyProfile(
    level: 2,
    hintsPerRound: null,
    idleHintDelay: Duration(seconds: 10),
    guidedDemo: false,
    reorientDelay: Duration(seconds: 10),
    adaptiveSteppingEnabled: false,
  );

  /// The profile for a 1–3 difficulty value (clamped; defaults to Medium).
  factory DifficultyProfile.forLevel(int difficulty) {
    switch (difficulty.clamp(1, 3)) {
      case 1:
        return easy;
      case 3:
        return hard;
      default:
        return medium;
    }
  }

  bool get unlimitedHints => hintsPerRound == null;
  bool get noHints => hintsPerRound == 0;

  /// Parent-facing tier name.
  String get label {
    switch (level) {
      case 1:
        return 'Easy';
      case 3:
        return 'Hard';
      default:
        return 'Medium';
    }
  }

  @override
  String toString() =>
      'DifficultyProfile($label, hints: ${hintsPerRound ?? '∞'}, '
      'idle: ${idleHintDelay.inSeconds}s, demo: $guidedDemo)';
}
