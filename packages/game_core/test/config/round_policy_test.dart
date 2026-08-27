import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

void main() {
  group('GameRoundPolicy', () {
    test('every mode except pre-assessment plays three rounds', () {
      for (final context in ['post_assessment', 'practice', 'my_path', 'game_lab']) {
        expect(GameRoundPolicy.roundsForContext(context), 3,
            reason: '$context should play three rounds');
      }
    });

    test('pre-assessment keeps four rounds for the evidence game', () {
      // The first pre-assessment game plays the four-condition evidence round
      // (music/haptic/baseline/combined) so the sensory label can read its
      // first combined metric; games 2-4 play three rounds.
      expect(GameRoundPolicy.roundsForContext('pre_assessment'), 4);
    });

    test('configuration versions distinguish the two formats', () {
      expect(GameRoundPolicy.configurationVersionForContext('post_assessment'),
          GameRoundPolicy.standardConfigurationVersion);
      expect(GameRoundPolicy.configurationVersionForContext('practice'),
          GameRoundPolicy.standardConfigurationVersion);
      expect(GameRoundPolicy.configurationVersionForContext('pre_assessment'),
          GameRoundPolicy.sensoryConfigurationVersion);
    });

    test('sensory three-round config version is defined', () {
      expect(GameRoundPolicy.sensoryThreeRoundConfigurationVersion,
          'sensory-three-round-v1');
    });

    test('standard games default to the policy round count', () {
      expect(GameRoundPolicy.standardRoundCount, 3);
    });
  });
}
