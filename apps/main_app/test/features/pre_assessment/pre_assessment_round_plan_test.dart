import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

import 'package:aumazing/features/pre_assessment/sensory/pre_assessment_round_plan.dart';

void main() {
  group('PreAssessmentRoundPlan', () {
    test('game 0 (evidence game) plays the full sensory round count', () {
      expect(PreAssessmentRoundPlan.roundsForGame(0),
          GameRoundPolicy.sensoryAssessmentRoundCount);
    });

    test('games 1-3 play the standard three rounds', () {
      for (final gameIndex in [1, 2, 3]) {
        expect(PreAssessmentRoundPlan.roundsForGame(gameIndex),
            GameRoundPolicy.standardRoundCount,
            reason: 'game $gameIndex should play three rounds');
      }
    });

    test('game 0 uses the sensory four-round config version', () {
      expect(PreAssessmentRoundPlan.configurationVersionForGame(0),
          GameRoundPolicy.sensoryConfigurationVersion);
    });

    test('games 1-3 use the sensory three-round config version', () {
      for (final gameIndex in [1, 2, 3]) {
        expect(PreAssessmentRoundPlan.configurationVersionForGame(gameIndex),
            GameRoundPolicy.sensoryThreeRoundConfigurationVersion,
            reason: 'game $gameIndex should use the three-round config version');
      }
    });
  });
}
