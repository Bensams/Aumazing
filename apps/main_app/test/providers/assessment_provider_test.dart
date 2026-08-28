import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/model/ai_assessment_response.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/services/assessment_service.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/services/entitlement_service.dart';

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

GameplaySession _assessmentSession(String runId, {String type = 'post'}) {
  final now = DateTime(2026, 8, 1);
  return GameplaySession(
    id: 'session-$type',
    childId: 'child-1',
    assessmentRunId: runId,
    gameId: 'match_it',
    context: '${type}_assessment',
    score: 5,
    totalItems: 10,
    errorCount: 1,
    totalResponseTimeMs: 1200,
    startedAt: now,
    endedAt: now.add(const Duration(minutes: 1)),
  );
}


const _postPrediction = AiAssessmentResponse(
  predictedProfile: 'post-profile',
  confidence: 0.9,
  summary: 'post summary',
  supportLevel: 'moderate',
  recommendedModules: ['post-module'],
);

class _GateAssessmentProvider extends AssessmentProvider {
  _GateAssessmentProvider({required this.hasPost});

  final bool hasPost;

  @override
  bool get hasPostAssessment => hasPost;
}

class _PredictingAssessmentProvider extends AssessmentProvider {
  _PredictingAssessmentProvider({required super.predictionGenerator});

  bool postComplete = false;

  @override
  bool get hasPostAssessment => postComplete;
}

void main() {
  group('AssessmentProvider.latestPerGame (retake replaces, never stacks)', () {
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
      expect(latest.firstWhere((r) => r.gameId == 'match_it').score, 9);
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

  group('nextCycleLocked', () {
    setUp(() {
      EntitlementService.instance.debugSetRealPremium(false);
    });

    tearDown(() {
      EntitlementService.instance.debugSetRealPremium(false);
    });

    test('keeps the first Free assessment cycle available', () {
      final provider = _GateAssessmentProvider(hasPost: false);

      expect(provider.nextCycleLocked, isFalse);
    });


    test('locks a repeat cycle for Free users after a post-assessment', () {
      final provider = _GateAssessmentProvider(hasPost: true);

      expect(provider.nextCycleLocked, isTrue);
    });

    test('keeps repeat cycles available to Premium users', () {
      EntitlementService.instance.debugSetRealPremium(true);
      final provider = _GateAssessmentProvider(hasPost: true);

      expect(provider.nextCycleLocked, isFalse);
    });
  });
  group('post prediction entitlement activation', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      EntitlementService.instance.debugSetRealPremium(false);
    });

    tearDown(() {
      EntitlementService.instance.debugSetRealPremium(false);
    });

    test('free repeat post does not activate prediction', () async {
      final provider = _PredictingAssessmentProvider(
        predictionGenerator: ({required childId, required sessions}) async =>
            _postPrediction,
      )..postComplete = true;
      provider.resumeAssessmentRun(
        OpenAssessmentRun(
          id: 'post-run',
          childId: 'child-1',
          type: 'post',
          startedAt: DateTime(2026, 8, 1),
          sessions: [_assessmentSession('post-run')],
        ),
      );

      final result = await provider.predictWithAI('child-1', assessmentType: 'post');

      expect(result, same(_postPrediction));
      expect(provider.aiPrediction, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ai_prediction_child-1'), isNull);
    });

    test('Premium repeat post activates prediction', () async {
      EntitlementService.instance.debugSetRealPremium(true);
      final provider = _PredictingAssessmentProvider(
        predictionGenerator: ({required childId, required sessions}) async =>
            _postPrediction,
      )..postComplete = true;
      provider.resumeAssessmentRun(
        OpenAssessmentRun(
          id: 'post-run',
          childId: 'child-1',
          type: 'post',
          startedAt: DateTime(2026, 8, 1),
          sessions: [_assessmentSession('post-run')],
        ),
      );

      final result = await provider.predictWithAI('child-1', assessmentType: 'post');

      expect(result, same(_postPrediction));
      expect(provider.aiPrediction, same(_postPrediction));
    });
  });

  group('run snapshots', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      EntitlementService.instance.debugSetRealPremium(true);
    });

    tearDown(() {
      EntitlementService.instance.debugSetRealPremium(false);
    });

    test('explicit null prediction is preserved instead of reusing latest', () async {
      final provider = _PredictingAssessmentProvider(
        predictionGenerator: ({required childId, required sessions}) async =>
            _postPrediction,
      );
      provider.resumeAssessmentRun(
        OpenAssessmentRun(
          id: 'pre-run',
          childId: 'child-1',
          type: 'pre',
          startedAt: DateTime(2026, 8, 1),
          sessions: [_assessmentSession('pre-run', type: 'pre')],
        ),
      );

      await provider.predictWithAI('child-1', assessmentType: 'pre');
      final omittedPredictionSnapshot = await provider.captureRunSnapshot(
        'child-1',
        assessmentType: 'pre',
      );
      final explicitNullSnapshot = await provider.captureRunSnapshot(
        'child-1',
        assessmentType: 'post',
        prediction: null,
      );

      expect(omittedPredictionSnapshot.prediction, same(_postPrediction));
      expect(explicitNullSnapshot.prediction, isNull);
      expect(provider.postSnapshot!.prediction, isNull);
      final prefs = await SharedPreferences.getInstance();
      final persisted = jsonDecode(
        prefs.getString('assessment_snapshot_post_child-1')!,
      ) as Map<String, dynamic>;
      expect(persisted['prediction'], isNull);
    });
  });

  group('finalized support profile', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('explicit null prediction builds a rubric-only profile', () async {
      final provider = _PredictingAssessmentProvider(
        predictionGenerator: ({required childId, required sessions}) async =>
            _postPrediction,
      );
      provider.resumeAssessmentRun(
        OpenAssessmentRun(
          id: 'pre-run',
          childId: 'child-1',
          type: 'pre',
          startedAt: DateTime(2026, 8, 1),
          sessions: [_assessmentSession('pre-run', type: 'pre')],
        ),
      );
      await provider.predictWithAI('child-1', assessmentType: 'pre');

      final profile = await provider.finalizeSupportProfile(
        'child-1',
        aiResponse: null,
      );

      expect(profile.recommendedDifficulty, 'beginner');
      expect(profile.promptRepetition, 3);
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
