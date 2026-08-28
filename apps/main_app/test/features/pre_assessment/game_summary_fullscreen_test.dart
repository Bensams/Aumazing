import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/pre_assessment/game_summary_dialog.dart';
import 'package:aumazing/features/pre_assessment/pre_assessment_result_screen.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _results = [
  AssessmentResult(
    id: 'r-1',
    childId: 'child-1',
    type: 'pre',
    gameId: 'copy_me',
    score: 8,
    totalItems: 10,
    errorCount: 2,
    randomTouchCount: 3,
    avgResponseTimeMs: 1500,
    completedAt: DateTime(2026, 8, 29),
  ),
  AssessmentResult(
    id: 'r-2',
    childId: 'child-1',
    type: 'pre',
    gameId: 'match_it',
    score: 9,
    totalItems: 10,
    errorCount: 1,
    randomTouchCount: 0,
    avgResponseTimeMs: 1200,
    completedAt: DateTime(2026, 8, 29),
  ),
];

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

final _navKey = GlobalKey<NavigatorState>();

Widget _summary({VoidCallback? onContinue}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      navigatorKey: _navKey,
      home: GameSummaryDialog(
        results: _results,
        aiResponse: null,
        onContinue: onContinue ?? () {},
      ),
    ),
  );
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider()
    : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'renders full screen with all three sections and no Dialog',
    (tester) async {
      await tester.pumpWidget(_summary());

      // No longer a modal dialog: no Dialog widget in the tree.
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Pre-Assessment Summary'), findsOneWidget);

      // Tap stats zone.
      expect(find.text('Correct\nTaps'), findsOneWidget);
      expect(find.text('Error\nTaps'), findsOneWidget);
      expect(find.text('Off-Target\nTaps'), findsOneWidget);

      // Overall stats zone.
      expect(find.text('Total Time'), findsOneWidget);
      expect(find.text('Total Taps'), findsOneWidget);
      expect(find.text('Games'), findsOneWidget);

      // Per-game breakdown zone.
      expect(find.text('Game Results'), findsOneWidget);
      expect(find.text('Copy Me'), findsOneWidget);
      expect(find.text('Match It'), findsOneWidget);
      expect(find.byType(StatusPillBadge), findsWidgets);
    },
  );

  testWidgets('system back does not leave the summary', (tester) async {
    await tester.pumpWidget(_summary());

    // PopScope(canPop: false) consumes the back event: the summary must
    // still be on screen afterwards. (handlePopRoute returns true because
    // the event was handled — i.e. blocked — by the scope.)
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Pre-Assessment Summary'), findsOneWidget);
    expect(find.byType(PreAssessmentResultScreen), findsNothing);
  });

  testWidgets('Continue replaces the summary with the result screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _summary(
        onContinue: () => _navKey.currentState!.pushReplacement(
          MaterialPageRoute(
            builder: (_) => PreAssessmentResultScreen(
              profile: _profile,
              results: _results,
              aiResponse: null,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(AppPrimaryButton, 'Continue'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.byType(PreAssessmentResultScreen), findsOneWidget);
    expect(find.text('Pre-Assessment Summary'), findsNothing);
  });
}
