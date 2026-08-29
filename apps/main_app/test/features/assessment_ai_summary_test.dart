import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/pre_assessment/assessment_result_view.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/services/assessment_summary_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The AI summary is a rewording of the result the parent is already
/// reading: it replaces the rubric sentence when it arrives, is labelled so
/// the parent knows where the words came from, and is simply absent when the
/// summarizer cannot be reached. Nothing else on the screen depends on it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an AI summary replaces the rubric sentence and is labelled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeSummaryService(
      const AssessmentSummary(text: _aiText, isAi: true),
    );
    await tester.pumpWidget(_app(summaryService: service));
    await tester.pumpAndSettle();

    expect(find.text(_aiText), findsOneWidget);
    expect(find.text(AssessmentLabels.aiSummary), findsOneWidget);
    expect(find.textContaining('Review each skill area'), findsNothing);

    // The request describes the run, never the child.
    expect(service.seenAreas, isNotEmpty);
    expect(service.seenPreviousAreas, isEmpty);
    expect(service.seenFallback, contains('Review each skill area'));
    expect(service.seenLanguage, 'en');
  });

  testWidgets('an unreachable summarizer leaves the rubric summary alone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // What the service returns when it is offline, timed out, or unkeyed:
    // the fallback it was handed, flagged as not-AI.
    final service = _FakeSummaryService(
      const AssessmentSummary(text: 'ignored fallback echo', isAi: false),
    );
    await tester.pumpWidget(_app(summaryService: service));
    await tester.pumpAndSettle();

    expect(find.textContaining('Review each skill area'), findsOneWidget);
    expect(find.text(AssessmentLabels.aiSummary), findsNothing);
  });

  testWidgets('a comparable earlier run is sent as before-and-after levels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeSummaryService(
      const AssessmentSummary(text: _aiText, isAi: true),
    );
    await tester.pumpWidget(
      _app(
        summaryService: service,
        assessmentType: 'post',
        progress: ResultProgress(
          areas: const [
            ResultProgressArea(
              label: 'Communication',
              beforeLevelName: 'Emerging',
              afterLevelName: 'Strength',
              beforeLevelInt: 1,
              afterLevelInt: 2,
            ),
          ],
          beforeCompletedAt: DateTime(2026, 5, 12),
          afterCompletedAt: DateTime(2026, 8, 15),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.seenPreviousAreas, [
      {'name': 'Communication', 'level': 'Emerging'},
    ]);
  });
}

const _aiText =
    'Your child really shone at copying actions, and a little more '
    'practice with taking turns will help.';

Widget _app({
  required AssessmentSummaryService summaryService,
  String assessmentType = 'pre',
  ResultProgress? progress,
}) => ChangeNotifierProvider<ChildProvider>(
  create: (_) => _TestChildProvider(),
  child: MaterialApp(
    theme: AppTheme.light,
    home: AssessmentResultView(
      results: _results,
      profile: _finalizedProfile,
      presentation: AssessmentResultPresentation.review,
      assessmentType: assessmentType,
      progress: progress,
      childDisplayName: 'Test',
      showCelebration: false,
      summaryService: summaryService,
    ),
  ),
);

class _FakeSummaryService extends AssessmentSummaryService {
  _FakeSummaryService(this._reply);

  final AssessmentSummary _reply;

  List<Map<String, String>>? seenAreas;
  List<Map<String, String>>? seenPreviousAreas;
  String? seenFallback;
  String? seenLanguage;

  @override
  Future<AssessmentSummary> summarize({
    required List<Map<String, String>> areas,
    required int overallPct,
    required String supportLevel,
    required List<String> recommendations,
    required String fallback,
    List<Map<String, String>>? previousAreas,
    String languageCode = 'en',
  }) async {
    seenAreas = areas;
    seenPreviousAreas = previousAreas;
    seenFallback = fallback;
    seenLanguage = languageCode;
    return _reply;
  }
}

const _finalizedProfile = SupportProfile(
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

final _results = [
  AssessmentResult(
    id: 'r-copy_me',
    childId: 'child-1',
    assessmentRunId: 'run-1',
    type: 'pre',
    gameId: 'copy_me',
    score: 7,
    totalItems: 10,
    errorCount: 3,
    avgResponseTimeMs: 1800,
    completedAt: DateTime(2026, 5, 12),
  ),
];

final _childProfile = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Test',
  birthDate: DateTime(2022, 4, 20),
  avatar: 'bear',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

class _TestChildProvider extends ChildProvider {
  _TestChildProvider()
    : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  @override
  ChildProfile? get profile => _childProfile;

  @override
  Future<void> loadProfile() async {}
}

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
