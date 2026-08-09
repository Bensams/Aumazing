import 'package:aumazing/features/pre_assessment/assessment_dashboard_screen.dart';
import 'package:aumazing/features/pre_assessment/pre_assessment_intro_screen.dart';
import 'package:aumazing/features/premium/premium_upgrade_screen.dart';
import 'package:aumazing/features/therapy/therapy_directory_screen.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/core/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Parent-facing screens run in portrait on phones. A landscape-only layout
/// shows up here as a RenderFlex overflow, which the framework surfaces as a
/// test exception.
const _phonePortrait = Size(360, 800);

final _profile = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Test',
  birthDate: DateTime(2022, 4, 20),
  avatar: 'bear',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  setUp(() {
    // Screens read the entitlement to decide between the free and premium
    // variants; the default (free) path shows the most content.
  });

  testWidgets('pre-assessment intro stacks its columns in portrait', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const PreAssessmentIntroScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Let\'s Get to Know You!'), findsOneWidget);
    expect(find.text('Let\'s Start!'), findsOneWidget);

    // The gradient must fill the screen — it used to shrink-wrap the scroll
    // content and leave a bare band under the "Let's Start!" button.
    expect(
      tester.getSize(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient ==
                  AppGradients.parentLavenderMint,
        ),
      ),
      _phonePortrait,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('assessment dashboard stacks its three cards in portrait', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        const AssessmentDashboardScreen(),
        assessmentProvider: _TestAssessmentProvider(withResults: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Assessment Summary'), findsOneWidget);
    // All three cards are on one scrolling page rather than in columns.
    expect(find.text('Game Results'), findsOneWidget);
    expect(find.text('Developmental Profile'), findsOneWidget);
    expect(find.text('Recommendations'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('premium upgrade fits a portrait phone', (tester) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        PremiumUpgradeScreen(
          authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });

  testWidgets('therapy directory fits a portrait phone', (tester) async {
    await tester.binding.setSurfaceSize(_phonePortrait);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const TherapyDirectoryScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });
}

Widget _wrap(Widget screen, {AssessmentProvider? assessmentProvider}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(),
      ),
      ChangeNotifierProvider<AssessmentProvider>(
        create: (_) => assessmentProvider ?? _TestAssessmentProvider(),
      ),
    ],
    child: MaterialApp(theme: AppTheme.light, home: screen),
  );
}

AssessmentResult _result(String gameId) => AssessmentResult(
  id: 'r-$gameId',
  childId: 'child-1',
  type: 'pre',
  gameId: gameId,
  score: 7,
  totalItems: 10,
  errorCount: 3,
  avgResponseTimeMs: 1800,
  completedAt: DateTime(2026, 1, 1),
);

class _TestChildProvider extends ChildProvider {
  _TestChildProvider()
    : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  @override
  ChildProfile? get profile => _profile;

  @override
  Future<void> loadProfile() async {}
}

class _TestAssessmentProvider extends AssessmentProvider {
  _TestAssessmentProvider({this.withResults = false});

  final bool withResults;

  @override
  bool get hasPreAssessment => withResults;

  @override
  List<AssessmentResult> get preResults => withResults
      ? [
          _result('copy_me'),
          _result('match_it'),
          _result('do_what_i_say'),
          _result('my_turn_your_turn'),
        ]
      : const [];

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
