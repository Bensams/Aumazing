/// Central policy for how many rounds each game mode plays.
///
/// Aumazing game modes originally played four rounds everywhere. Card AUM-305
/// reduces all game modes to three rounds. The pre-assessment sensory phase is
/// the deliberate exception: its first game (the evidence game) collects the
/// `combined` sensory condition as a distinct fourth round, and removing it
/// would silently make the combined sensory recommendation unreachable. The
/// per-game split (game 0 plays four rounds, games 1-3 play three) is owned by
/// PreAssessmentRoundPlan in main_app. That cutover is product-owner gated (see
/// docs/aum-305-three-round-impact.md).
abstract final class GameRoundPolicy {
  /// Standard number of rounds for every mode except pre-assessment.
  static const int standardRoundCount = 3;

  /// Number of rounds for the first pre-assessment game (the evidence game).
  ///
  /// Kept at four so the pre-assessment evidence game collects the `combined`
  /// sensory condition in a distinct fourth round — the genuinely distinct
  /// sensory evidence that the sensory label reads as its first combined
  /// metric. Reducing it to three would make that recommendation path
  /// unavailable and is therefore product-owner gated. The per-game split
  /// (game 0 = four rounds, games 1-3 = three) is owned by
  /// PreAssessmentRoundPlan in main_app.
  static const int sensoryAssessmentRoundCount = 4;

  /// Analytics config version for the standard three-round format.
  static const String standardConfigurationVersion = 'three-round-v1';

  /// Analytics config version for the sensory four-round pre-assessment.
  static const String sensoryConfigurationVersion = 'sensory-four-round-v1';

  /// Analytics config version for the three-round sensory format played by
  /// pre-assessment games 2-4.
  static const String sensoryThreeRoundConfigurationVersion = 'sensory-three-round-v1';

  /// Actual round count to play for a given assessment/practice [context].
  ///
  /// Only `pre_assessment` keeps four rounds (the evidence game's `combined`
  /// condition); every other mode (post_assessment, practice, My Path,
  /// game_lab) plays three. Pre-assessment games 2-4 play three rounds, owned
  /// by PreAssessmentRoundPlan in main_app.
  static int roundsForContext(String context) =>
      context == 'pre_assessment' ? sensoryAssessmentRoundCount : standardRoundCount;

  /// Analytics configuration-version identifier for a given [context].
  static String configurationVersionForContext(String context) =>
      context == 'pre_assessment'
          ? sensoryConfigurationVersion
          : standardConfigurationVersion;
}
