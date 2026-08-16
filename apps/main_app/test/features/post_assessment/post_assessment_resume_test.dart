import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/post_assessment/post_assessment_progress_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/services/assessment_service.dart';
import 'package:aumazing/widgets/resume_assessment_dialog.dart';

/// The post-assessment entry point must ask about an interrupted run *before*
/// starting a new one — starting one closes the run worth offering (AUM-154).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps without settling: the screen shows a spinner while the choice is
  /// open, and a [CircularProgressIndicator] never stops animating.
  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Widget app(AssessmentProvider provider) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>(create: (_) => _TestChildProvider()),
      ChangeNotifierProvider<AssessmentProvider>.value(value: provider),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const PostAssessmentProgressScreen(),
    ),
  );

  testWidgets('an interrupted run is offered back to the parent', (
    tester,
  ) async {
    final provider = _ScriptedAssessmentProvider(resumable: _openRun());
    await tester.pumpWidget(app(provider));
    await pumpFrames(tester);

    expect(find.text('Pick up where you left off?'), findsOneWidget);
    // The prompt names the progress rather than the interruption.
    expect(find.textContaining('covered 2 of 4 activities'), findsOneWidget);
    expect(find.text(ResumeAssessmentDialog.continueLabel), findsOneWidget);
    expect(find.text(ResumeAssessmentDialog.startOverLabel), findsOneWidget);
    expect(
      provider.startAttempts,
      0,
      reason: 'no new run may be minted while the old one is being offered',
    );
  });

  testWidgets('Continue adopts the run and skips the games already played', (
    tester,
  ) async {
    final provider = _ScriptedAssessmentProvider(resumable: _openRun());
    await tester.pumpWidget(app(provider));
    await pumpFrames(tester);

    await tester.tap(find.text(ResumeAssessmentDialog.continueLabel));
    await pumpFrames(tester);

    expect(provider.resumedRuns, ['run-open']);
    expect(provider.startAttempts, 0);
    // The child lands on the third activity, not the first.
    expect(find.text('Post-Assessment — Game 3 of 4'), findsOneWidget);
    expect(find.text('My Turn, Your Turn'), findsOneWidget);
  });

  testWidgets('Start over begins a clean run from the first activity', (
    tester,
  ) async {
    final provider = _ScriptedAssessmentProvider(resumable: _openRun());
    await tester.pumpWidget(app(provider));
    await pumpFrames(tester);

    await tester.tap(find.text(ResumeAssessmentDialog.startOverLabel));
    await pumpFrames(tester);

    expect(provider.resumedRuns, isEmpty);
    expect(provider.startAttempts, 1);
    expect(find.text('Post-Assessment — Game 1 of 4'), findsOneWidget);
    expect(find.text('Copy Me'), findsOneWidget);
  });

  testWidgets('with nothing to resume the flow starts as it always did', (
    tester,
  ) async {
    final provider = _ScriptedAssessmentProvider();
    await tester.pumpWidget(app(provider));
    await pumpFrames(tester);

    expect(find.text('Pick up where you left off?'), findsNothing);
    expect(provider.startAttempts, 1);
    expect(find.text('Play!'), findsOneWidget);
    expect(find.text('Post-Assessment — Game 1 of 4'), findsOneWidget);
  });
}

OpenAssessmentRun _openRun({
  List<String> played = const ['copy_me', 'do_what_i_say'],
}) => OpenAssessmentRun(
  id: 'run-open',
  childId: 'child-1',
  type: 'post',
  startedAt: DateTime(2026, 8, 16, 10),
  sessions: [
    for (final gameId in played)
      GameplaySession(
        id: 'stored-$gameId',
        childId: 'child-1',
        assessmentRunId: 'run-open',
        gameId: gameId,
        context: 'post_assessment',
        score: 7,
        totalItems: 10,
        errorCount: 3,
        totalResponseTimeMs: 12000,
        startedAt: DateTime(2026, 8, 16, 10),
        endedAt: DateTime(2026, 8, 16, 10, 5),
      ),
  ],
);

/// Stands in for the provider's database work: which run is resumable, and
/// which of the two paths the screen took.
class _ScriptedAssessmentProvider extends AssessmentProvider {
  _ScriptedAssessmentProvider({this.resumable});

  final OpenAssessmentRun? resumable;
  final List<String> resumedRuns = [];
  int startAttempts = 0;
  String? runId;

  @override
  Future<OpenAssessmentRun?> findResumableRun({
    required String childId,
    required String type,
    DateTime? now,
  }) async => resumable;

  @override
  void resumeAssessmentRun(OpenAssessmentRun run) {
    resumedRuns.add(run.id);
    runId = run.id;
  }

  @override
  Future<String> startAssessmentRun({
    required String childId,
    required String type,
  }) async {
    startAttempts++;
    runId = 'run-$startAttempts';
    return runId!;
  }

  @override
  String? get currentAssessmentRunId => runId;
}

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
