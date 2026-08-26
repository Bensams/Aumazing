import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/post_assessment/post_assessment_handoff_screen.dart';
import 'package:aumazing/features/post_assessment/post_assessment_progress_screen.dart';
import 'package:aumazing/features/post_assessment/post_assessment_result_screen.dart';
import 'package:aumazing/model/ai_assessment_response.dart';
import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/model/assessment_run_snapshot.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
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
    'accuracy_improvement': 18.0,
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
    await tester.pumpWidget(app(_ScriptedAssessmentProvider(
      improvement: improvement,
      preLevels: const {'communication': preLevel},
      postLevels: const {'communication': postLevel},
    )));
    await tester.pumpAndSettle();

    final handoff = tester.widget<PostAssessmentHandoffScreen>(
        find.byType(PostAssessmentHandoffScreen));

    expect(handoff.improvement, same(improvement));
    // The baseline is the frozen pre snapshot, not the freshly overwritten
    // "latest" prediction — that distinction is what makes "before" mean
    // anything, and the extra screen must not blur it.
    expect(handoff.preAreaLevels, {'communication': preLevel});
    expect(handoff.postAreaLevels, {'communication': postLevel});
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
    expect(provider.predictionCalls, 0);
  });

  testWidgets('result explains Premium gating only for locked next modules',
      (tester) async {
    Widget result({required bool locked}) => MaterialApp(
          theme: AppTheme.light,
          home: PostAssessmentResultScreen(
            improvement: improvement,
            preAreaLevels: const {},
            postAreaLevels: const {},
            nextModulePremiumRequired: locked,
          ),
        );

    await tester.pumpWidget(result(locked: true));
    expect(find.textContaining('Premium is required'), findsOneWidget);

    await tester.pumpWidget(result(locked: false));
    expect(find.textContaining('Premium is required'), findsNothing);
    expect(
      find.text('A new learning path has been prepared from these results.'),
      findsOneWidget,
    );
  });
}

/// Stands in for the provider's finalization, which normally writes to SQLite
/// and runs the on-device model.
class _ScriptedAssessmentProvider extends AssessmentProvider {
  _ScriptedAssessmentProvider({
    required this.improvement,
    required this.preLevels,
    required this.postLevels,
    this.locked = false,
  });

  final Map<String, dynamic> improvement;
  final Map<String, AreaLevel> preLevels;
  final Map<String, AreaLevel> postLevels;
  final bool locked;
  int predictionCalls = 0;

  String? _runId;

  @override
  bool get nextCycleLocked => locked;


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
        prediction: _prediction(preLevels),
      );

  @override
  Future<Map<String, dynamic>> finalizePostAssessment(String childId) async =>
      improvement;
  @override
  Future<AiAssessmentResponse?> predictWithAI(
    String childId, {
    String? assessmentType,
  }) async {
    predictionCalls++;

    return _prediction(postLevels);
  }

  @override
  Future<AssessmentRunSnapshot> captureRunSnapshot(
    String childId, {
    required String assessmentType,
    AiAssessmentResponse? prediction,
    SupportProfile? profile,
  }) async =>
      AssessmentRunSnapshot(
        assessmentType: assessmentType,
        childId: childId,
        completedAt: DateTime(2026, 8, 15),
        results: const [],
        prediction: prediction,
      );
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
