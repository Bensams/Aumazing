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

    test('pre-assessment keeps four rounds for the combined sensory round', () {
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

    test('standard games default to the policy round count', () {
      expect(GameRoundPolicy.standardRoundCount, 3);
    });
  });
}
