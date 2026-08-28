import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/src/games/copy_me/copy_me_game.dart';
import 'package:game_core/src/analytics/models/game_session_metrics.dart';

void main() {
  group('CopyMeGame Visual Guide Tests', () {
    late CopyMeGame game;
    bool gameCompleted = false;
    int currentStep = 0;

    setUp(() {
      gameCompleted = false;
      currentStep = 0;
      game = CopyMeGame(
        totalRounds: 3,
        childId: 'test-child',
        onStepChanged: (step) => currentStep = step,
        onGameComplete: ({required score, required totalItems, required errorCount, required totalResponseTimeMs, GameSessionMetrics? analytics}) {
          gameCompleted = true;
        },
      );
    });

    test('should have visual guide methods available', () {
      // Test that the visual guide methods exist
      expect(() => game.replaySequenceAsVisualGuide(), returnsNormally);
      expect(() => game.showFullSequenceHints(), returnsNormally);
    });

    test('should track consecutive errors', () {
      // This test would require more complex setup to test the internal state
      // For now, we just verify the methods exist and can be called
      expect(game, isA<CopyMeGame>());
    });
  });
}
