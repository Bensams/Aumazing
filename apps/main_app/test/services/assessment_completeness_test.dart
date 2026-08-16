import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/services/assessment_completeness.dart';

/// A run is only scored once it has covered every assessment activity
/// (AUM-154). Each of the four games is the evidence for one developmental
/// area, so a run that stopped early has nothing to say about the areas it
/// never reached.
void main() {
  GameplaySession session(String gameId) => GameplaySession(
    id: 'session-$gameId',
    childId: 'child-a',
    gameId: gameId,
    context: 'pre_assessment',
    score: 8,
    totalItems: 10,
    errorCount: 2,
    totalResponseTimeMs: 12000,
    startedAt: DateTime(2026, 6, 1),
    endedAt: DateTime(2026, 6, 1, 0, 5),
  );

  List<GameplaySession> sessionsFor(List<String> gameIds) => [
    for (final id in gameIds) session(id),
  ];

  final allFour = GameRegistry.assessmentGameIds;

  test('the required set is the registry assessment games', () {
    expect(AssessmentCompleteness.requiredGameIds, allFour);
    expect(allFour, hasLength(4));
  });

  test('all four activities played is complete', () {
    final sessions = sessionsFor(allFour);

    expect(AssessmentCompleteness.isComplete(sessions), isTrue);
    expect(AssessmentCompleteness.missingGames(sessions), isEmpty);
    expect(AssessmentCompleteness.playedCount(sessions), 4);
  });

  test('a run that stopped after one activity is incomplete', () {
    final sessions = sessionsFor([allFour.first]);

    expect(AssessmentCompleteness.isComplete(sessions), isFalse);
    expect(AssessmentCompleteness.missingGames(sessions), hasLength(3));
    expect(AssessmentCompleteness.playedCount(sessions), 1);
  });

  test('an empty run is incomplete, not vacuously complete', () {
    expect(AssessmentCompleteness.isComplete(const []), isFalse);
    expect(AssessmentCompleteness.missingGames(const []), allFour);
  });

  test('missing games come back in registry order', () {
    // Played the second one only; the other three stay in their own order.
    final sessions = sessionsFor([allFour[1]]);

    expect(AssessmentCompleteness.missingGames(sessions), [
      allFour[0],
      allFour[2],
      allFour[3],
    ]);
  });

  test('replaying an activity does not stand in for a missing one', () {
    final sessions = [
      session(allFour[0]),
      session(allFour[0]),
      session(allFour[1]),
    ];

    expect(AssessmentCompleteness.isComplete(sessions), isFalse);
    expect(AssessmentCompleteness.playedCount(sessions), 2);
  });

  test('an unrelated practice game never counts toward completeness', () {
    final sessions = [
      ...sessionsFor(allFour.take(3).toList()),
      session('hintay'),
    ];

    expect(AssessmentCompleteness.isComplete(sessions), isFalse);
    expect(AssessmentCompleteness.playedCount(sessions), 3);
  });

  test('extra games alongside a full set stay complete', () {
    final sessions = [...sessionsFor(allFour), session('hintay')];

    expect(AssessmentCompleteness.isComplete(sessions), isTrue);
  });

  group('the parent-facing explanation', () {
    test('names the progress, not a failure', () {
      final message = AssessmentCompleteness.incompleteMessage(
        sessionsFor([allFour.first]),
      );

      expect(message, contains('1 of 4'));
      expect(message, contains('3 games'));
      // Framed as something to finish, never as an error the parent caused.
      expect(message.toLowerCase(), isNot(contains('failed')));
      expect(message.toLowerCase(), isNot(contains('invalid')));
      expect(message.toLowerCase(), isNot(contains('error')));
    });

    test('uses the singular for a single remaining activity', () {
      final message = AssessmentCompleteness.incompleteMessage(
        sessionsFor(allFour.take(3).toList()),
      );

      expect(message, contains('3 of 4'));
      expect(message, contains('1 game '));
    });

    test('is empty for a complete run', () {
      expect(
        AssessmentCompleteness.incompleteMessage(sessionsFor(allFour)),
        isEmpty,
      );
    });
  });
}
