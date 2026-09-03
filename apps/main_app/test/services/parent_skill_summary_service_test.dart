import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/services/parent_skill_summary_service.dart';
import 'package:flutter_test/flutter_test.dart';

AreaLevel _areaLevel(int levelInt) => AreaLevel(
  level: const ['needs_support', 'emerging', 'strength'][levelInt],
  levelInt: levelInt,
  levelName: const ['Needs Support', 'Emerging', 'Strength'][levelInt],
  confidence: 0.9,
);

AssessmentResult _result({
  required String gameId,
  required int score,
  required int totalItems,
  required int errors,
  String type = 'pre',
  String runId = 'run-pre',
  String? communication = 'Emerging',
  String? play = 'Strength',
  String? social = 'Needs Support',
  String? attention = 'Variable Attention',
}) => AssessmentResult(
  id: '$runId-$gameId',
  childId: 'child-1',
  assessmentRunId: runId,
  gameId: gameId,
  type: type,
  score: score,
  totalItems: totalItems,
  errorCount: errors,
  avgResponseTimeMs: 1000,
  completedAt: type == 'post' ? DateTime(2026, 2, 1) : DateTime(2026, 1, 1),
  communicationLabel: communication,
  playSkillsLabel: play,
  socialInteractionLabel: social,
  behaviorAttentionLabel: attention,
);

GameplaySession _session({
  required String gameId,
  required String runId,
  double? completion,
  double? turnTaking,
  int? interruptions,
  double idle = 0,
  int randomTouches = 0,
}) => GameplaySession(
  id: '$runId-session-$gameId',
  childId: 'child-1',
  assessmentRunId: runId,
  gameId: gameId,
  context: runId.contains('post') ? 'post_assessment' : 'pre_assessment',
  score: 8,
  totalItems: 10,
  errorCount: 2,
  totalResponseTimeMs: 10000,
  idleTimeSeconds: idle,
  randomTouchCount: randomTouches,
  taskCompletionRate: completion,
  turnTakingSuccessRate: turnTaking,
  interruptionCount: interruptions,
  startedAt: DateTime(2026, 1, 1),
  endedAt: DateTime(2026, 1, 1, 0, 1),
);

void main() {
  group('ParentSkillSummaryService', () {
    test('the AI prediction levels override the rubric labels so the snapshot '
        'matches the summary Developmental Profile', () {
      final results = [
        _result(gameId: 'copy_me', score: 8, totalItems: 10, errors: 2),
        _result(gameId: 'do_what_i_say', score: 6, totalItems: 10, errors: 4),
        _result(gameId: 'match_it', score: 10, totalItems: 10, errors: 0),
        _result(gameId: 'my_turn_your_turn', score: 8, totalItems: 10, errors: 2),
      ];
      // Rubric labels say a mix (Emerging/Strength/Needs Support/Variable), but
      // the finalized AI prediction says every area is a Strength.
      final summary = ParentSkillSummaryService.build(
        assessmentType: 'pre',
        results: results,
        areaLevels: {
          'communication': _areaLevel(2),
          'social': _areaLevel(2),
          'play': _areaLevel(2),
          'attention': _areaLevel(2),
        },
      );

      expect(summary.area('communication')!.levelInt, 2);
      expect(summary.area('communication')!.levelName, 'Strength');
      expect(summary.area('social')!.levelInt, 2);
      expect(summary.area('play')!.levelInt, 2);
      // Attention keeps its own vocabulary but the prediction's level value.
      expect(summary.area('attention')!.levelInt, 2);
      expect(summary.area('attention')!.levelName, 'Sustained');
    });

    test('falls back to the rubric labels when no prediction is supplied', () {
      final summary = ParentSkillSummaryService.build(
        assessmentType: 'pre',
        results: [
          _result(
            gameId: 'copy_me',
            score: 8,
            totalItems: 10,
            errors: 2,
            communication: 'Needs Support',
          ),
        ],
      );
      expect(summary.area('communication')!.levelName, 'Needs Support');
      expect(summary.area('communication')!.levelInt, 0);
    });

    test('builds the four parent areas in the requested order', () {
      final summary = ParentSkillSummaryService.build(
        assessmentType: 'pre',
        results: [
          _result(gameId: 'copy_me', score: 8, totalItems: 10, errors: 2),
          _result(gameId: 'do_what_i_say', score: 6, totalItems: 10, errors: 4),
          _result(gameId: 'match_it', score: 10, totalItems: 10, errors: 0),
          _result(
            gameId: 'my_turn_your_turn',
            score: 5,
            totalItems: 10,
            errors: 5,
          ),
        ],
      );

      expect(summary.areas.map((area) => area.label), [
        'Communication',
        'Play Skills',
        'Social Interaction',
        'Attention & Focus',
      ]);
      expect(summary.areas.map((area) => area.levelName), [
        'Emerging',
        'Strength',
        'Needs Support',
        'Variable',
      ]);
      expect(summary.area('communication')!.metricPercent, 70);
      expect(summary.area('play')!.metricPercent, 90);
      expect(summary.area('social')!.metricPercent, 50);
    });

    test('uses telemetry for social and attention evidence when available', () {
      final results = [
        _result(
          gameId: 'my_turn_your_turn',
          score: 5,
          totalItems: 10,
          errors: 5,
        ),
        _result(gameId: 'match_it', score: 8, totalItems: 10, errors: 2),
      ];
      final summary = ParentSkillSummaryService.build(
        assessmentType: 'pre',
        results: results,
        sessions: [
          _session(
            gameId: 'my_turn_your_turn',
            runId: 'run-pre',
            completion: 0.8,
            turnTaking: 0.65,
            interruptions: 3,
            idle: 8,
            randomTouches: 4,
          ),
          _session(
            gameId: 'match_it',
            runId: 'run-pre',
            completion: 1,
            idle: 4,
            randomTouches: 2,
          ),
        ],
      );

      final social = summary.area('social')!;
      expect(social.metricLabel, 'successful turn-taking');
      expect(social.metricPercent, 65);
      expect(social.detail, '3 average interruptions');

      final attention = summary.area('attention')!;
      expect(attention.metricPercent, 90);
      expect(attention.detail, contains('6s average idle time'));
      expect(attention.detail, contains('3 average off-target touches'));
    });

    test('does not invent a level for legacy rows with missing labels', () {
      final summary = ParentSkillSummaryService.build(
        assessmentType: 'pre',
        results: [
          _result(
            gameId: 'copy_me',
            score: 8,
            totalItems: 10,
            errors: 2,
            communication: null,
            play: null,
            social: null,
            attention: null,
          ),
        ],
      );

      expect(
        summary.areas.map((area) => area.levelName),
        everyElement('Not enough data'),
      );
      expect(summary.areas.map((area) => area.levelInt), everyElement(isNull));
    });

    test('compares percentage points and band movement separately', () {
      final before = ParentSkillSummaryService.build(
        assessmentType: 'pre',
        results: [
          _result(
            gameId: 'copy_me',
            score: 6,
            totalItems: 10,
            errors: 4,
            communication: 'Emerging',
          ),
        ],
      );
      final after = ParentSkillSummaryService.build(
        assessmentType: 'post',
        results: [
          _result(
            gameId: 'copy_me',
            score: 9,
            totalItems: 10,
            errors: 1,
            type: 'post',
            runId: 'run-post',
            communication: 'Strength',
          ),
        ],
      );

      final progress = ParentSkillSummaryService.compare(
        before: before,
        after: after,
      );
      final communication = progress.areas.first;

      expect(communication.levelDelta, 1);
      expect(communication.metricDelta, 30);
      expect(progress.overallAccuracyDelta, closeTo(0.3, 1e-9));
      expect(progress.improvedAreaCount, 1);
    });
  });
}
