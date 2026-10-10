import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/services/overall_gameplay_summary_service.dart';
import 'package:aumazing/services/rubric/rubric.dart';

GameplaySession _session(
  String id, {
  required String context,
  String gameId = 'trace_it',
  String? runId,
  int score = 8,
  int totalItems = 10,
  DateTime? at,
}) {
  final start = at ?? DateTime(2026, 9, 1, 9);
  return GameplaySession(
    id: id,
    childId: 'child-1',
    assessmentRunId: runId,
    gameId: gameId,
    context: context,
    score: score,
    totalItems: totalItems,
    errorCount: totalItems - score,
    totalResponseTimeMs: 10000,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 2)),
  );
}

AssessmentResult _result(
  String runId,
  String type, {
  String comm = 'Emerging',
}) => AssessmentResult(
  id: 'r-$runId',
  childId: 'child-1',
  assessmentRunId: runId,
  type: type,
  gameId: 'do_what_i_say',
  score: 5,
  totalItems: 10,
  errorCount: 5,
  avgResponseTimeMs: 1000,
  completedAt: DateTime(2026, 9, 1),
  communicationLabel: comm,
  playSkillsLabel: 'Strength',
);

GameplaySummaryInput _input({
  List<GameplaySession>? sessions,
  Map<String, PathAttemptRecord> attempts = const {},
}) => OverallGameplaySummaryService.assemble(
  runs: [
    (id: 'pre-1', type: 'pre', completedAt: DateTime(2026, 9, 1)),
    (id: 'post-1', type: 'post', completedAt: DateTime(2026, 9, 10)),
  ],
  results: [
    _result('pre-1', 'pre', comm: 'Needs Support'),
    _result('post-1', 'post', comm: 'Emerging'),
  ],
  sessions:
      sessions ??
      [
        _session('a', context: 'pre_assessment', runId: 'pre-1'),
        _session('b', context: 'recommended_module', score: 5),
        _session(
          'c',
          context: 'recommended_module',
          score: 9,
          at: DateTime(2026, 9, 2),
        ),
        _session('d', context: 'practice', gameId: 'match_it'),
        _session('e', context: 'post_assessment', runId: 'post-1'),
      ],
  pathGameIds: const ['trace_it', 'hintay'],
  pathAttempts: attempts,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('assemble', () {
    test('leaves free practice out', () {
      final input = _input();
      expect(input.recommendedPlays, 2);
      expect(input.pathGames.map((g) => g.gameId), isNot(contains('match_it')));
    });

    test('orders assessments into cycles, pre before post', () {
      final input = _input();
      expect(input.assessments.map((a) => a.label), [
        'Pre-assessment (cycle 1)',
        'Post-assessment (cycle 1)',
      ]);
      expect(input.assessments.first.areas['Communication'], 'Needs Support');
      expect(input.assessments.last.areas['Communication'], 'Emerging');
    });

    test('derives tries to Strength from recommended plays', () {
      final trace = _input().pathGames.firstWhere(
        (g) => g.gameId == 'trace_it',
      );
      expect(trace.reachedStrength, isTrue);
      expect(trace.tries, 2);
      expect(trace.retries, 1);

      final hintay = _input().pathGames.firstWhere((g) => g.gameId == 'hintay');
      expect(hintay.tries, 0);
      expect(hintay.reachedStrength, isFalse);
    });

    test('the Strength gate\'s own count wins over the derived one', () {
      final input = _input(
        attempts: {
          'trace_it': const PathAttemptRecord(
            gameId: 'trace_it',
            attempts: 5,
            lastLabel: 'Strength',
            attemptsToStrength: 4,
          ),
        },
      );
      expect(input.pathGames.first.tries, 4);
    });

    test('a practice-only change leaves the fingerprint alone', () {
      final base = _input();
      final withPractice = _input(
        sessions: [
          _session('a', context: 'pre_assessment', runId: 'pre-1'),
          _session('b', context: 'recommended_module', score: 5),
          _session(
            'c',
            context: 'recommended_module',
            score: 9,
            at: DateTime(2026, 9, 2),
          ),
          _session('d', context: 'practice', gameId: 'match_it'),
          _session('x', context: 'practice', gameId: 'match_it'),
          _session('e', context: 'post_assessment', runId: 'post-1'),
        ],
      );
      expect(withPractice.fingerprint, base.fingerprint);
    });
  });

  group('summarize', () {
    test(
      'reuses the saved Gemini summary while no new record arrives',
      () async {
        var calls = 0;
        final service = OverallGameplaySummaryService(
          remote: (_) async {
            calls++;
            return {
              'summary': 'Your child is growing.',
              'questions': ['What next?'],
            };
          },
        );
        final input = _input();

        final first = await service.summarize(childId: 'child-1', input: input);
        expect(first!.isAi, isTrue);
        expect(first.fromCache, isFalse);

        final second = await service.summarize(
          childId: 'child-1',
          input: input,
        );
        expect(calls, 1);
        expect(second!.fromCache, isTrue);
        expect(second.summary, 'Your child is growing.');
        expect(second.questions, ['What next?']);
      },
    );

    test('a Groq reply is labelled and cached as Groq', () async {
      var calls = 0;
      final service = OverallGameplaySummaryService(
        remote: (_) async {
          calls++;
          return {
            'summary': 'Written by the fallback.',
            'questions': ['Q?'],
            'provider': 'groq',
          };
        },
      );
      final input = _input();

      final first = await service.summarize(childId: 'child-1', input: input);
      expect(first!.source, GameplaySummarySource.groq);
      expect(first.isAi, isTrue);

      final saved = await service.summarize(childId: 'child-1', input: input);
      expect(calls, 1);
      expect(saved!.fromCache, isTrue);
      expect(saved.source, GameplaySummarySource.groq);
    });

    test('a new game record asks Gemini again', () async {
      var calls = 0;
      final service = OverallGameplaySummaryService(
        remote: (_) async {
          calls++;
          return {'summary': 'Summary $calls', 'questions': <String>[]};
        },
      );
      await service.summarize(childId: 'child-1', input: _input());
      final updated = await service.summarize(
        childId: 'child-1',
        input: _input(
          sessions: [
            _session('a', context: 'pre_assessment', runId: 'pre-1'),
            _session('n', context: 'recommended_module', gameId: 'hintay'),
          ],
        ),
      );
      expect(calls, 2);
      expect(updated!.summary, 'Summary 2');
      // Gemini sent no questions, so the on-device ones fill in.
      expect(updated.questions, isNotEmpty);
    });

    test('falls back to the on-device summary and does not save it', () async {
      var calls = 0;
      final service = OverallGameplaySummaryService(
        remote: (_) async {
          calls++;
          throw Exception('offline');
        },
      );
      final input = _input();

      final summary = await service.summarize(childId: 'child-1', input: input);
      expect(summary!.source, GameplaySummarySource.onDevice);
      expect(summary.summary, isNotEmpty);
      expect(summary.questions, isNotEmpty);

      await service.summarize(childId: 'child-1', input: input);
      expect(calls, 2, reason: 'an on-device summary is never cached');
    });

    test('nothing to summarize yields null without calling Gemini', () async {
      var calls = 0;
      final service = OverallGameplaySummaryService(
        remote: (_) async {
          calls++;
          return null;
        },
      );
      final empty = OverallGameplaySummaryService.assemble(
        runs: const [],
        results: const [],
        sessions: [_session('p', context: 'practice')],
      );
      expect(await service.summarize(childId: 'child-1', input: empty), isNull);
      expect(calls, 0);
    });
  });

  group('on-device summarizer', () {
    test('narrates progress and suggests therapist questions', () {
      final input = _input(
        attempts: {
          'trace_it': const PathAttemptRecord(
            gameId: 'trace_it',
            attempts: 3,
            lastLabel: 'Strength',
            attemptsToStrength: 3,
          ),
        },
      );
      final summary = OverallGameplaySummaryService.buildFallback(input);

      expect(summary.summary, contains('communication moved up a level'));
      expect(summary.summary, contains('Trace It took 3 tries'));
      expect(summary.questions.any((q) => q.contains('communication')), isTrue);
      expect(summary.questions.length, inInclusiveRange(3, 5));
    });
  });
}
