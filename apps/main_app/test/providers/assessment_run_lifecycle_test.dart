import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/model/ai_assessment_response.dart';
import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/services/assessment_service.dart';
import 'package:aumazing/services/rubric/rubric_result.dart';

/// In-memory stand-in for the SQLite/Supabase-backed [AssessmentService].
class _FakeGateway implements AssessmentGateway {
  final List<GameplaySession> written = [];
  final List<AssessmentResult> created = [];
  final List<String> completedRuns = [];

  /// The sessions each `createAssessmentResult` call was given — this is
  /// what finalization actually scored.
  final List<List<GameplaySession>> finalizedSessionBatches = [];

  int _runCounter = 0;
  bool failStart = false;
  bool failRecord = false;
  bool failCreateResult = false;

  @override
  Future<String> startAssessmentRun({
    required String childId,
    required String type,
  }) async {
    if (failStart) throw StateError('no database');
    return 'run-${++_runCounter}';
  }

  @override
  Future<void> completeAssessmentRun(String runId) async {
    completedRuns.add(runId);
  }

  /// Children whose open runs were closed, in order.
  final List<String> abandonedFor = [];

  /// How many open runs the next [abandonOpenRuns] call should report.
  int openRunsToClose = 0;
  bool failAbandon = false;

  @override
  Future<int> abandonOpenRuns(String childId) async {
    if (failAbandon) throw StateError('no database');
    abandonedFor.add(childId);
    final closed = openRunsToClose;
    openRunsToClose = 0;
    return closed;
  }

  /// The run the child has left open, if the test set one up.
  OpenAssessmentRun? openRun;

  @override
  Future<OpenAssessmentRun?> openAssessmentRun(String childId) async =>
      openRun?.childId == childId ? openRun : null;

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
    String? configurationVersionOverride,
    bool bgMusicEnabled = true,
    bool hapticFeedbackEnabled = true,
    bool applySessionSensoryDefaults = true,
  }) async {
    if (failRecord) throw StateError('disk full');
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
    RubricResult? rubric,
  }) async {
    if (failCreateResult) throw StateError('write failed');
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
  Future<void> saveModuleRecommendation({
    required String childId,
    required String assessmentRunId,
    required String moduleId,
    required String moduleName,
    required int startingLevel,
    double? confidence,
    String? rationale,
  }) async {}

  @override
  Future<void> saveAssessmentComparison({
    required String childId,
    required String preAssessmentId,
    required String postAssessmentId,
    double? accuracyImprovement,
    int? responseTimeImprovementMs,
    double? overallImprovementPercent,
    String? summary,
  }) async {}

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
  }) {
    if (preResults.isEmpty || postResults.isEmpty) {
      return {'has_data': false};
    }
    return {
      'has_data': true,
      'pre_accuracy': AssessmentService.overallAccuracy(preResults),
      'post_accuracy': AssessmentService.overallAccuracy(postResults),
    };
  }
}

Future<GameplaySession?> _play(
  AssessmentProvider provider, {
  required String gameId,
  String childId = 'child-1',
  String context = 'pre_assessment',
  DateTime? startedAt,
  int score = 8,
  int totalItems = 10,
  int errorCount = 2,
}) => provider.recordGameSession(
  childId: childId,
  gameId: gameId,
  context: context,
  score: score,
  totalItems: totalItems,
  errorCount: errorCount,
  totalResponseTimeMs: 12000,
  startedAt: startedAt ?? DateTime(2026, 8, 1, 9),
);

/// Plays every assessment activity, which is what a run now needs before it
/// can be scored (AUM-154). Tests whose subject is snapshots or session
/// contamination use this, so the completeness gate is not what they end up
/// measuring.
Future<void> _playFullRun(
  AssessmentProvider provider, {
  String childId = 'child-1',
  String context = 'pre_assessment',
  DateTime? startedAt,
}) async {
  final start = startedAt ?? DateTime(2026, 8, 1, 9);
  final games = GameRegistry.assessmentGameIds;
  for (var i = 0; i < games.length; i++) {
    await _play(
      provider,
      gameId: games[i],
      childId: childId,
      context: context,
      // Distinct start times so each game gets its own dedupe key.
      startedAt: start.add(Duration(minutes: i)),
    );
  }
}

AiAssessmentResponse _prediction(int level) => AiAssessmentResponse(
  predictedProfile: 'mixed_support',
  confidence: 0.7,
  summary: 'summary-$level',
  supportLevel: 'moderate',
  recommendedModules: const [],
  moduleDetails: const [],
  skillAreas: const ['communication'],
  areaLevels: {
    'communication': AreaLevel(
      level: 'emerging',
      levelInt: level,
      levelName: 'level-$level',
      confidence: 0.7,
    ),
  },
  onDevice: true,
);

const _profile = SupportProfile(
  communication: 'good',
  socialInteraction: 'emerging',
  playSkills: 'strong',
  attention: 'moderate',
  sensoryNotes: ['Prefers Quiet Play'],
  recommendedDifficulty: 'intermediate',
  recommendedPromptStyle: 'combined',
  recommendedSessionMinutes: 5,
  promptRepetition: 2,
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

  group('closing runs the child walked away from (AUM-154)', () {
    test('starting a run closes anything left open first', () async {
      gateway.openRunsToClose = 1;

      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');

      expect(gateway.abandonedFor, ['child-1']);
    });

    test('an abandoned run is closed before the new one is created', () async {
      // A run is started and walked away from after one game…
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      await _play(provider, gameId: 'copy_me');

      // …and the parent later starts again.
      gateway.openRunsToClose = 1;
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');

      expect(gateway.abandonedFor, ['child-1', 'child-1']);
      // The new run is clean — the abandoned session did not follow it.
      expect(provider.currentSessions, isEmpty);
    });

    test('only the run owner\'s open runs are closed', () async {
      await provider.startAssessmentRun(childId: 'child-2', type: 'pre');

      expect(gateway.abandonedFor, ['child-2']);
    });

    test('a bookkeeping failure never blocks the child starting', () async {
      gateway.failAbandon = true;

      // The stale status is a records problem; refusing the assessment
      // over it would punish the child for it.
      final runId = await provider.startAssessmentRun(
        childId: 'child-1',
        type: 'pre',
      );

      expect(runId, 'run-1');
      expect(provider.currentAssessmentRunId, 'run-1');
    });
  });

  group('session contamination', () {
    test('practice play is excluded from a post-assessment', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'post');
      await _playFullRun(provider, context: 'post_assessment');
      // The child wanders off and plays a practice game mid-run.
      await _play(
        provider,
        gameId: 'copy_me',
        context: 'practice',
        startedAt: DateTime(2026, 8, 1, 14),
      );

      final comparison = await provider.finalizePostAssessment('child-1');

      // The practice session is stored, but unattached to the run…
      final practice = gateway.written.firstWhere(
        (s) => s.context == 'practice',
      );
      expect(practice.assessmentRunId, isNull);
      // …and never scored: only the run's own games produce results.
      expect(
        gateway.created.map((r) => r.gameId),
        containsAll(GameRegistry.assessmentGameIds),
      );
      expect(
        gateway.finalizedSessionBatches
            .expand((batch) => batch)
            .every((s) => s.context == 'post_assessment'),
        isTrue,
      );
      expect(
        comparison['has_data'],
        isFalse,
        reason: 'no pre-assessment to compare against yet',
      );
    });

    test('a new run excludes an abandoned run\'s sessions', () async {
      // A pre-assessment is started and abandoned after one game.
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      await _play(provider, gameId: 'copy_me');
      expect(provider.currentSessions, hasLength(1));

      // The parent later starts a post-assessment.
      await provider.startAssessmentRun(childId: 'child-1', type: 'post');
      expect(
        provider.currentSessions,
        isEmpty,
        reason: 'the new run starts from clean state',
      );

      await _playFullRun(
        provider,
        context: 'post_assessment',
        startedAt: DateTime(2026, 8, 2, 9),
      );

      await provider.finalizePostAssessment('child-1');

      // Only the new run's games are scored — the abandoned run's session
      // contributes nothing, and every result belongs to run-2.
      expect(
        gateway.created.map((r) => r.gameId),
        containsAll(GameRegistry.assessmentGameIds),
      );
      expect(
        gateway.created.map((r) => r.assessmentRunId),
        everyElement('run-2'),
      );
    });

    test('sessionsForRun keeps only the matching run, child and context', () {
      GameplaySession session(
        String id,
        String? runId,
        String childId,
        String context,
      ) => GameplaySession(
        id: id,
        childId: childId,
        assessmentRunId: runId,
        gameId: 'copy_me',
        context: context,
        score: 1,
        totalItems: 1,
        errorCount: 0,
        totalResponseTimeMs: 100,
        startedAt: DateTime(2026),
        endedAt: DateTime(2026),
      );

      final kept = AssessmentProvider.sessionsForRun(
        [
          session('keep', 'run-1', 'child-1', 'pre_assessment'),
          session('other-run', 'run-0', 'child-1', 'pre_assessment'),
          session('no-run', null, 'child-1', 'pre_assessment'),
          session('other-child', 'run-1', 'child-2', 'pre_assessment'),
          session('practice', 'run-1', 'child-1', 'practice'),
          session('post', 'run-1', 'child-1', 'post_assessment'),
        ],
        runId: 'run-1',
        childId: 'child-1',
        expectedContext: 'pre_assessment',
      );

      expect(kept.map((s) => s.id), ['keep']);
    });
  });

  group('run initialization', () {
    test('sessions recorded before a run exists are not collected', () async {
      // The old flow let the countdown start while the run was still being
      // created, so a fast first game landed here.
      await _play(provider, gameId: 'copy_me');

      expect(gateway.written.single.assessmentRunId, isNull);
      expect(provider.currentSessions, isEmpty);
      expect(provider.hasActiveAssessmentRun, isFalse);

      expect(await provider.finalizePreAssessment('child-1'), isFalse);
      expect(provider.lastFinalizationError, isNotNull);
      expect(gateway.created, isEmpty);
    });

    test('a failed run creation leaves no active run to play into', () async {
      gateway.failStart = true;

      await expectLater(
        provider.startAssessmentRun(childId: 'child-1', type: 'pre'),
        throwsA(isA<StateError>()),
      );
      expect(provider.hasActiveAssessmentRun, isFalse);
      expect(provider.currentAssessmentRunId, isNull);

      // Retrying after the transient failure clears succeeds.
      gateway.failStart = false;
      final runId = await provider.startAssessmentRun(
        childId: 'child-1',
        type: 'pre',
      );
      expect(runId, isNotEmpty);
      expect(provider.currentAssessmentRunId, runId);
    });

    test('the run id is available before any session is written', () async {
      final future = provider.startAssessmentRun(
        childId: 'child-1',
        type: 'pre',
      );
      expect(
        provider.currentAssessmentRunId,
        isNull,
        reason: 'not usable until the creation completes',
      );
      final runId = await future;

      await _play(provider, gameId: 'copy_me');
      expect(gateway.written.single.assessmentRunId, runId);
    });
  });

  group('duplicate completion callbacks', () {
    test('a repeated callback for the same game writes one session', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      final startedAt = DateTime(2026, 8, 1, 9);

      final first = await _play(
        provider,
        gameId: 'copy_me',
        startedAt: startedAt,
      );
      final second = await _play(
        provider,
        gameId: 'copy_me',
        startedAt: startedAt,
      );

      expect(gateway.written, hasLength(1));
      expect(provider.currentSessions, hasLength(1));
      expect(second?.id, first?.id);
    });

    test('a genuine replay of the same game is still recorded', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      await _play(
        provider,
        gameId: 'copy_me',
        startedAt: DateTime(2026, 8, 1, 9),
      );
      await _play(
        provider,
        gameId: 'copy_me',
        startedAt: DateTime(2026, 8, 1, 9, 30),
      );

      expect(gateway.written, hasLength(2));
    });
  });

  group('failed writes never look like success', () {
    test('a failed session write is surfaced and can be retried', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      gateway.failRecord = true;

      await expectLater(
        _play(provider, gameId: 'copy_me'),
        throwsA(isA<StateError>()),
      );
      expect(provider.currentSessions, isEmpty);

      // The dedupe key must not have swallowed the retry.
      gateway.failRecord = false;
      await _play(provider, gameId: 'copy_me');
      expect(gateway.written, hasLength(1));
      expect(provider.currentSessions, hasLength(1));
    });

    test('a failed finalization reports failure instead of a result', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      await _play(provider, gameId: 'copy_me');
      gateway.failCreateResult = true;

      expect(await provider.finalizePreAssessment('child-1'), isFalse);
      expect(provider.lastFinalizationError, isNotNull);
      expect(
        gateway.completedRuns,
        isEmpty,
        reason: 'a run that could not be saved is not marked completed',
      );
    });

    test('a failed post finalization reports no data', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'post');
      await _play(provider, gameId: 'copy_me', context: 'post_assessment');
      gateway.failCreateResult = true;

      final comparison = await provider.finalizePostAssessment('child-1');
      expect(comparison['has_data'], isFalse);
      expect(provider.lastFinalizationError, isNotNull);
    });
  });

  group('empty and incomplete runs', () {
    test('finalizing a run with no gameplay is safe', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');

      expect(await provider.finalizePreAssessment('child-1'), isFalse);
      expect(gateway.created, isEmpty);
      expect(gateway.completedRuns, isEmpty);
      expect(provider.lastFinalizationError, isNotNull);
    });

    // Was: "a partial run finalizes only the games that were played" — it
    // pinned the behaviour AUM-154 exists to stop. One game out of four
    // used to produce a full profile and a recommendation, with the three
    // unplayed areas scored on no evidence at all.
    test('a partial run is not scored', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      await _play(provider, gameId: 'copy_me');

      expect(await provider.finalizePreAssessment('child-1'), isFalse);
      // Nothing was written and no recommendation was invented.
      expect(gateway.created, isEmpty);
      expect(gateway.completedRuns, isEmpty);
      expect(provider.hasPreAssessment, isFalse);
      expect(provider.recommendation, isNull);
    });

    test('a partial run explains what is left rather than failing', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      await _play(provider, gameId: 'copy_me');
      await provider.finalizePreAssessment('child-1');

      final message = provider.lastFinalizationError!;
      expect(message, contains('1 of 4'));
      expect(message.toLowerCase(), isNot(contains('error')));
    });

    test('the run is scored once the last activity is played', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      await _playFullRun(provider);

      expect(await provider.finalizePreAssessment('child-1'), isTrue);
      expect(
        gateway.created.map((r) => r.gameId),
        containsAll(GameRegistry.assessmentGameIds),
      );
      expect(gateway.completedRuns, ['run-1']);
    });

    test('sessions from a partial run survive so it can be resumed', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      await _play(provider, gameId: 'copy_me');
      expect(await provider.finalizePreAssessment('child-1'), isFalse);

      // The child comes back and finishes the remaining activities in the
      // same run — the first game is not replayed.
      for (final gameId in GameRegistry.assessmentGameIds.skip(1)) {
        await _play(
          provider,
          gameId: gameId,
          startedAt: DateTime(2026, 8, 1, 10),
        );
      }

      expect(await provider.finalizePreAssessment('child-1'), isTrue);
      expect(
        gateway.created.map((r) => r.gameId),
        containsAll(GameRegistry.assessmentGameIds),
      );
    });
  });

  group('pre and post snapshots stay separate', () {
    test('a post run cannot rewrite the finalized pre snapshot', () async {
      // Pre-assessment.
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      await _playFullRun(provider);
      expect(await provider.finalizePreAssessment('child-1'), isTrue);
      final preSnapshot = await provider.captureRunSnapshot(
        'child-1',
        assessmentType: 'pre',
        prediction: _prediction(0),
        profile: _profile,
      );

      // Post-assessment, with a different prediction.
      await provider.startAssessmentRun(childId: 'child-1', type: 'post');
      await _playFullRun(
        provider,
        context: 'post_assessment',
        startedAt: DateTime(2026, 9, 1, 9),
      );
      await provider.finalizePostAssessment('child-1');
      final postSnapshot = await provider.captureRunSnapshot(
        'child-1',
        assessmentType: 'post',
        prediction: _prediction(2),
      );

      expect(preSnapshot.assessmentType, 'pre');
      expect(preSnapshot.assessmentRunId, 'run-1');
      expect(preSnapshot.prediction!.areaLevels['communication']!.levelInt, 0);
      expect(preSnapshot.profile, _profile);

      expect(postSnapshot.assessmentType, 'post');
      expect(postSnapshot.assessmentRunId, 'run-2');
      expect(postSnapshot.prediction!.areaLevels['communication']!.levelInt, 2);

      // The stored pre snapshot is untouched by the later run.
      expect(provider.preSnapshot!.assessmentRunId, 'run-1');
      expect(
        provider.preSnapshot!.prediction!.areaLevels['communication']!.levelInt,
        0,
      );
      expect(
        provider.preSnapshot!.results.map((r) => r.type),
        everyElement('pre'),
      );
      expect(
        provider.postSnapshot!.results.map((r) => r.type),
        everyElement('post'),
      );
    });

    test('snapshots survive a reload', () async {
      await provider.startAssessmentRun(childId: 'child-1', type: 'pre');
      await _play(provider, gameId: 'copy_me');
      await provider.finalizePreAssessment('child-1');
      await provider.captureRunSnapshot(
        'child-1',
        assessmentType: 'pre',
        prediction: _prediction(1),
        profile: _profile,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('assessment_snapshot_pre_child-1'), isNotNull);

      final restored = AssessmentProvider(assessmentService: _FakeGateway());
      await restored.loadAssessments('child-1');
      // No local DB in this test, so results come back empty; what matters
      // is that the frozen snapshot is readable again.
      expect(restored.preSnapshot, isNotNull);
      expect(restored.preSnapshot!.assessmentRunId, 'run-1');
      expect(
        restored.preSnapshot!.prediction!.areaLevels['communication']!.levelInt,
        1,
      );
      expect(
        restored.preSnapshot!.profile!.recommendedDifficulty,
        'intermediate',
      );
    });

    test('retaking the pre-assessment invalidates the post snapshot', () async {
      await provider.captureRunSnapshot(
        'child-1',
        assessmentType: 'post',
        prediction: _prediction(2),
      );
      expect(provider.postSnapshot, isNotNull);

      await provider.captureRunSnapshot(
        'child-1',
        assessmentType: 'pre',
        prediction: _prediction(0),
      );

      expect(provider.postSnapshot, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('assessment_snapshot_post_child-1'), isNull);
    });
  });
}
