import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/providers/assessment_provider.dart';

AssessmentResult _result(String gameId, DateTime completedAt, {int score = 5}) {
  return AssessmentResult(
    id: '${gameId}_${completedAt.millisecondsSinceEpoch}',
    childId: 'child-1',
    type: 'pre',
    gameId: gameId,
    score: score,
    totalItems: 10,
    errorCount: 1,
    randomTouchCount: 0,
    avgResponseTimeMs: 1200,
    completedAt: completedAt,
  );
}

void main() {
  group('AssessmentProvider.latestPerGame (retake replaces, never stacks)',
      () {
    test('keeps only the newest result per game', () {
      final firstRun = DateTime(2026, 7, 1);
      final retake = DateTime(2026, 7, 3);

      final results = [
        _result('match_it', firstRun, score: 3),
        _result('copy_me', firstRun, score: 4),
        _result('match_it', retake, score: 9),
        _result('copy_me', retake, score: 8),
      ];

      final latest = AssessmentProvider.latestPerGame(results);

      expect(latest.length, 2, reason: 'one result per game, not doubled');
      expect(
          latest.firstWhere((r) => r.gameId == 'match_it').score, 9);
      expect(latest.firstWhere((r) => r.gameId == 'copy_me').score, 8);
    });

    test('order of input does not matter', () {
      final results = [
        _result('match_it', DateTime(2026, 7, 3), score: 9),
        _result('match_it', DateTime(2026, 7, 1), score: 3),
      ];
      final latest = AssessmentProvider.latestPerGame(results);
      expect(latest.single.score, 9);
    });

    test('single run passes through unchanged', () {
      final run = DateTime(2026, 7, 3);
      final results = [
        _result('match_it', run),
        _result('copy_me', run),
        _result('do_what_i_say', run),
        _result('my_turn_your_turn', run),
      ];
      expect(AssessmentProvider.latestPerGame(results).length, 4);
    });
  });

  group('finalized support profile', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('is built once and persisted for the later review', () async {
      final provider = AssessmentProvider();
      await provider.finalizeSupportProfile('child-1');

      expect(provider.supportProfile, isNotNull);

      // Persisted under the child's key, so reopening the Assessment
      // Summary reads these values back instead of recomputing them.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('support_profile_child-1'), isNotNull);
    });

    test('a retake overwrites the stored profile', () async {
      final provider = AssessmentProvider();
      await provider.finalizeSupportProfile('child-1');
      final first = provider.supportProfile!;

      await provider.finalizeSupportProfile('child-1');
      final second = provider.supportProfile!;

      expect(second.recommendedDifficulty, first.recommendedDifficulty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('support_profile_child-1'), isNotNull);
    });

    test('clear() forgets it', () async {
      final provider = AssessmentProvider();
      await provider.finalizeSupportProfile('child-1');
      provider.clear();
      expect(provider.supportProfile, isNull);
    });
  });
}
