import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/pre_assessment/assessment_dashboard_screen.dart';
import 'package:aumazing/features/post_assessment/post_assessment_handoff_screen.dart';
import 'package:aumazing/features/post_assessment/post_assessment_progress_screen.dart';
import 'package:aumazing/features/post_assessment/post_assessment_result_screen.dart';
import 'package:aumazing/model/ai_assessment_response.dart';
import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/assessment_run_snapshot.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/module_recommendation.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/services/assessment_summary_service.dart';
import 'package:aumazing/widgets/assessment_handoff.dart';

/// When the post-assessment finished it pushed [PostAssessmentResultScreen]
/// straight out of the last game — a parent-facing comparison of the child's
/// own before/after levels, handed to the child who was still holding the
/// device, with no verification in front of it.
///
/// This pins the finish path itself: where it lands, and that the numbers the
/// run computed survive the extra hop intact.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => <String, Object?>{},
    );
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-publishable-key',
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const preLevel = AreaLevel(
    level: 'emerging',
    levelInt: 1,
    levelName: 'Emerging',
    confidence: 0.7,
  );
  const postLevel = AreaLevel(
    level: 'strength',
    levelInt: 2,
    levelName: 'Strength',
    confidence: 0.95,
  );

  final improvement = <String, dynamic>{
    'has_data': true,
    'accuracy_improvement': 0.18,
    'response_time_improvement': 600.0,
  };

  Widget app(AssessmentProvider provider) => MultiProvider(
        providers: [
          ChangeNotifierProvider<ChildProvider>(
            create: (_) => _TestChildProvider(),
          ),
          ChangeNotifierProvider<AssessmentProvider>.value(value: provider),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: PostAssessmentProgressScreen(
            skipToFinish: true,
            voiceOverFactory: (_) => _RecordingVoiceOver(),
          ),
        ),
      );

  testWidgets('a finished run hands off to the child, not to the results',
      (tester) async {
    await tester.pumpWidget(app(_ScriptedAssessmentProvider(
      improvement: improvement,
      preLevels: const {'communication': preLevel},
      postLevels: const {'communication': postLevel},
    )));
    await tester.pumpAndSettle();

    expect(find.byType(PostAssessmentHandoffScreen), findsOneWidget);
    expect(find.byType(PostAssessmentResultScreen), findsNothing,
        reason: 'the child is still holding the device');
  });

  testWidgets('the hand-off carries this run\'s exact numbers through',
      (tester) async {
    final provider = _ScriptedAssessmentProvider(
      improvement: improvement,
      preLevels: const {'communication': preLevel},
      postLevels: const {'communication': postLevel},
    );
    await tester.pumpWidget(app(provider));
    await tester.pumpAndSettle();

    final handoff = tester.widget<PostAssessmentHandoffScreen>(
        find.byType(PostAssessmentHandoffScreen));

    expect(handoff.improvement, same(improvement));
    expect(handoff.nextModulePremiumRequired, isFalse);
    // The finish chain runs the prediction, re-derives a fresh support
    // profile from it, then freeze-frames that exact profile and prediction
    // into the post snapshot — in that order.
    expect(provider.callOrder, ['predict', 'finalize', 'capture']);
    expect(provider.predictionCalls, 1);
    expect(provider.finalizeAiResponses.single, isNotNull);
    expect(provider.capturedProfiles.single, same(_postProfile));
    expect(provider.capturedPredictions.single, isNotNull);
  });

  testWidgets('the child sees the spoken hand-off, then the gate',
      (tester) async {
    await tester.pumpWidget(app(_ScriptedAssessmentProvider(
      improvement: improvement,
      preLevels: const {'communication': preLevel},
      postLevels: const {'communication': postLevel},
    )));
    // The finish path runs to the child hand-off. Fixed pumps (not
    // pumpAndSettle) land us inside the milestone celebration, whose companion
    // twinkles continuously and so never "settles": the first flushes the
    // finalize chain and pushes the hand-off, the second lets its route
    // transition in — well short of the 4.5 s celebration hold.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    // Celebration first, then the written instruction and its narration. The
    // headline is voiced, not drawn — the subtitle is what shows.
    expect(find.text('You finished all the activities!'), findsOneWidget);
    await tester.pump(kHandoffCelebrationDuration);
    await tester.pump(kHandoffVoiceDelay);
    await tester.pumpAndSettle();

    expect(find.text(kHandoffInstructionText), findsOneWidget);
    expect(find.text('I\'m the Parent'), findsOneWidget);
    expect(find.byType(PostAssessmentResultScreen), findsNothing);
  });

  testWidgets('locked cycle skips prediction and carries Premium gate',
      (tester) async {
    final provider = _ScriptedAssessmentProvider(
      improvement: improvement,
      preLevels: const {'communication': preLevel},
      postLevels: const {'communication': postLevel},
      locked: true,
    );
    await tester.pumpWidget(app(provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(PostAssessmentHandoffScreen), findsOneWidget);
    final handoff = tester.widget<PostAssessmentHandoffScreen>(
        find.byType(PostAssessmentHandoffScreen));
    expect(handoff.nextModulePremiumRequired, isTrue);
    // Locked: the prediction is skipped, but the profile is still re-derived
    // (explicitly with no prediction to reuse) and frozen into the snapshot.
    expect(provider.predictionCalls, 0);
    expect(provider.callOrder, ['finalize', 'capture']);
    expect(provider.finalizeAiResponses.single, isNull);
    expect(provider.capturedProfiles.single, same(_postProfile));
    expect(provider.capturedPredictions.single, isNull);
  });

  testWidgets('result explains Premium gating only for locked next modules',
      (tester) async {
    final postResult = AssessmentResult(
      id: 'post-1',
      childId: 'child-1',
      type: 'post',
      gameId: 'match_it',
      score: 8,
      totalItems: 10,
      errorCount: 1,
      avgResponseTimeMs: 900,
      completedAt: DateTime(2026, 8, 15),
    );

    Widget result({required bool locked}) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ChildProvider>(
              create: (_) => _TestChildProvider(),
            ),
            ChangeNotifierProvider<AssessmentProvider>.value(
              value: _ScriptedAssessmentProvider(
                improvement: improvement,
                preLevels: const {'communication': preLevel},
                postLevels: const {'communication': postLevel},
                postResults: [postResult],
                seedPostSnapshot: true,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: PostAssessmentResultScreen(
              improvement: improvement,
              nextModulePremiumRequired: locked,
              summaryService: _FallbackSummaryService(),
            ),
          ),
        );

    await tester.pumpWidget(result(locked: true));
    expect(find.textContaining('Premium is required'), findsOneWidget);
    expect(find.text('GAME RESULTS'), findsOneWidget);
    expect(find.textContaining('Match It'), findsOneWidget);
    expect(
      find.text(
        'Accuracy improved by 18 percentage points '
        'since the pre-assessment.',
      ),
      findsOneWidget,
    );
    expect(find.text('Responses are 0.6s faster on average.'), findsOneWidget);

    await tester.pumpWidget(result(locked: false));
    expect(find.textContaining('Premium is required'), findsNothing);
    expect(find.text('GAME RESULTS'), findsOneWidget);
    // The unlocked path renders the learning path modules alongside the
    // game results, and 'Match It' is both a completed game row and a
    // recommended module, so at least one occurrence is expected.
    expect(find.textContaining('Match It'), findsWidgets);

    // The completion layout schedules a 3s celebration timer in its
    // initState; advance the clock past it so the test framework does not
    // report a pending Timer after the tree is torn down.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('dashboard defaults to the frozen post run and keeps comparison',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ChildProvider>(
          create: (_) => _TestChildProvider(),
        ),
        ChangeNotifierProvider<AssessmentProvider>.value(
          value: _DashboardAssessmentProvider(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: AssessmentDashboardScreen(
          summaryService: _FallbackSummaryService(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('POST-ASSESSMENT'), findsOneWidget);
    expect(find.textContaining('Do What I Say'), findsOneWidget);
    expect(
      find.text('9 Correct · 1 Errors · 2 Off-Target · 10 Total Items'),
      findsOneWidget,
    );
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Visual'), findsOneWidget);
    expect(find.text('10 min'), findsOneWidget);
    expect(find.text('3x'), findsOneWidget);
    final activities = tester.widget<AssessmentLearningPathCard>(
      find.byType(AssessmentLearningPathCard),
    );
    expect(activities.modules.map((module) => module.name), contains('Match It'));
    expect(find.byType(AssessmentProgressCard), findsOneWidget);
    expect(find.textContaining('Copy Me'), findsNothing);
  });

  testWidgets('dashboard rebuilds a legacy post snapshot stale pre profile',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ChildProvider>(
          create: (_) => _TestChildProvider(),
        ),
        ChangeNotifierProvider<AssessmentProvider>.value(
          value: _DashboardAssessmentProvider(legacyPostProfile: true),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: AssessmentDashboardScreen(
          summaryService: _FallbackSummaryService(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('POST-ASSESSMENT'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Visual'), findsOneWidget);
    expect(find.text('Intermediate'), findsNothing);
  });
}

/// The support profile the flow re-derives from the post rubric before it
/// snapshots the run. The fresh profile must be what the snapshot carries —
/// not the stale pre-assessment profile.
const _postProfile = SupportProfile(
  communication: 'strong',
  socialInteraction: 'emerging',
  playSkills: 'developing',
  attention: 'moderate',
  recommendedDifficulty: 'advanced',
  recommendedPromptStyle: 'visual',
  recommendedSessionMinutes: 10,
  promptRepetition: 3,
);

const _legacyPreProfile = SupportProfile(
  communication: 'emerging',
  socialInteraction: 'emerging',
  playSkills: 'developing',
  attention: 'moderate',
  recommendedDifficulty: 'intermediate',
);

class _ScriptedAssessmentProvider extends AssessmentProvider {
  _ScriptedAssessmentProvider({
    required this.improvement,
    required this.preLevels,
    required this.postLevels,
    this.postResults = const [],
    this.seedPostSnapshot = false,
    this.locked = false,
  }) {
    if (seedPostSnapshot) {
      _postSnapshot = _snapshot(
        results: postResults,
        profile: _postProfile,
        prediction: _prediction(postLevels),
      );
    }
  }

  final Map<String, dynamic> improvement;
  final Map<String, AreaLevel> preLevels;
  final Map<String, AreaLevel> postLevels;
  @override
  final List<AssessmentResult> postResults;
  final bool locked;
  final bool seedPostSnapshot;

  /// The order in which the finish chain touched the provider.
  final List<String> callOrder = [];
  int predictionCalls = 0;
  final List<AiAssessmentResponse?> finalizeAiResponses = [];
  final List<SupportProfile?> capturedProfiles = [];
  final List<AiAssessmentResponse?> capturedPredictions = [];

  AssessmentRunSnapshot? _postSnapshot;
  String? _runId;

  @override
  bool get nextCycleLocked => locked;

  @override
  AssessmentRunSnapshot? get postSnapshot => _postSnapshot;

  AssessmentRunSnapshot _snapshot({
    required List<AssessmentResult> results,
    required SupportProfile profile,
    required AiAssessmentResponse? prediction,
  }) =>
      AssessmentRunSnapshot(
        assessmentType: 'post',
        childId: 'child-1',
        completedAt: DateTime(2026, 8, 15),
        results: results,
        profile: profile,
        prediction: prediction,
      );

  @override
  Future<String> startAssessmentRun({
    required String childId,
    required String type,
  }) async =>
      _runId = 'run-1';

  @override
  String? get currentAssessmentRunId => _runId;

  @override
  AssessmentRunSnapshot? get preSnapshot => AssessmentRunSnapshot(
        assessmentType: 'pre',
        childId: 'child-1',
        completedAt: DateTime(2026, 8, 1),
        results: const [],
        profile: const SupportProfile(
          communication: 'emerging',
          socialInteraction: 'emerging',
          playSkills: 'developing',
          attention: 'moderate',
        ),
        prediction: _prediction(preLevels),
      );

  @override
  Future<Map<String, dynamic>> finalizePostAssessment(String childId) async =>
      improvement;

  @override
  Future<SupportProfile> finalizeSupportProfile(
    String childId, {
    AiAssessmentResponse? aiResponse,
  }) async {
    callOrder.add('finalize');
    finalizeAiResponses.add(aiResponse);
    return _postProfile;
  }

  @override
  Future<AiAssessmentResponse?> predictWithAI(
    String childId, {
    String? assessmentType,
  }) async {
    callOrder.add('predict');
    predictionCalls++;
    return _prediction(postLevels);
  }

  @override
  Future<AssessmentRunSnapshot> captureRunSnapshot(
    String childId, {
    required String assessmentType,
    AiAssessmentResponse? prediction,
    SupportProfile? profile,
  }) async {
    callOrder.add('capture');
    capturedPredictions.add(prediction);
    capturedProfiles.add(profile);
    final snapshot = _snapshot(
      results: assessmentType == 'post' ? postResults : const [],
      profile: profile ?? _postProfile,
      prediction: prediction,
    );
    if (assessmentType == 'post') _postSnapshot = snapshot;
    return snapshot;
  }
}

class _DashboardAssessmentProvider extends AssessmentProvider {
  _DashboardAssessmentProvider({this.legacyPostProfile = false}) {
    _preSnapshot = AssessmentRunSnapshot(
      assessmentType: 'pre',
      childId: 'child-1',
      assessmentRunId: 'pre-run',
      completedAt: DateTime(2026, 8, 1),
      results: [
        AssessmentResult(
          id: 'pre-result',
          childId: 'child-1',
          assessmentRunId: 'pre-run',
          type: 'pre',
          gameId: 'copy_me',
          score: 4,
          totalItems: 10,
          errorCount: 6,
          avgResponseTimeMs: 2400,
          completedAt: DateTime(2026, 8, 1),
        ),
      ],
      profile: _legacyPreProfile,
      prediction: _prediction(const {
        'communication': AreaLevel(
          level: 'emerging',
          levelInt: 1,
          levelName: 'Emerging',
          confidence: 0.7,
        ),
      }),
    );
    _postSnapshot = AssessmentRunSnapshot(
      assessmentType: 'post',
      childId: 'child-1',
      assessmentRunId: 'post-run',
      completedAt: DateTime(2026, 8, 15),
      results: [
        AssessmentResult(
          id: 'post-result',
          childId: 'child-1',
          assessmentRunId: 'post-run',
          type: 'post',
          gameId: 'do_what_i_say',
          score: 9,
          totalItems: 10,
          errorCount: 1,
          randomTouchCount: 2,
          avgResponseTimeMs: 900,
          completedAt: DateTime(2026, 8, 15),
          rawMetrics: const {'preferred_mode': 'visual'},
        ),
      ],
      profile: legacyPostProfile ? _legacyPreProfile : _postProfile,
      profileIsRunSpecific: !legacyPostProfile,
      prediction: const AiAssessmentResponse(
        predictedProfile: 'strong',
        confidence: 0.95,
        summary: 'Post assessment summary.',
        supportLevel: 'low',
        recommendedModules: ['Match It'],
        moduleDetails: [
          ModuleRecommendation(
            gameId: 'match_it',
            name: 'Match It',
            startingLevel: 3,
          ),
        ],
        areaLevels: {
          'communication': AreaLevel(
            level: 'strength',
            levelInt: 2,
            levelName: 'Strength',
            confidence: 0.95,
          ),
        },
      ),
    );
  }

  final bool legacyPostProfile;
  late final AssessmentRunSnapshot _preSnapshot;
  late final AssessmentRunSnapshot _postSnapshot;

  @override
  bool get hasPostAssessment => true;

  @override
  AssessmentRunSnapshot get preSnapshot => _preSnapshot;

  @override
  AssessmentRunSnapshot get postSnapshot => _postSnapshot;

  @override
  SupportProfile get supportProfile => _legacyPreProfile;

  @override
  AiAssessmentResponse get aiPrediction =>
      _preSnapshot.prediction!;
}

class _RecordingVoiceOver extends VoiceOverService {
  _RecordingVoiceOver() : super(languageCode: 'en_adult_woman');

  @override
  Future<void> play(
    VoiceOverCue cue, {
    bool awaitCompletion = false,
    bool skipDebounce = false,
  }) async {}

  @override
  Future<void> dispose() async {
    await super.dispose();
  }
}

class _FallbackSummaryService extends AssessmentSummaryService {
  @override
  Future<AssessmentSummary> summarize({
    required List<Map<String, String>> areas,
    required int overallPct,
    required String supportLevel,
    required List<String> recommendations,
    required String fallback,
    List<Map<String, String>>? previousAreas,
    String languageCode = 'en',
  }) async => AssessmentSummary(text: fallback, isAi: false);
}

/// The screen only ever reads [AiAssessmentResponse.areaLevels]; the rest of
/// the schema is legacy dual-response padding.
AiAssessmentResponse _prediction(Map<String, AreaLevel> areaLevels) =>
    AiAssessmentResponse(
      predictedProfile: 'moderate',
      confidence: 0.9,
      summary: 'test',
      supportLevel: 'moderate',
      recommendedModules: const [],
      areaLevels: areaLevels,
    );

class _TestChildProvider extends ChildProvider {
  _TestChildProvider()
      : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  @override
  ChildProfile? get profile => _childProfile;

  @override
  Future<void> loadProfile() async {}
}

final _childProfile = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Test',
  birthDate: DateTime(2022, 4, 20),
  avatar: 'bear',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

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
