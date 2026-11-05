import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/services/rubric/rubric.dart';

GameplaySession _play(
  String gameId, {
  int score = 8,
  int totalItems = 10,
  double? completion,
  double? turnTaking,
  int? interruptions,
  int prompts = 0,
}) => GameplaySession(
  id: 's',
  childId: 'c',
  gameId: gameId,
  context: 'recommended_module',
  score: score,
  totalItems: totalItems,
  errorCount: 0,
  totalResponseTimeMs: 0,
  promptCount: prompts,
  taskCompletionRate: completion,
  turnTakingSuccessRate: turnTaking,
  interruptionCount: interruptions,
  startedAt: DateTime(2026, 9, 1),
  endedAt: DateTime(2026, 9, 1, 0, 2),
);

void main() {
  const mastery = PathMastery(thresholds: RubricThresholds.defaults);

  group('PathMastery', () {
    test(
      'general games need accuracy and completion at the Strength cutoff',
      () {
        expect(
          mastery.labelFor(_play('trace_it', score: 8)),
          PerformanceLabel.strength,
        );
        expect(
          mastery.labelFor(_play('trace_it', score: 7)),
          PerformanceLabel.emerging,
        );
        expect(
          mastery.labelFor(_play('trace_it', score: 9, completion: 0.6)),
          PerformanceLabel.emerging,
        );
        expect(
          mastery.labelFor(_play('trace_it', score: 2)),
          PerformanceLabel.needsSupport,
        );
      },
    );

    test('a play with no items is never a Strength', () {
      expect(
        mastery.isStrength(_play('trace_it', score: 0, totalItems: 0)),
        isFalse,
      );
    });

    test('turn-taking uses its own rubric rule', () {
      expect(
        mastery.labelFor(
          _play('my_turn_your_turn', turnTaking: 0.9, interruptions: 4),
        ),
        PerformanceLabel.emerging,
      );
      expect(
        mastery.labelFor(
          _play('my_turn_your_turn', turnTaking: 0.9, interruptions: 1),
        ),
        PerformanceLabel.strength,
      );
    });
  });

  group('PathMastery — instruction prompts', () {
    // copy_me and do_what_i_say log their own round instruction as a prompt,
    // so a flawless play arrives with one prompt per item. That must not
    // hold the path step locked.
    for (final game in ['do_what_i_say', 'copy_me']) {
      test('$game: a perfect play with only the instructions is a Strength',
          () {
        expect(
          mastery.labelFor(
            _play(game, score: 6, totalItems: 6, prompts: 6),
          ),
          PerformanceLabel.strength,
        );
      });

      test('$game: real extra prompts beyond the instructions still count',
          () {
        // 6 instructions + 3 extra repeats → dependency 0.5, not a Strength.
        expect(
          mastery.isStrength(
            _play(game, score: 6, totalItems: 6, prompts: 9),
          ),
          isFalse,
        );
      });
    }

    test('other games are scored on their raw prompt count', () {
      expect(
        mastery.isStrength(
          _play('match_it', score: 10, totalItems: 10, prompts: 10),
        ),
        isFalse,
      );
    });
  });

  group('PathAttemptRecord', () {
    test('keeps the try that first earned a Strength', () {
      var r = const PathAttemptRecord(gameId: 'g', attempts: 0, lastLabel: '');
      final at = DateTime(2026, 9, 1);
      r = r.next(PerformanceLabel.emerging, at);
      expect(r.reachedStrength, isFalse);
      expect(r.retries, 0);
      r = r.next(PerformanceLabel.strength, at);
      r = r.next(PerformanceLabel.needsSupport, at);
      expect(r.attempts, 3);
      expect(r.attemptsToStrength, 2);
      expect(r.retries, 1);
      expect(r.lastLabel, 'Needs Support');

      final roundTrip = PathAttemptRecord.fromMap(r.toMap());
      expect(roundTrip.attemptsToStrength, 2);
      expect(roundTrip.attempts, 3);
    });
  });
}
