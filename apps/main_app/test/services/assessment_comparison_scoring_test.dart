import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aumazing/core/services/auth_service.dart';

import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/services/assessment_service.dart';
import 'package:aumazing/services/scoring_service.dart' as local_scoring;

AssessmentResult _result(
  String gameId, {
  required int score,
  required int errorCount,
  required int totalItems,
  int avgResponseTimeMs = 1000,
  String type = 'pre',
}) => AssessmentResult(
  id: '$type-$gameId',
  childId: 'child-1',
  type: type,
  gameId: gameId,
  score: score,
  totalItems: totalItems,
  errorCount: errorCount,
  avgResponseTimeMs: avgResponseTimeMs,
  completedAt: DateTime(2026, 8, 1),
);

void main() {
  group('canonical item-weighted scoring', () {
    test('overall accuracy matches AssessmentScoring exactly', () {
      final results = [
        // 18/(18+2) = 0.90 over 20 items
        _result('copy_me', score: 18, errorCount: 2, totalItems: 20),
        // 2/(2+3) = 0.40 over 5 items
        _result('match_it', score: 2, errorCount: 3, totalItems: 5),
      ];

      final expected = AssessmentScoring.overallAdjustedAccuracy(
        AssessmentService.gameScores(results),
      );

      // (0.90*20 + 0.40*5) / 25 = 0.80 — not the 0.65 an equal-weighted
      // mean of the two games would give.
      expect(AssessmentService.overallAccuracy(results), closeTo(0.80, 1e-9));
      expect(AssessmentService.overallAccuracy(results), expected);
      expect(
        AssessmentService.overallAccuracy(results),
        isNot(closeTo(0.65, 1e-9)),
      );
    });

    test('response time is weighted by items, not by game', () {
      final results = [
        _result(
          'copy_me',
          score: 10,
          errorCount: 0,
          totalItems: 20,
          avgResponseTimeMs: 1000,
        ),
        _result(
          'match_it',
          score: 5,
          errorCount: 0,
          totalItems: 5,
          avgResponseTimeMs: 5000,
        ),
      ];

      // (1000*20 + 5000*5) / 25 = 1800; an unweighted mean would say 3000.
      expect(
        AssessmentService.weightedAvgResponseTimeMs(results),
        closeTo(1800, 1e-9),
      );
    });

    test('empty and zero-item result sets score 0 rather than dividing by '
        'zero', () {
      expect(AssessmentService.overallAccuracy(const []), 0.0);
      expect(AssessmentService.weightedAvgResponseTimeMs(const []), 0.0);
      expect(
        AssessmentService.overallAccuracy([
          _result('copy_me', score: 0, errorCount: 0, totalItems: 0),
        ]),
        0.0,
      );
    });
  });
  group('critical therapy recommendation threshold', () {
    test('marks item-weighted accuracy below 0.50 as critical', () {
      final results = [
        // 2/20 and 5/5: item-weighted accuracy is 7/25 = 0.28,
        // while an equal game average would incorrectly be 0.55.
        _result('copy_me', score: 2, errorCount: 18, totalItems: 20),
        _result('match_it', score: 5, errorCount: 0, totalItems: 5),
      ];

      expect(
        local_scoring.AssessmentScoring.isCriticallyPoor(results),
        isTrue,
      );
    });
    test('uses adjusted accuracy when retries exceed scored items', () {
      final results = [
        // Retries mean totalItems is 4, but only 4/10 attempts were correct.
        // Raw score/totalItems would be 1.0; canonical adjusted accuracy is .4.
        _result('copy_me', score: 4, errorCount: 6, totalItems: 4),
      ];

      expect(
        local_scoring.AssessmentScoring.isCriticallyPoor(results),
        isTrue,
      );
    });

    test('does not mark exactly 0.50 as critical', () {
      final results = [
        _result('copy_me', score: 50, errorCount: 50, totalItems: 100),
      ];

      expect(
        local_scoring.AssessmentScoring.isCriticallyPoor(results),
        isFalse,
      );
    });

    test('does not mark empty or zero-total results as critical', () {
      expect(local_scoring.AssessmentScoring.isCriticallyPoor(const []), isFalse);
      expect(
        local_scoring.AssessmentScoring.isCriticallyPoor([
          _result('copy_me', score: 0, errorCount: 0, totalItems: 0),
        ]),
        isFalse,
      );
    });
  });


  group('compareAssessments', () {
    // The comparison methods are pure; only the constructor needs an auth
    // client, and the default one would reach for a live Supabase instance.
    late AssessmentService service;
    setUp(
      () =>
          service = AssessmentService(
            authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
          ),
    );

    test('compares pre and post with the canonical policy', () {
      final pre = [
        _result('copy_me', score: 9, errorCount: 11, totalItems: 20),
        _result('match_it', score: 4, errorCount: 1, totalItems: 5),
      ];
      final post = [
        _result(
          'copy_me',
          score: 18,
          errorCount: 2,
          totalItems: 20,
          type: 'post',
        ),
        _result(
          'match_it',
          score: 2,
          errorCount: 3,
          totalItems: 5,
          type: 'post',
        ),
      ];

      final comparison = service.compareAssessments(
        preResults: pre,
        postResults: post,
      );

      expect(comparison['has_data'], isTrue);
      expect(
        comparison['pre_accuracy'],
        closeTo(AssessmentService.overallAccuracy(pre), 1e-9),
      );
      expect(
        comparison['post_accuracy'],
        closeTo(AssessmentService.overallAccuracy(post), 1e-9),
      );
      expect(
        comparison['accuracy_improvement'],
        closeTo(
          AssessmentService.overallAccuracy(post) -
              AssessmentService.overallAccuracy(pre),
          1e-9,
        ),
      );
    });

    test('a differently weighted post run is not flattered by game count', () {
      // The child improved on a 5-item game and regressed on a 20-item one.
      // Equal weighting would report an improvement; item weighting does not.
      final pre = [
        _result('copy_me', score: 18, errorCount: 2, totalItems: 20),
        _result('match_it', score: 1, errorCount: 4, totalItems: 5),
      ];
      final post = [
        _result(
          'copy_me',
          score: 12,
          errorCount: 8,
          totalItems: 20,
          type: 'post',
        ),
        _result(
          'match_it',
          score: 5,
          errorCount: 0,
          totalItems: 5,
          type: 'post',
        ),
      ];

      final comparison = service.compareAssessments(
        preResults: pre,
        postResults: post,
      );
      final equalWeighted =
          (post.map((r) => r.adjustedAccuracy).reduce((a, b) => a + b) /
              post.length) -
          (pre.map((r) => r.adjustedAccuracy).reduce((a, b) => a + b) /
              pre.length);

      expect(equalWeighted, greaterThan(0));
      expect(comparison['accuracy_improvement'] as double, lessThan(0));
    });

    test('an empty side reports no data', () {
      expect(
        service.compareAssessments(preResults: const [], postResults: const []),
        {'has_data': false},
      );
      expect(
        service.compareAssessments(
          preResults: [
            _result('copy_me', score: 1, errorCount: 0, totalItems: 1),
          ],
          postResults: const [],
        ),
        {'has_data': false},
      );
    });
  });
}

class _FakeSupabaseAuthClient implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
