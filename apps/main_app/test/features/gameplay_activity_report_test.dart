import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/home/gameplay_report_screen.dart';
import 'package:aumazing/features/home/home_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/progress_provider.dart';
import 'package:aumazing/services/entitlement_service.dart';
import 'package:aumazing/services/tour_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EntitlementService.instance.debugSetRealPremium(false);
    TourService.instance.markParentTourSeen();
  });

  tearDown(() {
    EntitlementService.instance.debugSetRealPremium(false);
  });

  testWidgets('report renders the selected game and detailed telemetry', (
    tester,
  ) async {
    final session = _session(
      id: 'report-detail',
      gameId: 'trace_it',
      score: 7,
      totalItems: 9,
      totalResponseTimeMs: 45678,
      avgResponseTime: 4.5,
      avgValidResponseTime: 3.2,
      taskCompletionRate: .78,
      promptDependencyScore: .21,
      improvementScore: .42,
      consistencyScore: .88,
      sensoryCondition: 'quiet-room',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: GameplayReportScreen(
          session: session,
          palette: GamePalettes.neutral,
        ),
      ),
    );

    expect(find.text('Gameplay report'), findsOneWidget);
    expect(find.text('Trace it'), findsOneWidget);
    expect(find.text('7/9'), findsOneWidget);
    expect(find.text('78%'), findsNWidgets(2));
    expect(find.text('4.5s'), findsOneWidget);
    expect(find.text('3.2s'), findsOneWidget);
    expect(find.text('21%'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(find.text('quiet-room'), findsOneWidget);
  });

  testWidgets('free activity keeps summary and opens Premium upgrade', (
    tester,
  ) async {
    final session = _session(
      id: 'free-activity',
      gameId: 'copy_me',
      score: 8,
      totalItems: 10,
      endedAt: DateTime.now().subtract(const Duration(minutes: 2)),
    );

    await tester.pumpWidget(_homeApp(session));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Copy me'), findsOneWidget);
    expect(find.text('8/10 correct · 1m 5s'), findsOneWidget);
    final item = find.byKey(const ValueKey('recentActivityItem-free-activity'));
    expect(item, findsOneWidget);

    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Aumazing Premium'), findsOneWidget);
    expect(find.text('Gameplay report'), findsNothing);
  });

  testWidgets('Premium activity opens report for the tapped session', (
    tester,
  ) async {
    final session = _session(
      id: 'premium-activity',
      gameId: 'match_it',
      score: 6,
      totalItems: 8,
      totalResponseTimeMs: 12345,
      avgResponseTime: 9.9,
      avgValidResponseTime: 8.8,
      taskCompletionRate: .66,
      sensoryCondition: 'blue-lights',
      endedAt: DateTime.now().subtract(const Duration(minutes: 2)),
    );
    EntitlementService.instance.debugSetRealPremium(true);

    await tester.pumpWidget(_homeApp(session));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(EntitlementService.instance.isPremium, isTrue);
    final item = find.byKey(
      const ValueKey('recentActivityItem-premium-activity'),
    );
    await tester.ensureVisible(item);
    tester.widget<InkWell>(item).onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(EntitlementService.instance.isPremium, isTrue);
    expect(tester.takeException(), isNull);
    expect(
      find.byType(GameplayReportScreen),
      findsOneWidget,
      reason: 'Premium tap should push the detailed report',
    );
    expect(find.text('Match it'), findsOneWidget);
    expect(find.text('6/8'), findsOneWidget);
    expect(find.text('9.9s'), findsOneWidget);
    expect(find.text('8.8s'), findsOneWidget);
    expect(find.text('66%'), findsOneWidget);
    expect(find.text('blue-lights'), findsOneWidget);
  });
}

GameplaySession _session({
  required String id,
  required String gameId,
  required int score,
  required int totalItems,
  int totalResponseTimeMs = 65000,
  double avgResponseTime = 1.0,
  double avgValidResponseTime = 0.8,
  double taskCompletionRate = .5,
  double promptDependencyScore = .1,
  double improvementScore = .1,
  double consistencyScore = .5,
  String? sensoryCondition,
  DateTime? endedAt,
}) {
  final end = endedAt ?? DateTime(2026, 8, 20, 10, 5);
  return GameplaySession(
    id: id,
    childId: 'child-1',
    gameId: gameId,
    context: 'practice',
    startedAt: end.subtract(const Duration(minutes: 1, seconds: 5)),
    endedAt: end,
    score: score,
    totalItems: totalItems,
    errorCount: 2,
    totalResponseTimeMs: totalResponseTimeMs,
    avgResponseTime: avgResponseTime,
    avgValidResponseTime: avgValidResponseTime,
    taskCompletionRate: taskCompletionRate,
    promptDependencyScore: promptDependencyScore,
    improvementScore: improvementScore,
    consistencyScore: consistencyScore,
    sensoryCondition: sensoryCondition,
  );
}

Widget _homeApp(GameplaySession session) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>.value(value: _ChildFixture()),
      ChangeNotifierProvider<ProgressProvider>.value(
        value: _ProgressFixture(session),
      ),
      ChangeNotifierProvider<AssessmentProvider>.value(
        value: _AssessmentFixture(),
      ),
      Provider<AudioService>(create: (_) => _AudioFixture()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: HomeScreen(
        authService: AuthService(supabaseAuth: _AuthFixture()),
        syncStates: const Stream.empty(),
      ),
    ),
  );
}

final _profile = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Test Child',
  birthDate: DateTime(2022, 1, 1),
  avatar: 'bear',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

class _ChildFixture extends ChildProvider {
  _ChildFixture()
    : super(authService: AuthService(supabaseAuth: _AuthFixture()));

  @override
  ChildProfile? get profile => _profile;

  @override
  Future<void> loadProfile() async {}
}

class _ProgressFixture extends ProgressProvider {
  _ProgressFixture(this.session);
  final GameplaySession session;

  @override
  List<GameplaySession> get recentSessions => [session];

  @override
  int get totalSessions => 1;

  @override
  Future<void> loadProgress(String childId) async {}
}

class _AssessmentFixture extends AssessmentProvider {
  @override
  Future<void> loadAssessments(String childId) async {}
}

class _AudioFixture extends AudioService {
  _AudioFixture() : super(config: const AudioConfig());

  @override
  bool get isMusicPlaying => false;

  @override
  void updateConfig(AudioConfig config) {}

  @override
  Future<void> resumeMusic() async {}

  @override
  Future<void> playRandomMusic(List<String> trackNames) async {}

  @override
  Future<void> playCategoryMusic(
    String? categoryKey, {
    bool restart = false,
  }) async {}

  @override
  Future<void> pauseMusic() async {}

  @override
  Future<void> stopMusic() async {}

  @override
  Future<void> playMusic(String trackName) async {}

  @override
  Future<void> playSfx(String sfxName, {double volumeScale = 1.0}) async {}

  @override
  Future<void> playButtonTap() async {}

  @override
  Future<void> dispose() async {}
}

class _AuthFixture implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
