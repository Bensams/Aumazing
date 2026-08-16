import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/assessment_run_snapshot.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/services/assessment_progress_service.dart';

/// Pre → post comparison rules (AUM-161).
///
/// The point of the comparability gate is that an *invented* improvement is
/// worse than no comparison, so these lean on the cases where two runs look
/// superficially comparable but are not.
void main() {
  AssessmentResult result(
    String gameId, {
    String? runId,
    String childId = 'child-a',
    String type = 'pre',
  }) => AssessmentResult(
    id: '$gameId-${runId ?? 'none'}',
    childId: childId,
    type: type,
    gameId: gameId,
    score: 8,
    totalItems: 10,
    errorCount: 2,
    avgResponseTimeMs: 1200,
    completedAt: DateTime(2026, 1, 1),
    assessmentRunId: runId,
  );

  SupportProfile profileWith({
    String communication = 'needs_support',
    String social = 'needs_support',
    String play = 'needs_support',
    String attention = 'needs_support',
  }) => SupportProfile(
    communication: communication,
    socialInteraction: social,
    playSkills: play,
    attention: attention,
    recommendedDifficulty: 'easy',
    recommendedPromptStyle: 'visual',
    recommendedSessionMinutes: 5,
    promptRepetition: 2,
  );

  AssessmentRunSnapshot snapshot({
    required String type,
    required DateTime completedAt,
    String childId = 'child-a',
    String? runId,
    SupportProfile? profile,
    List<AssessmentResult>? results,
  }) => AssessmentRunSnapshot(
    assessmentType: type,
    childId: childId,
    completedAt: completedAt,
    assessmentRunId: runId,
    results:
        results ??
        [result('copy_me', runId: runId, childId: childId, type: type)],
    profile: profile ?? profileWith(),
  );

  group('areComparable', () {
    test('a later run for the same child is comparable', () {
      final before = snapshot(type: 'pre', completedAt: DateTime(2026, 1, 1));
      final after = snapshot(type: 'post', completedAt: DateTime(2026, 2, 1));

      expect(AssessmentProgressService.areComparable(before, after), isTrue);
    });

    test('runs from different children are never comparable', () {
      final before = snapshot(
        type: 'pre',
        completedAt: DateTime(2026, 1, 1),
        childId: 'child-a',
      );
      final after = snapshot(
        type: 'post',
        completedAt: DateTime(2026, 2, 1),
        childId: 'child-b',
      );

      expect(AssessmentProgressService.areComparable(before, after), isFalse);
      expect(
        AssessmentProgressService.compare(before: before, after: after),
        isNull,
      );
    });

    test('the same run read twice is not a comparison', () {
      final run = snapshot(
        type: 'pre',
        completedAt: DateTime(2026, 1, 1),
        runId: 'run-1',
      );

      expect(AssessmentProgressService.areComparable(run, run), isFalse);
    });

    test('an "after" run that predates the baseline is rejected', () {
      final before = snapshot(type: 'pre', completedAt: DateTime(2026, 3, 1));
      final after = snapshot(type: 'post', completedAt: DateTime(2026, 2, 1));

      expect(AssessmentProgressService.areComparable(before, after), isFalse);
    });

    test('a run with no stored profile cannot be compared', () {
      final before = AssessmentRunSnapshot(
        assessmentType: 'pre',
        childId: 'child-a',
        completedAt: DateTime(2026, 1, 1),
        results: [result('copy_me', runId: 'run-1')],
      );
      final after = snapshot(type: 'post', completedAt: DateTime(2026, 2, 1));

      expect(AssessmentProgressService.areComparable(before, after), isFalse);
    });

    test('a missing run is not comparable', () {
      final after = snapshot(type: 'post', completedAt: DateTime(2026, 2, 1));

      expect(AssessmentProgressService.areComparable(null, after), isFalse);
      expect(AssessmentProgressService.areComparable(after, null), isFalse);
      expect(
        AssessmentProgressService.compare(before: null, after: after),
        isNull,
      );
    });
  });

  group('compare', () {
    test('reports the areas that moved up and those that held steady', () {
      final before = snapshot(
        type: 'pre',
        completedAt: DateTime(2026, 1, 1),
        runId: 'run-1',
        profile: profileWith(
          communication: 'needs_support', // 0
          social: 'developing', // 1
          play: 'needs_support', // 0
          attention: 'needs_support', // 0
        ),
      );
      final after = snapshot(
        type: 'post',
        completedAt: DateTime(2026, 2, 1),
        runId: 'run-2',
        profile: profileWith(
          communication: 'developing', // 0 → 1, up
          social: 'developing', // 1 → 1, steady
          play: 'strong', // 0 → 2, up
          attention: 'needs_support', // 0 → 0, steady
        ),
      );

      final progress =
          AssessmentProgressService.compare(before: before, after: after)!;

      expect(progress.areas, hasLength(4));
      expect(progress.improvedCount, 2);
      expect(progress.steadyCount, 2);

      final communication = progress.areas.firstWhere(
        (a) => a.label == 'Communication',
      );
      expect(communication.beforeLevelName, 'Needs Support');
      expect(communication.afterLevelName, 'Emerging');
      expect(communication.improved, isTrue);

      final attention = progress.areas.firstWhere(
        (a) => a.label == 'Attention',
      );
      expect(attention.steady, isTrue);
      expect(attention.delta, 0);
    });

    test('a drop is reported honestly rather than hidden', () {
      final before = snapshot(
        type: 'pre',
        completedAt: DateTime(2026, 1, 1),
        runId: 'run-1',
        profile: profileWith(communication: 'strong'),
      );
      final after = snapshot(
        type: 'post',
        completedAt: DateTime(2026, 2, 1),
        runId: 'run-2',
        profile: profileWith(communication: 'needs_support'),
      );

      final progress =
          AssessmentProgressService.compare(before: before, after: after)!;
      final communication = progress.areas.firstWhere(
        (a) => a.label == 'Communication',
      );

      expect(communication.delta, lessThan(0));
      expect(communication.improved, isFalse);
      expect(communication.steady, isFalse);
    });

    test('the headline stays neutral when nothing moved', () {
      final before = snapshot(
        type: 'pre',
        completedAt: DateTime(2026, 1, 1),
        runId: 'run-1',
      );
      final after = snapshot(
        type: 'post',
        completedAt: DateTime(2026, 2, 1),
        runId: 'run-2',
      );

      final progress =
          AssessmentProgressService.compare(before: before, after: after)!;

      expect(progress.improvedCount, 0);
      expect(progress.headline, contains('held steady'));
      // Never framed as a failure or a concern.
      expect(progress.headline.toLowerCase(), isNot(contains('no progress')));
      expect(progress.headline.toLowerCase(), isNot(contains('failed')));
    });

    test('growth is stated plainly in the headline', () {
      final before = snapshot(
        type: 'pre',
        completedAt: DateTime(2026, 1, 1),
        runId: 'run-1',
        profile: profileWith(communication: 'needs_support'),
      );
      final after = snapshot(
        type: 'post',
        completedAt: DateTime(2026, 2, 1),
        runId: 'run-2',
        profile: profileWith(communication: 'strong'),
      );

      final progress =
          AssessmentProgressService.compare(before: before, after: after)!;

      expect(progress.headline, contains('Grew in 1 of 4'));
    });

    test('carries both completion dates for the parent', () {
      final before = snapshot(
        type: 'pre',
        completedAt: DateTime(2026, 1, 1),
        runId: 'run-1',
      );
      final after = snapshot(
        type: 'post',
        completedAt: DateTime(2026, 2, 1),
        runId: 'run-2',
      );

      final progress =
          AssessmentProgressService.compare(before: before, after: after)!;

      expect(progress.beforeCompletedAt, DateTime(2026, 1, 1));
      expect(progress.afterCompletedAt, DateTime(2026, 2, 1));
    });
  });

  group('non-diagnostic language (AUM-161)', () {
    test('no comparison wording implies a diagnosis or condition', () {
      final before = snapshot(
        type: 'pre',
        completedAt: DateTime(2026, 1, 1),
        runId: 'run-1',
        profile: profileWith(communication: 'needs_support'),
      );
      final after = snapshot(
        type: 'post',
        completedAt: DateTime(2026, 2, 1),
        runId: 'run-2',
        profile: profileWith(communication: 'strong'),
      );

      final progress =
          AssessmentProgressService.compare(before: before, after: after)!;

      const banned = [
        'diagnos',
        'disorder',
        'severity',
        'symptom',
        'condition',
        'impair',
        'deficit',
        'normal',
        'abnormal',
        'cure',
        'treat',
      ];
      final wording =
          [
            progress.headline,
            for (final area in progress.areas)
              '${area.label} ${area.beforeLevelName} ${area.afterLevelName}',
          ].join(' ').toLowerCase();

      for (final word in banned) {
        expect(wording, isNot(contains(word)), reason: 'must avoid "$word"');
      }
    });
  });
}
