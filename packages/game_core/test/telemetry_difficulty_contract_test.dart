import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

/// Cross-game contract for AUM-221: "consistent game telemetry and difficulty
/// behaviour so that progress and recommendations are trustworthy."
///
/// The three acceptance criteria are structural promises the whole game
/// catalogue must keep, not something to eyeball per game:
///
///   1. Games record applicable attempts, accuracy, duration, hints, completion.
///   2. Easy / medium / hard produce meaningful gameplay differences.
///   3. Hint use is age-appropriate and included in session records.
///
/// These tests hold every registered game to that contract at once, so a new
/// game — or a refactor that drops a wire — cannot regress it silently. The
/// concrete bug this locks down: for most games the registry factory used to
/// ignore `config.difficulty`, so every tier collapsed to Medium.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A no-op registry factory harness. The registry's `create` exposes the
  // simple completion signature (no analytics/extras), so a game can be built
  // headlessly with throwaway callbacks — construction alone is enough to read
  // back the difficulty it was handed.
  FlameGame build(GameEntry entry, {required int difficulty}) => entry.create(
        config: GameConfig(difficulty: difficulty, childId: 'test-child'),
        onStepChanged: (_) {},
        onGameComplete: ({
          required int score,
          required int totalItems,
          required int errorCount,
          required int totalResponseTimeMs,
        }) {},
      );

  group('AC2 — difficulty tiers are meaningfully distinct', () {
    test('each tier carries a different hint/guidance policy', () {
      const easy = DifficultyProfile.easy;
      const medium = DifficultyProfile.medium;
      const hard = DifficultyProfile.hard;

      // Easy = errorless learning: unlimited hints, gesture demos allowed.
      expect(easy.level, 1);
      expect(easy.unlimitedHints, isTrue);
      expect(easy.guidedDemo, isTrue);

      // Medium = delayed prompting: a bounded per-round hint budget, no demo.
      expect(medium.level, 2);
      expect(medium.hintsPerRound, 3);
      expect(medium.guidedDemo, isFalse);
      expect(medium.unlimitedHints, isFalse);
      expect(medium.noHints, isFalse);

      // Hard = independence: no answer hints at all.
      expect(hard.level, 3);
      expect(hard.noHints, isTrue);
      expect(hard.guidedDemo, isFalse);

      // The three (hints, demo) policies must be pairwise distinct — that is
      // what "meaningful gameplay difference" means at the shared-policy layer.
      final policies = {
        for (final p in [easy, medium, hard]) '${p.hintsPerRound}|${p.guidedDemo}',
      };
      expect(policies, hasLength(3));
    });

    test('forLevel maps and clamps 1/2/3 to easy/medium/hard', () {
      expect(DifficultyProfile.forLevel(1).level, 1);
      expect(DifficultyProfile.forLevel(2).level, 2);
      expect(DifficultyProfile.forLevel(3).level, 3);
      // Out-of-range values clamp to a real tier rather than throwing.
      expect(DifficultyProfile.forLevel(0).level, 1);
      expect(DifficultyProfile.forLevel(9).level, 3);
    });

    test('assessment profile freezes difficulty so scores stay comparable', () {
      const a = DifficultyProfile.assessment;
      // Unlimited, non-adaptive hints: every child is measured on the same
      // footing, uncontaminated by the practice-mode tier system.
      expect(a.unlimitedHints, isTrue);
      expect(a.adaptiveSteppingEnabled, isFalse);
    });
  });

  group('AC2/AC3 — within-round adaptive stepping', () {
    test('medium steps down one tier after two consecutive errors', () {
      final adaptive = AdaptiveDifficulty(DifficultyProfile.medium)..startRound();
      expect(adaptive.recordError(), isFalse); // first error: no step yet
      expect(adaptive.recordError(), isTrue); // second: step-down fires once
      expect(adaptive.isSteppedDown, isTrue);
      expect(adaptive.effective.level, 1); // now running Easy for the round
    });

    test('a correct answer breaks the error streak before it steps down', () {
      final adaptive = AdaptiveDifficulty(DifficultyProfile.medium)..startRound();
      adaptive.recordError();
      adaptive.recordCorrect();
      expect(adaptive.recordError(), isFalse); // streak reset, no step-down
      expect(adaptive.isSteppedDown, isFalse);
    });

    test('easy never steps down — there is no easier tier', () {
      final adaptive = AdaptiveDifficulty(DifficultyProfile.easy)..startRound();
      adaptive.recordError();
      expect(adaptive.recordError(), isFalse);
      expect(adaptive.isSteppedDown, isFalse);
    });

    test('assessment never steps down, keeping telemetry constant', () {
      final adaptive =
          AdaptiveDifficulty(DifficultyProfile.assessment)..startRound();
      adaptive.recordError();
      expect(adaptive.recordError(), isFalse);
      expect(adaptive.isSteppedDown, isFalse);
    });

    test('the step-down lasts only one round', () {
      final adaptive = AdaptiveDifficulty(DifficultyProfile.hard)..startRound();
      adaptive.recordError();
      adaptive.recordError();
      expect(adaptive.isSteppedDown, isTrue);
      adaptive.startRound();
      expect(adaptive.isSteppedDown, isFalse);
      expect(adaptive.effective.level, 3);
    });
  });

  group('AC2 — every registered game honours the chosen difficulty', () {
    test('the catalogue is non-empty (guards an empty loop passing vacuously)',
        () {
      expect(GameRegistry.games, isNotEmpty);
    });

    for (final entry in GameRegistry.games) {
      test('${entry.id} builds at the tier it is given', () {
        for (final level in [1, 2, 3]) {
          final game = build(entry, difficulty: level);
          // Every game exposes a `profile`; reading it back proves the factory
          // forwarded config.difficulty instead of collapsing to the default.
          final profile = (game as dynamic).profile as DifficultyProfile;
          expect(profile.level, level,
              reason: '${entry.id} ignored difficulty $level — the tier the '
                  'parent/AI selected never reaches the game');
        }
      });
    }
  });

  group('AC1/AC3 — every registered game wires the telemetry engine', () {
    for (final entry in GameRegistry.games) {
      test('${entry.id} mixes in the shared analytics engine', () {
        final game = build(entry, difficulty: 2);
        expect(game, isA<EnhancedGameplayAnalyticsMixin>(),
            reason: '${entry.id} would record no session metrics, so its '
                'progress and recommendations cannot be trusted');
      });
    }
  });

  group('AC1/AC3 — the telemetry engine records the required indicators', () {
    test('attempts, accuracy, hints and completion are captured and serialised',
        () {
      final metrics = GameSessionMetrics(
        gameId: 'contract_probe',
        sessionId: 'sess-1',
        childId: 'test-child',
        totalRounds: 1,
      );

      metrics.startSession();
      metrics.startRound(roundNumber: 1);
      metrics
        ..recordCorrect()
        ..recordCorrect()
        ..recordWrong() // 2 correct + 1 wrong = 3 attempts, 2/3 accuracy
        ..recordHint(); // hint use lands in the session record
      metrics.completeRound(successful: true);
      metrics.markCompleted();
      metrics.endSession();

      // Attempts + accuracy (AC1).
      expect(metrics.correctCount, 2);
      expect(metrics.wrongCount, 1);
      expect(metrics.totalInteractions, 3);
      expect(metrics.accuracy, closeTo(2 / 3, 1e-9));

      // Hints (AC1/AC3).
      expect(metrics.hintCount, 1);

      // Completion (AC1).
      expect(metrics.isCompleted, isTrue);
      expect(metrics.completedRounds, 1);
      expect(metrics.taskCompletionRate, 1.0);

      // Duration (AC1): the session is bracketed by start/end timestamps.
      expect(metrics.startTime, isNotNull);
      expect(metrics.endTime, isNotNull);
      expect(metrics.durationSeconds, greaterThanOrEqualTo(0));

      // The indicators survive serialisation into both sinks the pipeline
      // reads — a metric recorded but not exported is not "included in the
      // session record".
      final firestore = metrics.toFirestoreMap();
      for (final key in [
        'correct_count',
        'wrong_count',
        'accuracy',
        'hint_count',
        'duration_seconds',
        'is_completed',
        'task_completion_rate',
      ]) {
        expect(firestore.containsKey(key), isTrue,
            reason: 'Firestore record is missing $key');
      }
      expect(firestore['correct_count'], 2);
      expect(firestore['hint_count'], 1);
      expect(firestore['is_completed'], isTrue);

      final xgboost = metrics.toXgboostMap();
      for (final key in [
        'accuracy',
        'hint_count',
        'duration_seconds',
        'is_completed',
      ]) {
        expect(xgboost.containsKey(key), isTrue,
            reason: 'XGBoost row is missing $key');
      }
      // Booleans are 0/1 in the training row.
      expect(xgboost['is_completed'], 1);
    });
  });
}
