import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/services/assessment_completeness.dart';
import 'package:aumazing/services/assessment_service.dart';

/// In-memory stand-in for the SQLite-backed [AssessmentService].
///
/// [openAssessmentRun] is what the resume path reads: it stands for the
/// database, so a provider built fresh from it is an app restart — nothing
/// the previous provider held in memory comes back with it.
class _FakeGateway implements AssessmentGateway {
  /// The run and sessions the "database" holds for the child.
  OpenAssessmentRun? storedRun;

  final List<GameplaySession> written = [];
  final List<AssessmentResult> created = [];
  final List<String> completedRuns = [];
  final List<String> abandonedFor = [];
  final List<String> openRunLookups = [];

  /// The sessions each `createAssessmentResult` call was given — this is
  /// what finalization actually scored.
  final List<List<GameplaySession>> finalizedSessionBatches = [];

  int _runCounter = 0;

  @override
  Future<String> startAssessmentRun({
    required String childId,
    required String type,
  }) async => 'run-${++_runCounter}';

  @override
  Future<void> completeAssessmentRun(String runId) async =>
      completedRuns.add(runId);

  @override
  Future<int> abandonOpenRuns(String childId) async {
    abandonedFor.add(childId);
    final closed = storedRun == null ? 0 : 1;
    storedRun = null;
    return closed;
  }

  @override
  Future<OpenAssessmentRun?> openAssessmentRun(String childId) async {
    openRunLookups.add(childId);
    final run = storedRun;
    return run != null && run.childId == childId ? run : null;
  }

  @override
  Future<GameplaySession> recordSession({
    required String childId,
    required String gameId,
    required String context,
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required DateTime startedAt,
    String? assessmentRunId,
    GameSessionMetrics? analytics,
    bool bgMusicEnabled = true,
    bool hapticFeedbackEnabled = true,
    bool applySessionSensoryDefaults = true,
  }) async {
    final session = GameplaySession(
      id: 'session-${written.length + 1}',
      childId: childId,
      assessmentRunId: assessmentRunId,
      gameId: gameId,
      context: context,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      totalResponseTimeMs: totalResponseTimeMs,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 2)),
    );
    written.add(session);
    return session;
  }

  @override
  Future<AssessmentResult> createAssessmentResult({
    required String childId,
    required String type,
    required String gameId,
    required List<GameplaySession> sessions,
    String? assessmentRunId,
  }) async {
    finalizedSessionBatches.add(List.of(sessions));
    final result = AssessmentResult(
      id: 'result-${created.length + 1}',
      childId: childId,
      assessmentRunId: assessmentRunId,
      type: type,
      gameId: gameId,
      score: sessions.fold(0, (sum, s) => sum + s.score),
      totalItems: sessions.fold(0, (sum, s) => sum + s.totalItems),
      errorCount: sessions.fold(0, (sum, s) => sum + s.errorCount),
      avgResponseTimeMs: 1500,
      completedAt: DateTime(2026, 8, created.length + 1),
    );
    created.add(result);
    return result;
  }

  @override
  Map<String, dynamic> recommendModule(List<AssessmentResult> preResults) => {
    'module_id': 'module_basic',
    'module_name': 'Basic Skills',
    'starting_level': 1,
    'confidence': 0.5,
  };

  @override
  Map<String, dynamic> compareAssessments({
    required List<AssessmentResult> preResults,
    required List<AssessmentResult> postResults,
  }) =>
      preResults.isEmpty || postResults.isEmpty
          ? {'has_data': false}
          : {'has_data': true};
}

final _now = DateTime(2026, 8, 17, 10);

GameplaySession _storedSession(
  String gameId, {
  String runId = 'run-open',
  String childId = 'child-1',
  String context = 'pre_assessment',
  DateTime? startedAt,
}) {
  final start = startedAt ?? _now.subtract(const Duration(days: 1));
  return GameplaySession(
    id: 'stored-$gameId',
    childId: childId,
    assessmentRunId: runId,
    gameId: gameId,
    context: context,
    score: 7,
    totalItems: 10,
    errorCount: 3,
    totalResponseTimeMs: 12000,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 2)),
  );
}

/// A run left open after [played] activities, started [age] ago.
OpenAssessmentRun _openRun({
  List<String> played = const ['copy_me', 'do_what_i_say'],
  Duration age = const Duration(days: 1),
  String type = 'pre',
  String childId = 'child-1',
  String id = 'run-open',
}) => OpenAssessmentRun(
  id: id,
  childId: childId,
  type: type,
  startedAt: _now.subtract(age),
  sessions: [
    for (final gameId in played)
      _storedSession(
        gameId,
        runId: id,
        childId: childId,
        context: AssessmentProvider.expectedContextFor(type),
      ),
  ],
);

Future<GameplaySession?> _play(
  AssessmentProvider provider, {
  required String gameId,
  String childId = 'child-1',
  String context = 'pre_assessment',
  DateTime? startedAt,
}) => provider.recordGameSession(
  childId: childId,
  gameId: gameId,
  context: context,
  score: 8,
  totalItems: 10,
  errorCount: 2,
  totalResponseTimeMs: 12000,
  startedAt: startedAt ?? _now,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeGateway gateway;
  late AssessmentProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    gateway = _FakeGateway();
    provider = AssessmentProvider(assessmentService: gateway);
  });

  group('offering an interrupted run back (AUM-154)', () {
    test('a run left open within the window is offered', () async {
      gateway.storedRun = _openRun();

      final resumable = await provider.findResumableRun(
        childId: 'child-1',
        type: 'pre',
        now: _now,
      );

      expect(resumable, isNotNull);
      expect(resumable!.id, 'run-open');
      expect(resumable.sessions.map((s) => s.gameId), [
        'copy_me',
        'do_what_i_say',
      ]);
      expect(
        gateway.abandonedFor,
        isEmpty,
        reason: 'the run being offered must still be open to resume into',
      );
    });

    test('the offer says how far the child got', () async {
      gateway.storedRun = _openRun();
      final resumable = await provider.findResumableRun(
        childId: 'child-1',
        type: 'pre',
        now: _now,
      );

      // What the parent-facing prompt is built from.
      expect(AssessmentCompleteness.playedCount(resumable!.sessions), 2);
      expect(AssessmentCompleteness.missingGames(resumable.sessions), [
        'my_turn_your_turn',
        'match_it',
      ]);
    });

    test('a run older than a week is not offered, and is closed', () async {
      gateway.storedRun = _openRun(age: const Duration(days: 8));

      final resumable = await provider.findResumableRun(
        childId: 'child-1',
        type: 'pre',
        now: _now,
      );

      expect(resumable, isNull);
      expect(
        gateway.abandonedFor,
        ['child-1'],
        reason: 'stale open runs are closed so they cannot accumulate',
      );
    });

    test('a run at the edge of the window is still offered', () async {
      gateway.storedRun = _openRun(age: const Duration(days: 7));

      expect(
        await provider.findResumableRun(
          childId: 'child-1',
          type: 'pre',
          now: _now,
        ),
        isNotNull,
      );
    });

    test('nothing is offered when no run is open', () async {
      final resumable = await provider.findResumableRun(
        childId: 'child-1',
        type: 'pre',
        now: _now,
      );

      expect(resumable, isNull);
      expect(gateway.abandonedFor, isEmpty);
      // Behaviour is exactly what it was before: a normal fresh run.
      final runId = await provider.startAssessmentRun(
        childId: 'child-1',
        type: 'pre',
      );
      expect(runId, 'run-1');
      expect(provider.currentSessions, isEmpty);
    });

    test('an open pre run is not offered to the post-assessment', () async {
      gateway.storedRun = _openRun(type: 'pre');

      expect(
        await provider.findResumableRun(
          childId: 'child-1',
          type: 'post',
          now: _now,
        ),
        isNull,
      );
    });

    test('another child\'s open run is never offered', () async {
      gateway.storedRun = _openRun(childId: 'child-2');

      expect(
        await provider.findResumableRun(
          childId: 'child-1',
          type: 'pre',
          now: _now,
        ),
        isNull,
      );
    });

    test('a run that recorded no play is not worth an offer', () async {
      gateway.storedRun = _openRun(played: const []);

      expect(
        await provider.findResumableRun(
          childId: 'child-1',
          type: 'pre',
          now: _now,
        ),
        isNull,
      );
    });

    test('a lookup failure leaves the child able to start', () async {
      gateway.storedRun = _openRun();
      final failing = AssessmentProvider(assessmentService: _ThrowingGateway());

      expect(
        await failing.findResumableRun(
          childId: 'child-1',
          type: 'pre',
          now: _now,
        ),
        isNull,
      );
    });
  });

  group('continuing an interrupted run', () {
    test('the run is adopted, sessions and all, after a restart', () async {
      // The provider that played the first two games is gone — this one has
      // only the database behind it, exactly as after an app restart.
      gateway.storedRun = _openRun();
      final resumable = await provider.findResumableRun(
        childId: 'child-1',
        type: 'pre',
        now: _now,
      );
      provider.resumeAssessmentRun(resumable!);

      expect(provider.currentAssessmentRunId, 'run-open');
      expect(provider.hasActiveAssessmentRun, isTrue);
      expect(provider.runSessions().map((s) => s.gameId), [
        'copy_me',
        'do_what_i_say',
      ]);
      expect(
        gateway.abandonedFor,
        isEmpty,
        reason: 'resuming must not close the run it is resuming',
      );
    });

    test('the remaining activities finish the run, without replay', () async {
      gateway.storedRun = _openRun();
      final resumable = await provider.findResumableRun(
        childId: 'child-1',
        type: 'pre',
        now: _now,
      );
      provider.resumeAssessmentRun(resumable!);

      for (final gameId in const ['my_turn_your_turn', 'match_it']) {
        await _play(provider, gameId: gameId);
      }

      expect(await provider.finalizePreAssessment('child-1'), isTrue);
      expect(
        gateway.created.map((r) => r.gameId),
        containsAll(GameRegistry.assessmentGameIds),
      );
      expect(
        gateway.created.map((r) => r.assessmentRunId),
        everyElement('run-open'),
      );
      expect(gateway.completedRuns, ['run-open']);
      // Only the two activities that were actually left were played again.
      expect(gateway.written.map((s) => s.gameId), [
        'my_turn_your_turn',
        'match_it',
      ]);
      // The earlier games were scored from their stored sessions.
      final scored = gateway.finalizedSessionBatches.expand((b) => b);
      expect(scored.map((s) => s.id), contains('stored-copy_me'));
    });

    test('a game already played in the run is not recorded twice', () async {
      gateway.storedRun = _openRun();
      final resumable = await provider.findResumableRun(
        childId: 'child-1',
        type: 'pre',
        now: _now,
      );
      provider.resumeAssessmentRun(resumable!);

      // The same game instance reports completion again after the resume.
      await _play(
        provider,
        gameId: 'copy_me',
        startedAt: resumable.sessions.first.startedAt,
      );

      expect(gateway.written, isEmpty);
      expect(provider.runSessions(), hasLength(2));
    });

    test('a post run resumes into the post-assessment', () async {
      gateway.storedRun = _openRun(
        type: 'post',
        played: const ['copy_me', 'do_what_i_say', 'my_turn_your_turn'],
      );
      final resumable = await provider.findResumableRun(
        childId: 'child-1',
        type: 'post',
        now: _now,
      );
      provider.resumeAssessmentRun(resumable!);
      await _play(
        provider,
        gameId: 'match_it',
        context: 'post_assessment',
      );

      // No pre-assessment to compare against, but the run itself is complete
      // and scored — the completeness gate no longer refuses it.
      await provider.finalizePostAssessment('child-1');
      expect(
        gateway.created.map((r) => r.gameId),
        containsAll(GameRegistry.assessmentGameIds),
      );
      expect(gateway.completedRuns, ['run-open']);
    });
  });

  group('starting over instead', () {
    test('the old run is closed and a clean one begins', () async {
      gateway.storedRun = _openRun();
      final resumable = await provider.findResumableRun(
        childId: 'child-1',
        type: 'pre',
        now: _now,
      );
      expect(resumable, isNotNull);

      // The parent chose Start over: the ordinary path, untouched.
      final runId = await provider.startAssessmentRun(
        childId: 'child-1',
        type: 'pre',
      );

      expect(runId, 'run-1');
      expect(provider.currentAssessmentRunId, 'run-1');
      expect(gateway.abandonedFor, ['child-1']);
      expect(
        provider.currentSessions,
        isEmpty,
        reason: 'the abandoned run\'s play does not follow the new one',
      );
      expect(
        await provider.findResumableRun(
          childId: 'child-1',
          type: 'pre',
          now: _now,
        ),
        isNull,
        reason: 'the closed run is no longer resumable',
      );
    });

    test('starting over after a resume closes the resumed run', () async {
      gateway.storedRun = _openRun();
      final resumable = await provider.findResumableRun(
        childId: 'child-1',
        type: 'pre',
        now: _now,
      );
      provider.resumeAssessmentRun(resumable!);

      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');

      expect(provider.currentAssessmentRunId, 'run-1');
      expect(provider.runSessions(), isEmpty);
      expect(gateway.abandonedFor, ['child-1']);
    });
  });
}

/// A gateway whose database is unavailable.
class _ThrowingGateway implements AssessmentGateway {
  @override
  Future<OpenAssessmentRun?> openAssessmentRun(String childId) async =>
      throw StateError('no database');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
