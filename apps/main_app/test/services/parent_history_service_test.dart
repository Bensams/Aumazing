import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/assessment_run_record.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/services/learning_path_service.dart';
import 'package:aumazing/services/parent_history_service.dart';

AreaLevel _level(int levelInt) => AreaLevel(
  level: ['needs_support', 'emerging', 'strength'][levelInt],
  levelInt: levelInt,
  levelName: ['Needs Support', 'Emerging', 'Strength'][levelInt],
  confidence: 0.9,
);

AssessmentResult _result({
  required String id,
  String? assessmentRunId,
  String type = 'pre',
  String gameId = 'match_it',
  String? playSkillsLabel,
  String? communicationLabel,
  String? socialInteractionLabel,
  String? behaviorAttentionLabel,
  String? sensoryPreferenceLabel,
  String? recommendedModule,
  String? overallSummary,
}) => AssessmentResult(
  id: id,
  childId: 'child-1',
  assessmentRunId: assessmentRunId,
  type: type,
  gameId: gameId,
  score: 8,
  totalItems: 10,
  errorCount: 2,
  avgResponseTimeMs: 1000,
  completedAt: DateTime(2026, 8, 6),
  playSkillsLabel: playSkillsLabel,
  communicationLabel: communicationLabel,
  socialInteractionLabel: socialInteractionLabel,
  behaviorAttentionLabel: behaviorAttentionLabel,
  sensoryPreferenceLabel: sensoryPreferenceLabel,
  recommendedModule: recommendedModule,
  overallSummary: overallSummary,
);

AssessmentRunRecord _run({
  required String id,
  String type = 'pre',
  String status = 'completed',
  required DateTime startedAt,
  DateTime? completedAt,
}) => AssessmentRunRecord(
  id: id,
  childId: 'child-1',
  type: type,
  status: status,
  startedAt: startedAt,
  completedAt: completedAt,
);

GameplaySession _session({
  required String id,
  String? assessmentRunId,
  required String gameId,
  String context = 'practice',
  required int score,
  required int errorCount,
  required DateTime startedAt,
  DateTime? endedAt,
  String? configurationVersion,
}) => GameplaySession(
  id: id,
  childId: 'child-1',
  assessmentRunId: assessmentRunId,
  gameId: gameId,
  context: context,
  score: score,
  totalItems: 10,
  errorCount: errorCount,
  totalResponseTimeMs: 2000,
  startedAt: startedAt,
  endedAt: endedAt ?? startedAt.add(const Duration(minutes: 5)),
  configurationVersion: configurationVersion,
);

void main() {
  group('ParentHistoryService.configLabelFor', () {
    test('maps known configuration versions to flow labels', () {
      expect(ParentHistoryService.configLabelFor(null), 'Legacy');
      expect(
        ParentHistoryService.configLabelFor('three-round-v1'),
        '3-round flow',
      );
      expect(
        ParentHistoryService.configLabelFor('sensory-four-round-v1'),
        '4-round sensory flow',
      );
      expect(
        ParentHistoryService.configLabelFor('sensory-three-round-v1'),
        '3-round sensory flow',
      );
      expect(ParentHistoryService.configLabelFor('some-unknown'), 'Legacy');
    });
  });

  group('ParentHistoryService.aggregateSkills', () {
    test('uses a single result label per area', () {
      final skills = ParentHistoryService.aggregateSkills([
        _result(
          id: 'r1',
          communicationLabel: 'Strength',
          socialInteractionLabel: 'Emerging',
        ),
      ]);

      expect(skills, hasLength(2));
      expect(skills[0].area, 'Communication');
      expect(skills[0].label, 'Strength');
      expect(skills[1].area, 'Social Interaction');
      expect(skills[1].label, 'Emerging');
    });

    test('majority label wins across results', () {
      final skills = ParentHistoryService.aggregateSkills([
        _result(id: 'r1', communicationLabel: 'Strength'),
        _result(id: 'r2', communicationLabel: 'Strength'),
        _result(id: 'r3', communicationLabel: 'Emerging'),
      ]);

      final communication = skills.firstWhere((s) => s.area == 'Communication');
      expect(communication.label, 'Strength');
    });

    test('a tie resolves toward the more conservative label', () {
      final skills = ParentHistoryService.aggregateSkills([
        _result(id: 'r1', playSkillsLabel: 'Strength'),
        _result(id: 'r2', playSkillsLabel: 'Emerging'),
      ]);

      final play = skills.firstWhere((s) => s.area == 'Play Skills');
      expect(play.label, 'Emerging');

      final conservative = ParentHistoryService.aggregateSkills([
        _result(id: 'r1', playSkillsLabel: 'Strength'),
        _result(id: 'r2', playSkillsLabel: 'Needs Support'),
      ]);
      final play2 = conservative.firstWhere((s) => s.area == 'Play Skills');
      expect(play2.label, 'Needs Support');
    });

    test('areas with only null labels are omitted', () {
      final skills = ParentHistoryService.aggregateSkills([
        _result(id: 'r1', communicationLabel: 'Strength'),
      ]);

      final areas = skills.map((s) => s.area).toList();
      expect(areas, isNot(contains('Sensory Preference')));
      expect(areas, isNot(contains('Attention & Focus')));
      expect(areas, isNot(contains('Play Skills')));
    });

    test('output follows the fixed area order', () {
      final skills = ParentHistoryService.aggregateSkills([
        _result(
          id: 'r1',
          sensoryPreferenceLabel: 'Strength',
          playSkillsLabel: 'Emerging',
          communicationLabel: 'Strength',
        ),
      ]);

      final areas = skills.map((s) => s.area).toList();
      expect(
        areas,
        [
          'Communication',
          'Social Interaction',
          'Play Skills',
          'Attention & Focus',
          'Sensory Preference',
        ].where(areas.contains).toList(),
      );
    });
  });

  group('ParentHistoryService.loadHistory', () {
    test('builds a full summary: runs sorted, games sorted, accuracy, '
        'skills, My Path, practice', () async {
      // The pre run is the newest by startedAt but the post run is older.
      final preRun = _run(
        id: 'run-pre',
        status: 'completed',
        startedAt: DateTime(2026, 8, 5, 9),
        completedAt: DateTime(2026, 8, 6, 9),
      );
      final postRun = _run(
        id: 'run-post',
        type: 'post',
        status: 'in_progress',
        startedAt: DateTime(2026, 8, 1, 9),
      );

      final path = LearningPathService.buildPath(
        areaLevels: {'communication': _level(0)},
      );
      expect(path, isNotEmpty);
      final pathIds = path.map((e) => e.game.id).toSet();

      final summary = await ParentHistoryService(
        localDb: _FakeDb(
          runs: [preRun, postRun],
          results: [
            _result(
              id: 'res-pre',
              assessmentRunId: 'run-pre',
              communicationLabel: 'Strength',
              recommendedModule: 'Emotions Module',
              overallSummary: 'Great progress!',
            ),
          ],
          sessions: [
            _session(
              id: 's1',
              assessmentRunId: 'run-pre',
              gameId: 'match_it',
              context: 'pre_assessment',
              score: 8,
              errorCount: 2,
              startedAt: DateTime(2026, 8, 5, 9, 0),
            ),
            _session(
              id: 's2',
              assessmentRunId: 'run-pre',
              gameId: 'copy_me',
              context: 'pre_assessment',
              score: 5,
              errorCount: 5,
              startedAt: DateTime(2026, 8, 5, 10, 0),
              configurationVersion: 'three-round-v1',
            ),
            _session(
              id: 's3',
              assessmentRunId: 'run-post',
              gameId: 'match_it',
              context: 'post_assessment',
              score: 9,
              errorCount: 1,
              startedAt: DateTime(2026, 8, 1, 9, 0),
            ),
            // Practice sessions, newest endedAt first below.
            _session(
              id: 'p-a',
              gameId: pathIds.first,
              context: 'practice',
              score: 10,
              errorCount: 0,
              startedAt: DateTime(2026, 8, 3, 9),
              endedAt: DateTime(2026, 8, 3, 10),
            ),
            _session(
              id: 'p-b',
              gameId: 'my_turn_your_turn',
              context: 'practice',
              score: 10,
              errorCount: 0,
              startedAt: DateTime(2026, 8, 2, 9),
              endedAt: DateTime(2026, 8, 2, 10),
            ),
          ],
        ),
      ).loadHistory(
        childId: 'child-1',
        path: path,
        pathCompletedGameIds: pathIds,
      );

      // Runs sorted by startedAt DESC (pre is newer).
      expect(summary.runs, hasLength(2));
      expect(summary.runs[0].run.id, 'run-pre');
      expect(summary.runs[1].run.id, 'run-post');

      // Pre run: games sorted by startedAt ASC.
      final pre = summary.runs[0];
      expect(pre.games, hasLength(2));
      expect(pre.games[0].gameId, 'match_it');
      expect(pre.games[1].gameId, 'copy_me');

      // Per-game accuracy = score / (score + errorCount).
      expect(pre.games[0].accuracy, closeTo(8 / 10, 1e-9));
      expect(pre.games[1].accuracy, closeTo(5 / 10, 1e-9));

      // Config label mapping through loadHistory.
      expect(pre.games[0].configLabel, 'Legacy');
      expect(pre.games[1].configLabel, '3-round flow');

      // overallAccuracy = mean of per-game accuracy.
      expect(pre.overallAccuracy, closeTo((0.8 + 0.5) / 2, 1e-9));

      // Recommended module / summary = first non-null from results.
      expect(pre.recommendedModule, 'Emotions Module');
      expect(pre.overallSummary, 'Great progress!');

      // Skills aggregated from the run's result rows.
      expect(pre.skills, hasLength(1));
      expect(pre.skills.single.area, 'Communication');
      expect(pre.skills.single.label, 'Strength');

      // Practice sessions sorted endedAt DESC.
      expect(summary.practiceSessions, hasLength(2));
      expect(summary.practiceSessions[0].id, 'p-a');
      expect(summary.practiceSessions[1].id, 'p-b');

      // My Path completion, single record with correct fields.
      expect(summary.completedModules, hasLength(1));
      final module = summary.completedModules.single;
      expect(module.moduleId, 'my_path');
      expect(module.moduleName, 'My Path');
      expect(module.source, 'my_path');
      expect(module.gameCount, path.length);
      expect(module.level, 0);
      // completedAt = the last (latest endedAt) path-game practice session.
      expect(module.completedAt, DateTime(2026, 8, 3, 10));

      // No comparison because the post run is not completed.
      expect(summary.comparison, isNull);
    });

    test(
      'builds a comparison only from completed runs, latest by completedAt',
      () async {
        final olderPre = _run(
          id: 'run-pre-old',
          status: 'completed',
          startedAt: DateTime(2026, 8, 1),
          completedAt: DateTime(2026, 8, 2),
        );
        final latestPre = _run(
          id: 'run-pre-new',
          status: 'completed',
          startedAt: DateTime(2026, 8, 5),
          completedAt: DateTime(2026, 8, 6),
        );
        final post = _run(
          id: 'run-post',
          type: 'post',
          status: 'completed',
          startedAt: DateTime(2026, 8, 10),
          completedAt: DateTime(2026, 8, 11),
        );

        final summary = await ParentHistoryService(
          localDb: _FakeDb(
            runs: [olderPre, latestPre, post],
            results: [
              _result(
                id: 'res-old',
                assessmentRunId: 'run-pre-old',
                communicationLabel: 'Emerging',
              ),
              _result(
                id: 'res-new',
                assessmentRunId: 'run-pre-new',
                communicationLabel: 'Strength',
                playSkillsLabel: 'Emerging',
              ),
              _result(
                id: 'res-post',
                assessmentRunId: 'run-post',
                communicationLabel: 'Emerging',
              ),
            ],
            sessions: [
              _session(
                id: 'sg-old',
                assessmentRunId: 'run-pre-old',
                gameId: 'match_it',
                context: 'pre_assessment',
                score: 6,
                errorCount: 4,
                startedAt: DateTime(2026, 8, 1, 9),
              ),
              _session(
                id: 'sg-new',
                assessmentRunId: 'run-pre-new',
                gameId: 'match_it',
                context: 'pre_assessment',
                score: 9,
                errorCount: 1,
                startedAt: DateTime(2026, 8, 5, 9),
              ),
              _session(
                id: 'sg-post',
                assessmentRunId: 'run-post',
                gameId: 'match_it',
                context: 'post_assessment',
                score: 5,
                errorCount: 5,
                startedAt: DateTime(2026, 8, 10, 9),
              ),
            ],
          ),
        ).loadHistory(
          childId: 'child-1',
          path: const [],
          pathCompletedGameIds: const {},
        );

        final comparison = summary.comparison;
        expect(comparison, isNotNull);
        // The LATEST completed pre by completedAt wins.
        expect(comparison!.pre.run.id, 'run-pre-new');
        expect(comparison.post.run.id, 'run-post');

        expect(comparison.pre.overallAccuracy, closeTo(0.9, 1e-9));
        expect(comparison.post.overallAccuracy, closeTo(0.5, 1e-9));
        expect(comparison.overallDeltaPoints, closeTo(-40.0, 1e-9));

        // Area rows union; missing on one side -> null.
        expect(comparison.areas, hasLength(2));
        final communication = comparison.areas.firstWhere(
          (a) => a.area == 'Communication',
        );
        expect(communication.before, 'Strength');
        expect(communication.after, 'Emerging');
        final play = comparison.areas.firstWhere(
          (a) => a.area == 'Play Skills',
        );
        expect(play.before, 'Emerging');
        expect(play.after, isNull);
      },
    );

    test('produces no comparison when only a completed pre exists', () async {
      final pre = _run(
        id: 'run-pre',
        status: 'completed',
        startedAt: DateTime(2026, 8, 5),
        completedAt: DateTime(2026, 8, 6),
      );

      final summary = await ParentHistoryService(
        localDb: _FakeDb(
          runs: [pre],
          results: [
            _result(
              id: 'res-pre',
              assessmentRunId: 'run-pre',
              communicationLabel: 'Strength',
            ),
          ],
          sessions: [
            _session(
              id: 'sg-pre',
              assessmentRunId: 'run-pre',
              gameId: 'match_it',
              context: 'pre_assessment',
              score: 8,
              errorCount: 2,
              startedAt: DateTime(2026, 8, 5, 9),
            ),
          ],
        ),
      ).loadHistory(
        childId: 'child-1',
        path: const [],
        pathCompletedGameIds: const {},
      );

      expect(summary.comparison, isNull);
    });

    test(
      'leaves completedModules empty when the path is not fully completed',
      () async {
        final path = LearningPathService.buildPath(
          areaLevels: {'communication': _level(0)},
        );
        expect(path, isNotEmpty);

        // Only some games completed — the path is incomplete.
        final partial =
            path.take(path.length - 1).map((e) => e.game.id).toSet();

        final summary = await ParentHistoryService(
          localDb: _FakeDb(
            runs: [_run(id: 'run-pre', startedAt: DateTime(2026, 8, 5))],
            results: const [],
            sessions: const [],
          ),
        ).loadHistory(
          childId: 'child-1',
          path: path,
          pathCompletedGameIds: partial,
        );

        expect(summary.completedModules, isEmpty);
      },
    );

    test('maps practice vs ignored sessions correctly', () async {
      final pre = _run(
        id: 'run-pre',
        status: 'completed',
        startedAt: DateTime(2026, 8, 5),
      );

      await Future<void>.value();

      final summary = await ParentHistoryService(
        localDb: _FakeDb(
          runs: [pre],
          results: const [],
          sessions: [
            // Practice: belongs to practiceSessions, never a run's games.
            _session(
              id: 'p-1',
              gameId: 'match_it',
              context: 'practice',
              score: 10,
              errorCount: 0,
              startedAt: DateTime(2026, 8, 6, 9),
            ),
            // Null run id + non-practice context -> ignored entirely.
            _session(
              id: 'orphan-1',
              gameId: 'copy_me',
              context: 'pre_assessment',
              score: 8,
              errorCount: 2,
              startedAt: DateTime(2026, 8, 6, 10),
            ),
          ],
        ),
      ).loadHistory(
        childId: 'child-1',
        path: const [],
        pathCompletedGameIds: const {},
      );

      expect(summary.runs.single.games, isEmpty);
      expect(summary.practiceSessions, hasLength(1));
      expect(summary.practiceSessions.single.id, 'p-1');
      // The orphaned session appears nowhere.
      expect(summary.runs.every((h) => h.games.isEmpty), isTrue);
    });

    test('caps practice sessions at 20 newest first', () async {
      final sessions = <GameplaySession>[];
      for (var i = 0; i < 25; i++) {
        sessions.add(
          _session(
            id: 'p-$i',
            gameId: 'match_it',
            context: 'practice',
            score: 10,
            errorCount: 0,
            startedAt: DateTime(2026, 8, 1).add(Duration(hours: i * 2)),
          ),
        );
      }

      final summary = await ParentHistoryService(
        localDb: _FakeDb(runs: const [], results: const [], sessions: sessions),
      ).loadHistory(
        childId: 'child-1',
        path: const [],
        pathCompletedGameIds: const {},
      );

      expect(summary.practiceSessions, hasLength(20));
      // Newest first: the last-created session (largest endedAt) is first.
      expect(summary.practiceSessions.first.id, 'p-24');
    });

    test(
      'reports 0.0 accuracy when a session has no score and no errors',
      () async {
        final pre = _run(
          id: 'run-pre',
          status: 'completed',
          startedAt: DateTime(2026, 8, 5),
        );

        final summary = await ParentHistoryService(
          localDb: _FakeDb(
            runs: [pre],
            results: const [],
            sessions: [
              _session(
                id: 'sg-zero',
                assessmentRunId: 'run-pre',
                gameId: 'match_it',
                context: 'pre_assessment',
                score: 0,
                errorCount: 0,
                startedAt: DateTime(2026, 8, 5, 9),
              ),
            ],
          ),
        ).loadHistory(
          childId: 'child-1',
          path: const [],
          pathCompletedGameIds: const {},
        );

        final run = summary.runs.single;
        expect(run.games.single.accuracy, 0.0);
        expect(run.overallAccuracy, 0.0);
      },
    );
  });
}

class _FakeDb extends LocalDbService {
  _FakeDb({
    this.runs = const [],
    this.results = const [],
    this.sessions = const [],
  });

  final List<AssessmentRunRecord> runs;
  final List<AssessmentResult> results;
  final List<GameplaySession> sessions;

  @override
  Future<List<AssessmentRunRecord>> getAssessmentRuns({
    required String childId,
    bool includeDeleted = false,
  }) async => runs;

  @override
  Future<List<AssessmentResult>> getAssessmentResults({
    required String childId,
    String? type,
    bool includeDeleted = false,
  }) async => results;

  @override
  Future<List<GameplaySession>> getGameSessions({
    String? childId,
    String? context,
    bool includeDeleted = false,
  }) async => sessions;
}
