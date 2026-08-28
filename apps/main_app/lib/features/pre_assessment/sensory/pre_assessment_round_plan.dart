import 'package:game_core/game_core.dart';

/// Per-game round counts for the four pre-assessment games under AUM-305.
///
/// Game 1 (copy_me) plays the full four-round evidence cycle (music, haptic,
/// baseline, combined): the sensory label uses the FIRST metric of each
/// purpose, and game 1's round-4 combined sample is that first combined
/// metric. Games 2-4 play three rounds (music/haptic/baseline); dropping
/// their combined round cannot change the label, and keeps shared-module
/// sessions short. See docs/aum-305-three-round-impact.md.
abstract final class PreAssessmentRoundPlan {
  static int roundsForGame(int gameIndex) => gameIndex == 0
      ? GameRoundPolicy.sensoryAssessmentRoundCount
      : GameRoundPolicy.standardRoundCount;

  static String configurationVersionForGame(int gameIndex) =>
      gameIndex == 0
          ? GameRoundPolicy.sensoryConfigurationVersion
          : GameRoundPolicy.sensoryThreeRoundConfigurationVersion;
}
