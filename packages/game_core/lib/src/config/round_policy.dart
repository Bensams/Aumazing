/// Central policy for how many rounds each game mode plays.
///
/// Aumazing game modes originally played four rounds everywhere. Card AUM-305
/// reduces all game modes to three rounds. The pre-assessment sensory phase is
/// the deliberate exception: it collects the `combined` sensory condition as a
/// distinct fourth round, and removing it would silently make the combined
/// sensory recommendation unreachable. That cutover is product-owner gated (see
/// docs/aum-305-three-round-impact.md).
abstract final class GameRoundPolicy {
  /// Standard number of rounds for every mode except pre-assessment.
  static const int standardRoundCount = 3;

  /// Number of rounds for the pre-assessment sensory phase.
  ///
  /// Kept at four so the `combined` sensory condition (the genuinely distinct
  /// sensory evidence collected in round four) remains reachable. Reducing it
  /// to three would make that recommendation path unavailable and is therefore
  /// product-owner gated.
  static const int sensoryAssessmentRoundCount = 4;

  /// Analytics config version for the standard three-round format.
  static const String standardConfigurationVersion = 'three-round-v1';

  /// Analytics config version for the sensory four-round pre-assessment.
  static const String sensoryConfigurationVersion = 'sensory-four-round-v1';

  /// Actual round count to play for a given assessment/practice [context].
  ///
  /// Only `pre_assessment` keeps four rounds (for the sensory `combined`
  /// condition); every other mode (post_assessment, practice, My Path,
  /// game_lab) plays three.
  static int roundsForContext(String context) =>
      context == 'pre_assessment' ? sensoryAssessmentRoundCount : standardRoundCount;

  /// Analytics configuration-version identifier for a given [context].
  static String configurationVersionForContext(String context) =>
      context == 'pre_assessment'
          ? sensoryConfigurationVersion
          : standardConfigurationVersion;
}
