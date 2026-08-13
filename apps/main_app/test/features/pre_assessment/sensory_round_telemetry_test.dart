import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

import 'package:aumazing/features/pre_assessment/sensory/sensory.dart';

/// Builds one recorded round with explicit, *different* telemetry so an
/// even split of the game totals could never reproduce it.
GameRoundMetrics _round(
  int number, {
  required int correct,
  required int wrong,
  int hints = 0,
  int prompts = 0,
  int retries = 0,
  int idle = 0,
  int randomTouches = 0,
  double completionSeconds = 4.0,
  double firstTouchSeconds = 1.0,
}) {
  final round = GameRoundMetrics(roundNumber: number);
  round.correctCount = correct;
  round.wrongCount = wrong;
  round.hintCount = hints;
  round.promptCount = prompts;
  round.retryCount = retries;
  round.idleTimeSeconds = idle;
  round.randomTouchCount = randomTouches;
  round.timeToCompletion = completionSeconds;
  round.timeToFirstTouch = firstTouchSeconds;
  return round;
}

GameSessionMetrics _analytics(List<GameRoundMetrics> rounds) {
  final metrics = GameSessionMetrics(
    sessionId: 'session-1',
    childId: 'child-1',
    gameId: 'copy_me',
    totalRounds: rounds.length,
  );
  metrics.rounds.addAll(rounds);
  return metrics;
}

void main() {
  group('SensoryRoundTelemetry.collect', () {
    test('maps each measured round onto the config that was active', () {
      final collection = SensoryRoundTelemetry.collect(
        gameId: 'copy_me',
        analytics: _analytics([
          _round(1, correct: 5, wrong: 0, idle: 1, completionSeconds: 4),
          _round(
            2,
            correct: 1,
            wrong: 4,
            hints: 2,
            prompts: 1,
            retries: 3,
            idle: 12,
            randomTouches: 6,
            completionSeconds: 20,
            firstTouchSeconds: 5,
          ),
        ]),
        rounds: SensoryRoundConfig.preAssessmentRounds,
      );

      expect(collection.reliable, isTrue);
      expect(collection.metrics, hasLength(2));

      final musicRound = collection.metrics.first;
      expect(musicRound.sensoryConfig, SensoryRoundConfig.round1);
      expect(musicRound.sensoryConfig.purpose, SensoryRoundPurpose.musicOnly);
      expect(musicRound.correctCount, 5);
      expect(musicRound.wrongCount, 0);
      expect(musicRound.accuracy, 1.0);
      expect(musicRound.idleTimeSeconds, 1.0);
      expect(musicRound.timeToCompletionMs, 4000);
      expect(musicRound.avgResponseTimeMs, closeTo(800, 1e-9));
      expect(musicRound.hintCount, 0);

      final hapticRound = collection.metrics.last;
      expect(hapticRound.sensoryConfig, SensoryRoundConfig.round2);
      expect(hapticRound.sensoryConfig.purpose, SensoryRoundPurpose.hapticOnly);
      expect(hapticRound.correctCount, 1);
      expect(hapticRound.wrongCount, 4);
      expect(hapticRound.accuracy, closeTo(0.2, 1e-9));
      expect(hapticRound.hintCount, 2);
      expect(hapticRound.promptCount, 1);
      expect(hapticRound.retryCount, 3);
      expect(hapticRound.idleTimeSeconds, 12.0);
      expect(hapticRound.randomTouchCount, 6);
      expect(hapticRound.tapCount, 11); // 5 interactions + 6 stray touches
      expect(hapticRound.timeToFirstTouchMs, 5000);
      expect(hapticRound.timeToCompletionMs, 20000);

      // The whole point: the conditions are genuinely distinguishable.
      expect(musicRound.accuracy, isNot(hapticRound.accuracy));
    });

    test('a game with no per-round telemetry is unreliable, not invented', () {
      final collection = SensoryRoundTelemetry.collect(
        gameId: 'copy_me',
        analytics: _analytics(const []),
        rounds: SensoryRoundConfig.preAssessmentRounds,
      );

      expect(collection.metrics, isEmpty);
      expect(collection.reliable, isFalse);
    });

    test('missing analytics is unreliable', () {
      final collection = SensoryRoundTelemetry.collect(
        gameId: 'copy_me',
        analytics: null,
        rounds: SensoryRoundConfig.preAssessmentRounds,
      );
      expect(collection.reliable, isFalse);
      expect(collection.metrics, isEmpty);
    });

    test('a round with no matching config marks the set unreliable', () {
      final collection = SensoryRoundTelemetry.collect(
        gameId: 'copy_me',
        analytics: _analytics([
          _round(1, correct: 3, wrong: 1),
          _round(9, correct: 3, wrong: 1), // no round 9 in the experiment
        ]),
        rounds: SensoryRoundConfig.preAssessmentRounds,
      );

      expect(collection.metrics, hasLength(1));
      expect(collection.metrics.single.roundNumber, 1);
      expect(collection.reliable, isFalse);
    });
  });

  group('SensoryPreferenceAnalyzer availability', () {
    List<SensoryRoundMetrics> metrics() =>
        SensoryRoundTelemetry.collect(
          gameId: 'copy_me',
          analytics: _analytics([
            _round(1, correct: 5, wrong: 0, completionSeconds: 3),
            _round(2, correct: 1, wrong: 4, completionSeconds: 18, idle: 10),
            _round(3, correct: 3, wrong: 2, completionSeconds: 9),
            _round(4, correct: 4, wrong: 1, completionSeconds: 6),
          ]),
          rounds: SensoryRoundConfig.preAssessmentRounds,
        ).metrics;

    test('reliable telemetry yields an available recommendation', () {
      final result = SensoryPreferenceAnalyzer().analyze(metrics());

      expect(result.available, isTrue);
      expect(result.configScores, isNotEmpty);
      expect(result.bestConfig, SensoryRoundPurpose.musicOnly);
      expect(result.recommendedMusicEnabled, isTrue);
      expect(result.recommendedHapticEnabled, isFalse);
    });

    test('unreliable telemetry is marked unavailable and low confidence', () {
      final result = SensoryPreferenceAnalyzer().analyze(
        metrics(),
        telemetryReliable: false,
      );

      expect(result.available, isFalse);
      expect(result.confidence, ConfidenceLevel.low);
      expect(result.toMap()['available'], 0);
    });

    test('no metrics at all is unavailable rather than a default answer', () {
      final result = SensoryPreferenceAnalyzer().analyze(const []);

      expect(result.available, isFalse);
      expect(result.confidence, ConfidenceLevel.low);
      expect(result.configScores, isEmpty);
    });
  });
}
