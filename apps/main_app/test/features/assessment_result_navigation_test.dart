import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/pre_assessment/assessment_dashboard_screen.dart';
import 'package:aumazing/features/pre_assessment/pre_assessment_intro_screen.dart';
import 'package:aumazing/features/pre_assessment/pre_assessment_result_screen.dart';
import 'package:aumazing/features/post_assessment/post_assessment_result_screen.dart';
import 'package:aumazing/features/therapy/therapy_directory_screen.dart';
import 'package:aumazing/model/ai_assessment_response.dart';
import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _phonePortrait = Size(360, 800);

final _childProfile = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Test',
  birthDate: DateTime(2022, 4, 20),
  avatar: 'bear',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

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

AssessmentResult _result(
  String gameId, {
  int score = 7,
  int totalItems = 10,
  int errorCount = 3,
}) => AssessmentResult(
  id: 'r-$gameId',
  childId: 'child-1',
  assessmentRunId: 'run-1',
  type: 'pre',
  gameId: gameId,
  score: score,
  totalItems: totalItems,
  errorCount: errorCount,
  avgResponseTimeMs: 1800,
  completedAt: DateTime(2026, 5, 12),
);

final _results = [_result('copy_me'), _result('match_it')];

final _criticalResults = [
  _result('copy_me', score: 49, totalItems: 100, errorCount: 51),
];


const _criticalAiResponse = AiAssessmentResponse(
  predictedProfile: 'mixed_support',
  confidence: 0.8,
  summary: 'Several areas may benefit from additional support.',
  supportLevel: 'high',
  recommendedModules: [],
  areaLevels: {
    'communication': AreaLevel(
      level: 'needs_support',
      levelInt: 0,
      levelName: 'Needs Support',
      confidence: 0.9,
    ),
    'social': AreaLevel(
      level: 'needs_support',
      levelInt: 0,
      levelName: 'Needs Support',
      confidence: 0.9,
    ),
    'play': AreaLevel(
      level: 'needs_support',
      levelInt: 0,
      levelName: 'Needs Support',
      confidence: 0.9,
    ),
    'attention': AreaLevel(
      level: 'needs_support',
      levelInt: 0,
      levelName: 'Needs Support',
      confidence: 0.9,
    ),
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('completion results continue back to home', (tester) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey: navigator, home: const _Home()));

    navigator.currentState!.push(
      MaterialPageRoute(
        builder:
            (_) => PreAssessmentResultScreen(
              profile: _finalizedProfile,
              results: _results,
            ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('Explore Therapy Center support'), findsNothing);

    expect(find.text(AssessmentLabels.title), findsOneWidget);
    expect(find.text(AssessmentLabels.continueToHome), findsOneWidget);
    expect(find.text(AssessmentLabels.retakeAssessment), findsNothing);

    await tester.ensureVisible(find.text(AssessmentLabels.continueToHome));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AssessmentLabels.continueToHome));
    await tester.pumpAndSettle();

    expect(find.byType(_Home), findsOneWidget);
  });

  testWidgets('critical completion results offer Therapy Center support', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey: navigator, home: const _Home()));
    navigator.currentState!.push(
      MaterialPageRoute(
        builder:
            (_) => PreAssessmentResultScreen(
              profile: _finalizedProfile,
              results: _criticalResults,
              aiResponse: _criticalAiResponse,
            ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Explore Therapy Center support'), findsOneWidget);
    expect(find.textContaining('not a medical diagnosis'), findsOneWidget);
    expect(find.text('Browse Therapy Centers'), findsOneWidget);

    await tester.tap(find.text('Browse Therapy Centers'));
    await tester.pumpAndSettle();

    expect(find.byType(TherapyDirectoryScreen), findsOneWidget);
    expect(find.text('Therapy Directory'), findsOneWidget);
  });

  testWidgets('critical completion results can be dismissed for later', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey: navigator, home: const _Home()));

    navigator.currentState!.push(
      MaterialPageRoute(
        builder:
            (_) => PreAssessmentResultScreen(
              profile: _finalizedProfile,
              results: _criticalResults,
              aiResponse: _criticalAiResponse,
            ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Explore Therapy Center support'), findsOneWidget);
    expect(find.text('Browse Therapy Centers'), findsOneWidget);
    expect(find.text('Maybe Later'), findsOneWidget);

    await tester.tap(find.text('Maybe Later'));
    await tester.pumpAndSettle();

    expect(find.text('Explore Therapy Center support'), findsNothing);
    expect(find.text('Browse Therapy Centers'), findsNothing);
    expect(find.text(AssessmentLabels.title), findsOneWidget);
    expect(find.text(AssessmentLabels.continueToHome), findsOneWidget);
  });
  testWidgets('post critical results offer Therapy Center support', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey: navigator, home: const _Home()));
    navigator.currentState!.push(
      MaterialPageRoute(
        builder: (_) => const PostAssessmentResultScreen(
          improvement: {'has_data': true, 'post_accuracy': 0.4},
          preAreaLevels: {},
          postAreaLevels: {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Explore Therapy Center support'), findsOneWidget);
    expect(find.textContaining('not a medical diagnosis'), findsOneWidget);
    await tester.tap(find.text('Maybe Later'));
    await tester.pumpAndSettle();
    expect(find.text('Explore Therapy Center support'), findsNothing);
  });

  testWidgets('exactly 50% results do not offer Therapy Center support', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey: navigator, home: const _Home()));

    navigator.currentState!.push(
      MaterialPageRoute(
        builder:
            (_) => PreAssessmentResultScreen(
              profile: _finalizedProfile,
              results: [
                _result('copy_me', score: 5, totalItems: 10, errorCount: 5),
              ],
              // Four Needs Support areas would trigger the old area-count
              // heuristic, so this pins the canonical 0.50 boundary.
              aiResponse: _criticalAiResponse,
            ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Explore Therapy Center support'), findsNothing);
  });

  testWidgets('critical therapy navigation preserves the active child', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey: navigator, home: const _Home()));

    navigator.currentState!.push(
      MaterialPageRoute(
        builder:
            (_) => PreAssessmentResultScreen(
              profile: _finalizedProfile,
              results: [
                _result('copy_me', score: 49, totalItems: 100, errorCount: 51),
              ],
              aiResponse: _criticalAiResponse,
            ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('Browse Therapy Centers'), findsOneWidget);
    expect(find.textContaining('not a medical diagnosis'), findsOneWidget);

    final beforeId =
        tester.element(find.byType(PreAssessmentResultScreen))
            .read<ChildProvider>()
            .profile
            ?.id;
    expect(beforeId, 'child-1');

    await tester.tap(find.text('Browse Therapy Centers'));
    await tester.pumpAndSettle();

    expect(find.byType(TherapyDirectoryScreen), findsOneWidget);
    final afterId =
        tester.element(find.byType(TherapyDirectoryScreen))
            .read<ChildProvider>()
            .profile
            ?.id;
    expect(afterId, beforeId);
  });

  testWidgets('zero-total results do not offer Therapy Center support', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey: navigator, home: const _Home()));
    navigator.currentState!.push(
      MaterialPageRoute(
        builder:
            (_) => PreAssessmentResultScreen(
              profile: _finalizedProfile,
              results: [
                _result('copy_me', score: 0, totalItems: 0, errorCount: 0),
              ],
              aiResponse: _criticalAiResponse,
            ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Explore Therapy Center support'), findsNothing);
  });


  testWidgets('review results go back to the dashboard', (tester) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey: navigator, home: const _Home()));

    navigator.currentState!.push(
      MaterialPageRoute(builder: (_) => const AssessmentDashboardScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text(AssessmentLabels.retakeAssessment), findsOneWidget);
    expect(find.byType(GameCelebrationOverlay), findsNothing);

    await tester.ensureVisible(find.text(AssessmentLabels.home));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AssessmentLabels.home));
    await tester.pumpAndSettle();

    expect(find.byType(_Home), findsOneWidget);
  });

  testWidgets('review results start a retake', (tester) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey: navigator, home: const _Home()));

    navigator.currentState!.push(
      MaterialPageRoute(builder: (_) => const AssessmentDashboardScreen()),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(AssessmentLabels.retakeAssessment));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AssessmentLabels.retakeAssessment));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.byType(PreAssessmentIntroScreen), findsOneWidget);
  });

  testWidgets('review mode shows the finalized profile, not a recomputed one', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(home: const AssessmentDashboardScreen()));
    await tester.pumpAndSettle();

    // The sensory note recorded with the run — the child's *current*
    // settings would produce different notes entirely.
    expect(find.textContaining('Prefers Quiet Play'), findsOneWidget);
    expect(find.text('Intermediate'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);
  });
}

Widget _app({required Widget home, GlobalKey<NavigatorState>? navigatorKey}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(),
      ),
      ChangeNotifierProvider<AssessmentProvider>(
        create: (_) => _TestAssessmentProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      navigatorKey: navigatorKey,
      home: home,
    ),
  );
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('home')));
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider()
    : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  @override
  ChildProfile? get profile => _childProfile;

  @override
  Future<void> loadProfile() async {}
}

class _TestAssessmentProvider extends AssessmentProvider {
  @override
  bool get hasPreAssessment => true;

  @override
  List<AssessmentResult> get preResults => _results;

  @override
  SupportProfile? get supportProfile => _finalizedProfile;

  @override
  Future<void> loadAssessments(String childId) async {}
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
