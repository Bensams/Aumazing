import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/post_assessment/post_assessment_progress_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';

final _childProfile = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Test',
  birthDate: DateTime(2022, 4, 20),
  avatar: 'bear',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

/// Stands in for the provider's run creation, which normally writes to
/// SQLite. Records how many attempts were made so a Retry is observable.
class _ScriptedAssessmentProvider extends AssessmentProvider {
  _ScriptedAssessmentProvider({this.failFirstAttempt = false});

  final bool failFirstAttempt;
  int startAttempts = 0;
  String? runId;

  @override
  Future<String> startAssessmentRun({
    required String childId,
    required String type,
  }) async {
    startAttempts++;
    if (failFirstAttempt && startAttempts == 1) {
      throw StateError('no database');
    }
    runId = 'run-$startAttempts';
    return runId!;
  }

  @override
  String? get currentAssessmentRunId => runId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(AssessmentProvider provider) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(),
      ),
      ChangeNotifierProvider<AssessmentProvider>.value(value: provider),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const PostAssessmentProgressScreen(),
    ),
  );

  testWidgets('no Play button is shown until the run exists', (tester) async {
    final provider = _ScriptedAssessmentProvider();
    await tester.pumpWidget(app(provider));

    // First frame: the run creation has not completed yet.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Play!'), findsNothing);

    await tester.pumpAndSettle();

    expect(provider.startAttempts, 1);
    expect(find.text('Play!'), findsOneWidget);
  });

  testWidgets('a failed initialization offers a Retry that recovers', (
    tester,
  ) async {
    final provider = _ScriptedAssessmentProvider(failFirstAttempt: true);
    await tester.pumpWidget(app(provider));
    await tester.pumpAndSettle();

    expect(find.text('Play!'), findsNothing);
    expect(find.text(AssessmentLabels.couldNotStart), findsOneWidget);
    expect(find.text(AssessmentLabels.tryAgain), findsOneWidget);

    await tester.tap(find.text(AssessmentLabels.tryAgain));
    await tester.pumpAndSettle();

    expect(provider.startAttempts, 2);
    expect(find.text(AssessmentLabels.tryAgain), findsNothing);
    expect(find.text('Play!'), findsOneWidget);
  });
}

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
