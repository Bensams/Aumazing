import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/dev/developer_tools_service.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/services/assessment_service.dart';

/// In-memory stand-in for the SQLite/Supabase-backed [AssessmentService].
///
/// Mirrors the real service's derivations (telemetry from the analytics
/// object, item-weighted result aggregation, canonical comparison) so a
/// simulated run is scored here the same way it is on a device.
class _FakeGateway implements AssessmentGateway {
  final List<GameplaySession> written = [];
  final List<AssessmentResult> created = [];
  final List<String> startedRuns = [];
  final List<String> completedRuns = [];

  int _runCounter = 0;
  bool failRecord = false;
  bool failCreateResult = false;

  @override
  Future<String> startAssessmentRun({
    required String childId,
    required String type,
  }) async {
    final id = 'run-${++_runCounter}';
    startedRuns.add('$type:$id');
    return id;
  }

  @override
  Future<void> completeAssessmentRun(String runId) async =>
      completedRuns.add(runId);

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
      retryCount: analytics?.retryCount ?? 0,
      hintCount: analytics?.hintCount ?? 0,
      promptCount: analytics?.promptCount ?? 0,
      idleTimeSeconds: analytics?.idleTimeSeconds.toDouble() ?? 0.0,
      randomTouchCount: analytics?.randomTouchCount ?? 0,
      avgResponseTime: analytics?.avgResponseTime ?? 0.0,
      avgValidResponseTime: analytics?.avgValidResponseTime ?? 0.0,
      offTaskActionCount: analytics?.offTaskActionCount ?? 0,
      improvementScore: analytics?.improvementScore ?? 0.0,
      consistencyScore: analytics?.consistencyScore ?? 0.0,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 5)),
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
    if (failCreateResult) throw StateError('write failed');
    final totalItems = sessions.fold<int>(0, (sum, s) => sum + s.totalItems);
    final totalTime =
        sessions.fold<int>(0, (sum, s) => sum + s.totalResponseTimeMs);
    final result = AssessmentResult(
      id: 'result-${created.length + 1}',
      childId: childId,
      assessmentRunId: assessmentRunId,
      type: type,
      gameId: gameId,
      score: sessions.fold(0, (sum, s) => sum + s.score),
      totalItems: totalItems,
      errorCount: sessions.fold(0, (sum, s) => sum + s.errorCount),
      randomTouchCount: sessions.fold(0, (sum, s) => sum + s.randomTouchCount),
      avgResponseTimeMs: totalItems > 0 ? (totalTime / totalItems).round() : 0,
      completedAt: DateTime(2026, 8, 15, 12, created.length),
    );
    created.add(result);
    return result;
  }

  @override
  Map<String, dynamic> recommendModule(List<AssessmentResult> preResults) => {
        'module_id': 'module_foundation',
        'module_name': 'Foundation Skills',
        'starting_level': 2,
        'confidence': 0.6,
      };

  /// The canonical comparison, scored exactly like the real service.
  @override
  Map<String, dynamic> compareAssessments({
    required List<AssessmentResult> preResults,
    required List<AssessmentResult> postResults,
  }) {
    if (preResults.isEmpty || postResults.isEmpty) {
      return {'has_data': false};
    }
    final pre = AssessmentService.overallAccuracy(preResults);
    final post = AssessmentService.overallAccuracy(postResults);
    return {
      'has_data': true,
      'accuracy_improvement': post - pre,
      'pre_accuracy': pre,
      'post_accuracy': post,
      'response_time_improvement':
          AssessmentService.weightedAvgResponseTimeMs(preResults) -
              AssessmentService.weightedAvgResponseTimeMs(postResults),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeGateway gateway;
  late AssessmentProvider provider;
  late DeveloperToolsService service;

  // A fixed clock so every simulated timestamp is repeatable.
  DateTime clock() => DateTime(2026, 8, 15, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    gateway = _FakeGateway();
    provider = AssessmentProvider(assessmentService: gateway);
    service = DeveloperToolsService(clock: clock);
  });

  List<GameplaySession> sessionsWith(String context) =>
      gateway.written.where((s) => s.context == context).toList();

  group('pre-assessment simulation', () {
    test('creates four correctly scoped sessions', () async {
      await service.completePreAssessment(
          provider: provider, childId: 'child-1');

      final pre = sessionsWith('pre_assessment');
      expect(pre.map((s) => s.gameId), DeveloperToolsService.assessmentGameIds);
      expect(pre.every((s) => s.assessmentRunId == 'run-1'), isTrue);
      expect(pre.every((s) => s.childId == 'child-1'), isTrue);
      expect(
        pre.map((s) => s.startedAt).toSet(),
        hasLength(4),
        reason: 'distinct start times, so dedupe cannot collapse them',
      );
      expect(pre.every((s) => s.totalItems > 0 && s.totalResponseTimeMs > 0),
          isTrue);
      // The telemetry the rubric and the model read is really carried.
      expect(pre.every((s) => s.avgResponseTime > 0), isTrue);
      expect(gateway.written.where((s) => s.context != 'pre_assessment'),
          isEmpty);
    });

    test('runs the whole finalize → predict → profile → snapshot pipeline',
        () async {
      final result = await service.completePreAssessment(
          provider: provider, childId: 'child-1');

      // Finalization really happened: one result per game, run completed.
      expect(gateway.created.map((r) => r.gameId).toSet(),
          DeveloperToolsService.assessmentGameIds.toSet());
      expect(gateway.created.every((r) => r.type == 'pre'), isTrue);
      expect(gateway.completedRuns, ['run-1']);

      expect(provider.hasPreAssessment, isTrue);
      expect(provider.recommendation, isNotNull);
      expect(provider.supportProfile, isNotNull);
      expect(provider.rubricResult, isNotNull,
          reason: 'scored by the real rubric, not by invented labels');

      // The AI step ran and fell back legitimately (no model assets and no
      // reachable API in a test), producing usable area levels.
      expect(result.aiResponse, isNotNull);
      expect(result.aiResponse!.areaLevels, isNotEmpty);
      expect(provider.aiPrediction, isNotNull);

      // The run is frozen, and the returned values are the snapshot's.
      expect(provider.preSnapshot, isNotNull);
      expect(provider.preSnapshot!.assessmentRunId, 'run-1');
      expect(result.results, hasLength(4));
      expect(result.profile, provider.supportProfile);
    });

    test('produces a learning path the child can actually play', () async {
      await service.completePreAssessment(
          provider: provider, childId: 'child-1');

      expect(DeveloperToolsService.learningPath(provider), isNotEmpty);
      expect(provider.pathCompletedGameIds, isEmpty,
          reason: 'a new prediction restarts the path at step 1');
    });

    test('refuses to create data for a missing child', () async {
      await expectLater(
        service.completePreAssessment(provider: provider, childId: 'unknown'),
        throwsA(isA<DeveloperToolsException>()),
      );
      await expectLater(
        service.completePreAssessment(provider: provider, childId: ''),
        throwsA(isA<DeveloperToolsException>()),
      );
      expect(gateway.written, isEmpty);
      expect(gateway.startedRuns, isEmpty);
    });

    test('a failed session write aborts before finalization', () async {
      gateway.failRecord = true;

      await expectLater(
        service.completePreAssessment(provider: provider, childId: 'child-1'),
        throwsA(isA<DeveloperToolsException>()),
      );
      expect(gateway.created, isEmpty);
      expect(gateway.completedRuns, isEmpty);
      expect(provider.hasPreAssessment, isFalse);
      expect(provider.preSnapshot, isNull);
    });

    test('a failed finalization never reports success', () async {
      gateway.failCreateResult = true;

      await expectLater(
        service.completePreAssessment(provider: provider, childId: 'child-1'),
        throwsA(isA<DeveloperToolsException>()),
      );
      expect(provider.preSnapshot, isNull);
      expect(provider.supportProfile, isNull);
    });
  });

  group('post-assessment simulation', () {
    test('requires a pre-assessment baseline', () async {
      await expectLater(
        service.completePostAssessment(provider: provider, childId: 'child-1'),
        throwsA(isA<DeveloperToolsException>()),
      );
      expect(gateway.startedRuns, isEmpty,
          reason: 'no run is created without a baseline to compare against');
    });

    test('creates four correctly scoped post sessions', () async {
      await service.completePreAssessment(
          provider: provider, childId: 'child-1');
      await service.completePostAssessment(
          provider: provider, childId: 'child-1');

      final post = sessionsWith('post_assessment');
      expect(
          post.map((s) => s.gameId), DeveloperToolsService.assessmentGameIds);
      expect(post.every((s) => s.assessmentRunId == 'run-2'), isTrue);
      expect(post.map((s) => s.startedAt).toSet(), hasLength(4));
      expect(gateway.created.where((r) => r.type == 'post'), hasLength(4));
    });

    test('the comparison has real data and shows improvement', () async {
      await service.completePreAssessment(
          provider: provider, childId: 'child-1');
      final result = await service.completePostAssessment(
          provider: provider, childId: 'child-1');

      expect(result.improvement['has_data'], isTrue);
      expect(result.improvement['accuracy_improvement'], greaterThan(0),
          reason: 'the synthetic post run is deliberately the better one');
      expect(result.improvement['response_time_improvement'], greaterThan(0));
      expect(result.postAreaLevels, isNotEmpty);
    });

    test('the frozen pre-assessment snapshot survives intact', () async {
      final pre = await service.completePreAssessment(
          provider: provider, childId: 'child-1');
      final preLevels =
          Map.of(provider.preSnapshot!.prediction!.areaLevels);
      final preResultIds =
          provider.preSnapshot!.results.map((r) => r.id).toList();

      final post = await service.completePostAssessment(
          provider: provider, childId: 'child-1');

      expect(provider.preSnapshot!.assessmentRunId, 'run-1');
      expect(provider.preSnapshot!.prediction!.areaLevels, preLevels);
      expect(provider.preSnapshot!.results.map((r) => r.id), preResultIds);
      expect(provider.preSnapshot!.profile, pre.profile);
      // The hand-off is given the frozen baseline, not the freshly
      // overwritten "latest" prediction.
      expect(post.preAreaLevels, preLevels);
      expect(provider.postSnapshot!.assessmentRunId, 'run-2');
    });

    test('a failed post finalization never reports success', () async {
      await service.completePreAssessment(
          provider: provider, childId: 'child-1');
      gateway.failCreateResult = true;

      await expectLater(
        service.completePostAssessment(provider: provider, childId: 'child-1'),
        throwsA(isA<DeveloperToolsException>()),
      );
      expect(provider.postSnapshot, isNull);
      expect(provider.hasPostAssessment, isFalse);
    });
  });

  group('learning-path modules', () {
    test('completes only the next incomplete module', () async {
      await service.completePreAssessment(
          provider: provider, childId: 'child-1');
      final path = DeveloperToolsService.learningPath(provider);

      final done = await service.completeNextModule(
          provider: provider, childId: 'child-1');

      expect(done.gameId, path.first.game.id);
      expect(provider.pathCompletedGameIds, {path.first.game.id});
      expect(done.remaining, path.length - 1);
      // Recorded as practice, and therefore attached to no assessment run.
      final practice = sessionsWith('practice');
      expect(practice, hasLength(1));
      expect(practice.single.assessmentRunId, isNull);
      expect(practice.single.gameId, path.first.game.id);
    });

    test('repeated presses walk the path without duplicating progress',
        () async {
      await service.completePreAssessment(
          provider: provider, childId: 'child-1');
      final path = DeveloperToolsService.learningPath(provider);

      for (var i = 0; i < path.length; i++) {
        final done = await service.completeNextModule(
            provider: provider, childId: 'child-1');
        expect(done.gameId, path[i].game.id);
      }

      expect(provider.pathCompletedGameIds,
          path.map((e) => e.game.id).toSet());
      expect(sessionsWith('practice'), hasLength(path.length),
          reason: 'one session per module, never a repeat');
      expect(DeveloperToolsService.nextIncompleteModule(provider), isNull);

      // The path is finished — pressing again is refused rather than
      // silently re-completing the last module.
      await expectLater(
        service.completeNextModule(provider: provider, childId: 'child-1'),
        throwsA(isA<DeveloperToolsException>()),
      );
      expect(sessionsWith('practice'), hasLength(path.length));
    });

    test('is unavailable before there is a path', () async {
      await expectLater(
        service.completeNextModule(provider: provider, childId: 'child-1'),
        throwsA(isA<DeveloperToolsException>()),
      );
      expect(gateway.written, isEmpty);
    });

    test('practice play never contaminates an assessment run', () async {
      await service.completePreAssessment(
          provider: provider, childId: 'child-1');
      await service.completeNextModule(
          provider: provider, childId: 'child-1');
      await service.completePostAssessment(
          provider: provider, childId: 'child-1');

      final scored = gateway.created.where((r) => r.type == 'post');
      expect(scored.map((r) => r.gameId).toSet(),
          DeveloperToolsService.assessmentGameIds.toSet());
      expect(
        sessionsWith('practice').every((s) => s.assessmentRunId == null),
        isTrue,
      );
    });
  });
}
