import 'dart:async';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/history/history_models.dart';
import 'package:aumazing/features/history/parent_history_screen.dart';
import 'package:aumazing/model/assessment_run_record.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/services/active_games_service.dart';
import 'package:aumazing/services/learning_path_service.dart';
import 'package:aumazing/services/parent_history_service.dart';
import 'package:aumazing/services/report_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  // The screen's _load reads ActiveGamesService before loadHistory. The
  // cache is read-only, so pre-warm it via the deterministic offline
  // fallback (no Supabase is initialized in tests) before any pump.
  setUp(() async {
    await ActiveGamesService.instance.activeGameIds;
  });
  tearDown(() => ActiveGamesService.instance.invalidateCache());

  group('ParentHistoryScreen', () {
    testWidgets('shows a loading spinner while history is being loaded', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final gate = Completer<void>();
      final service = _FakeHistoryService(summary: _emptySummary(), gate: gate);

      await tester.pumpWidget(
        _buildApp(
          childProvider: _TestChildProvider(initialProfile: _profile),
          assessmentProvider: _TestAssessmentProvider(),
          screen: ParentHistoryScreen(
            childId: 'child-1',
            historyService: service,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading history...'), findsOneWidget);

      // Let the load finish and confirm the spinner is replaced.
      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Loading history...'), findsNothing);
    });

    testWidgets('renders empty states when there is no history', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildApp(
          childProvider: _TestChildProvider(initialProfile: _profile),
          assessmentProvider: _TestAssessmentProvider(),
          screen: ParentHistoryScreen(
            childId: 'child-1',
            historyService: _FakeHistoryService(summary: _emptySummary()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          'No assessments yet. Complete a pre-assessment to see '
          'results here.',
        ),
        findsOneWidget,
      );
      expect(find.text('No completed modules yet.'), findsOneWidget);
      expect(find.text('No practice sessions yet.'), findsOneWidget);
      expect(find.text('Progress Comparison'), findsNothing);
    });

    testWidgets('shows an error card and retries successfully', (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeHistoryService(
        summary: _populatedSummary(),
        failFirst: 1,
      );

      await tester.pumpWidget(
        _buildApp(
          childProvider: _TestChildProvider(initialProfile: _profile),
          assessmentProvider: _TestAssessmentProvider(),
          screen: ParentHistoryScreen(
            childId: 'child-1',
            historyService: service,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(service.loadCalls, 1);
      expect(
        find.text('We couldn’t load your child’s history. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pump();
      await tester.pump();

      expect(service.loadCalls, 2);
      expect(find.text('Assessment History'), findsOneWidget);
      expect(find.text('Try Again'), findsNothing);
    });

    testWidgets('shows unauthorized when the child is not on the account', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final unrelated = ChildProfile(
        id: 'child-other',
        userId: 'user-1',
        displayName: 'Other',
        birthDate: DateTime(2022, 4, 20),
        avatar: 'bear',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      await tester.pumpWidget(
        _buildApp(
          childProvider: _TestChildProvider(
            initialProfile: unrelated,
            children: [unrelated],
          ),
          assessmentProvider: _TestAssessmentProvider(),
          screen: ParentHistoryScreen(
            childId: 'child-1',
            historyService: _FakeHistoryService(summary: _populatedSummary()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text('This child is not available on your account.'),
        findsOneWidget,
      );
      expect(find.text('Assessment History'), findsNothing);
      expect(find.text('Practice History'), findsNothing);
    });

    testWidgets('renders a populated summary with runs, skills, comparison, '
        'My Path, and practice', (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildApp(
          childProvider: _TestChildProvider(initialProfile: _profile),
          assessmentProvider: _TestAssessmentProvider(),
          screen: ParentHistoryScreen(
            childId: 'child-1',
            historyService: _FakeHistoryService(summary: _populatedSummary()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Flow config chips from the run games.
      expect(find.text('3-round flow'), findsOneWidget);
      expect(find.text('Legacy 4-round'), findsWidgets);

      // Skill chip and recommendation.
      expect(find.text('Communication: Strength'), findsOneWidget);
      expect(find.text('Recommended: Emotions Module'), findsOneWidget);

      // Pre/post type badges.
      expect(find.text('PRE'), findsOneWidget);
      expect(find.text('POST'), findsOneWidget);

      // Progress comparison delta (positive sign).
      expect(find.text('+25 points overall'), findsOneWidget);

      // Practice row date is formatted exactly.
      expect(find.text('Aug 27, 2026'), findsOneWidget);

      // My Path completion card.
      expect(find.text('My Path'), findsOneWidget);
      expect(find.text('3 games on the path'), findsOneWidget);
      expect(find.text('Completed'), findsWidgets);
    });

    testWidgets('shows the three status pill labels', (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final summary = HistorySummary(
        runs: [
          _runHistory(
            id: 'r-completed',
            type: 'pre',
            status: 'completed',
            startedAt: DateTime(2026, 8, 1),
            completedAt: DateTime(2026, 8, 2),
          ),
          _runHistory(
            id: 'r-progress',
            type: 'post',
            status: 'in_progress',
            startedAt: DateTime(2026, 8, 5),
          ),
          _runHistory(
            id: 'r-incomplete',
            type: 'pre',
            status: 'incomplete',
            startedAt: DateTime(2026, 8, 8),
          ),
        ],
        completedModules: const [],
        practiceSessions: const [],
        comparison: null,
      );

      await tester.pumpWidget(
        _buildApp(
          childProvider: _TestChildProvider(initialProfile: _profile),
          assessmentProvider: _TestAssessmentProvider(),
          screen: ParentHistoryScreen(
            childId: 'child-1',
            historyService: _FakeHistoryService(summary: summary),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Incomplete'), findsOneWidget);
    });

    testWidgets('wraps long status and result labels on a narrow card', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final run = _runHistory(
        id: 'run-narrow',
        type: 'post',
        status: 'in_progress',
        startedAt: DateTime(2026, 8, 8),
        games: [
          _game(
            gameId: 'long_game',
            gameName: 'Emotion recognition and communication practice',
            score: 8,
            errorCount: 2,
            configLabel:
                'Extended multi-round communication and emotional regulation flow',
            endedAt: DateTime(2026, 8, 8, 9),
          ),
        ],
        skills: const [
          SkillBreakdownEntry(
            area: 'Social communication and emotional awareness',
            label: 'Needs support',
          ),
        ],
      );

      await tester.pumpWidget(
        _buildApp(
          childProvider: _TestChildProvider(initialProfile: _profile),
          assessmentProvider: _TestAssessmentProvider(),
          screen: ParentHistoryScreen(
            childId: 'child-1',
            historyService: _FakeHistoryService(
              summary: HistorySummary(
                runs: [run],
                completedModules: [
                  CompletedModuleRecord(
                    moduleId: 'long-module',
                    moduleName:
                        'A very long completed module name for narrow screens',
                    completedAt: DateTime(2026, 8, 9),
                    status: 'completed',
                    level: 3,
                    maxLevel: 5,
                    source: 'module_progress',
                    gameCount: 0,
                  ),
                ],
                practiceSessions: const [],
                comparison: null,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('In progress'), findsOneWidget);
      expect(
        find.text(
          'Extended multi-round communication and emotional regulation flow',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Social communication and emotional awareness: Needs support'),
        findsOneWidget,
      );
      expect(find.text('Completed'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Post-assessment')).overflow,
        TextOverflow.ellipsis,
      );
      expect(
        tester
            .widget<Text>(
              find.text(
                'A very long completed module name for narrow screens',
              ),
            )
            .overflow,
        TextOverflow.ellipsis,
      );

      final card = tester.getRect(
        find.byKey(const ValueKey('history-run-run-narrow')),
      );
      for (final label in [
        'In progress',
        'Extended multi-round communication and emotional regulation flow',
        'Social communication and emotional awareness: Needs support',
      ]) {
        final labelRect = tester.getRect(find.text(label));
        expect(card.contains(labelRect.topLeft), isTrue, reason: label);
        expect(card.contains(labelRect.bottomRight), isTrue, reason: label);
      }
      final moduleLabel =
          'A very long completed module name for narrow screens';
      final moduleCard = tester.getRect(
        find.ancestor(
          of: find.text(moduleLabel),
          matching: find.byType(AppCard),
        ).first,
      );
      final moduleStatus = tester.getRect(find.text('Completed'));
      final moduleTitleRect = tester.getRect(find.text(moduleLabel));
      expect(moduleCard.contains(moduleTitleRect.topLeft), isTrue);
      expect(moduleCard.contains(moduleTitleRect.bottomRight), isTrue);
      expect(moduleCard.contains(moduleStatus.topLeft), isTrue);
      expect(moduleCard.contains(moduleStatus.bottomRight), isTrue);
    });

    testWidgets('shows a minus sign on a negative delta', (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pre = _runHistory(
        id: 'run-pre',
        type: 'pre',
        status: 'completed',
        startedAt: DateTime(2026, 8, 1),
        completedAt: DateTime(2026, 8, 2),
        overallAccuracy: 0.8,
      );
      final post = _runHistory(
        id: 'run-post',
        type: 'post',
        status: 'completed',
        startedAt: DateTime(2026, 8, 10),
        completedAt: DateTime(2026, 8, 11),
        overallAccuracy: 0.5,
      );
      final summary = HistorySummary(
        runs: [pre, post],
        completedModules: const [],
        practiceSessions: const [],
        comparison: ProgressComparison(pre: pre, post: post, areas: const []),
      );

      await tester.pumpWidget(
        _buildApp(
          childProvider: _TestChildProvider(initialProfile: _profile),
          assessmentProvider: _TestAssessmentProvider(),
          screen: ParentHistoryScreen(
            childId: 'child-1',
            historyService: _FakeHistoryService(summary: summary),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('-30 points overall'), findsOneWidget);
    });

    testWidgets('renders completed module cards with dates and levels', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final summary = HistorySummary(
        runs: const [],
        completedModules: [
          CompletedModuleRecord(
            moduleId: 'my_path',
            moduleName: 'My Path',
            completedAt: DateTime(2026, 8, 25, 10),
            status: 'completed',
            level: 0,
            maxLevel: 0,
            source: 'my_path',
            gameCount: 3,
          ),
          CompletedModuleRecord(
            moduleId: 'emotions_module',
            moduleName: 'Emotions Module',
            completedAt: DateTime(2026, 6, 2, 10),
            status: 'completed',
            level: 2,
            maxLevel: 5,
            source: 'module_progress',
            gameCount: 0,
          ),
        ],
        practiceSessions: const [],
        comparison: null,
      );

      await tester.pumpWidget(
        _buildApp(
          childProvider: _TestChildProvider(initialProfile: _profile),
          assessmentProvider: _TestAssessmentProvider(),
          screen: ParentHistoryScreen(
            childId: 'child-1',
            historyService: _FakeHistoryService(summary: summary),
          ),
        ),
      );
      await tester.pump();

      // My Path card: name, completion date, and path length.
      expect(find.text('My Path'), findsOneWidget);
      expect(find.text('3 games on the path'), findsOneWidget);
      expect(find.text('Aug 25, 2026'), findsOneWidget);
      // Recommendation module card: name, date, and level progress.
      expect(find.text('Emotions Module'), findsOneWidget);
      expect(find.text('Level 2 of 5'), findsOneWidget);
      expect(find.text('Jun 2, 2026'), findsOneWidget);
      expect(find.text('Completed'), findsNWidgets(2));
    });

    testWidgets(
      'shares the loaded snapshot once, shows busy, and does not reload',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(960, 540));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final summary = _populatedSummary();
        final history = _FakeHistoryService(summary: summary);
        final gate = Completer<void>();
        final reports = _FakeReportSharer(gate: gate);
        await tester.pumpWidget(
          _buildApp(
            childProvider: _TestChildProvider(initialProfile: _profile),
            assessmentProvider: _TestAssessmentProvider(),
            screen: ParentHistoryScreen(
              childId: 'child-1',
              childName: 'Test',
              historyService: history,
              reportPdfSharer: reports,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final button = tester.widget<IconButton>(
          find.byKey(const ValueKey('share-history-pdf')),
        );
        button.onPressed!();
        button.onPressed!();
        await tester.pump();

        expect(reports.historyCalls, 1);
        expect(identical(reports.summary, summary), isTrue);
        expect(reports.childName, 'Test');
        expect(history.loadCalls, 1);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        gate.complete();
        await tester.pump();
        expect(find.byKey(const ValueKey('share-history-pdf')), findsOneWidget);
        expect(history.loadCalls, 1);
      },
    );

    testWidgets('share failure is friendly and restores the action', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final reports = _FakeReportSharer(fail: true);
      await tester.pumpWidget(
        _buildApp(
          childProvider: _TestChildProvider(initialProfile: _profile),
          assessmentProvider: _TestAssessmentProvider(),
          screen: ParentHistoryScreen(
            childId: 'child-1',
            historyService: _FakeHistoryService(summary: _emptySummary()),
            reportPdfSharer: reports,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('share-history-pdf')));
      await tester.pump();

      expect(
        find.text(
          'We couldn\u2019t create or share the PDF. Please try again.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('share-history-pdf')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('share-history-pdf')));
      await tester.pump();
      expect(reports.historyCalls, 2);
    });
  });
}

Widget _buildApp({
  required ChildProvider childProvider,
  required AssessmentProvider assessmentProvider,
  required ParentHistoryScreen screen,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>.value(value: childProvider),
      ChangeNotifierProvider<AssessmentProvider>.value(
        value: assessmentProvider,
      ),
    ],
    child: MaterialApp(theme: AppTheme.light, home: screen),
  );
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider({
    required ChildProfile initialProfile,
    List<ChildProfile>? children,
  }) : _profile = initialProfile,
       _children = children ?? [initialProfile],
       super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  final ChildProfile _profile;
  final List<ChildProfile> _children;

  @override
  ChildProfile? get profile => _profile;

  @override
  List<ChildProfile> get children => _children;

  @override
  bool get musicEnabled => true;

  @override
  bool get vibrationEnabled => true;

  @override
  Future<void> loadProfile() async {}

  @override
  Future<void> updateComfortSettings({
    bool? musicEnabled,
    double? musicVolume,
    String? musicCategory,
    double? sfxVolume,
    bool? vibrationEnabled,
    double? animationIntensity,
    double? promptSpeed,
    bool? sensoryPreferencesSet,
  }) async {}
}

class _TestAssessmentProvider extends AssessmentProvider {
  @override
  bool get hasPreAssessment => false;

  @override
  String? get recommendedModuleName => null;

  @override
  int get recommendedLevel => 1;

  @override
  Future<void> loadAssessments(String childId) async {}
}

class _FakeHistoryService extends ParentHistoryService {
  _FakeHistoryService({this.summary, this.failFirst = 0, this.gate});

  final HistorySummary? summary;
  final int failFirst;
  final Completer<void>? gate;
  int loadCalls = 0;

  @override
  Future<HistorySummary> loadHistory({
    required String childId,
    required List<LearningPathEntry> path,
    required Set<String> pathCompletedGameIds,
  }) async {
    loadCalls += 1;
    if (gate != null) {
      await gate!.future;
    }
    if (loadCalls <= failFirst) {
      throw StateError('simulated load failure');
    }
    return summary ?? _emptySummary();
  }
}

class _FakeReportSharer implements ReportPdfSharer {
  _FakeReportSharer({this.gate, this.fail = false});

  final Completer<void>? gate;
  final bool fail;
  int historyCalls = 0;
  HistorySummary? summary;
  String? childName;

  @override
  Future<void> shareHistoryReport({
    required HistorySummary summary,
    required String childDisplayName,
  }) async {
    historyCalls += 1;
    this.summary = summary;
    childName = childDisplayName;
    if (fail) throw StateError('simulated share failure');
    await gate?.future;
  }

  @override
  Future<void> shareAssessmentReport({
    required AssessmentResultViewModel model,
    required String childDisplayName,
  }) => throw UnimplementedError();
}

class _FakeSupabaseAuthClient implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Future<AuthResponse> signInAnonymously() async => AuthResponse();

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResponse> linkIdentityWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
    String? emailRedirectTo,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UserResponse> updateUser(UserAttributes attributes) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResponse> verifyEmailChange({
    required String email,
    required String token,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ResendResponse> resendEmailChange(String email) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResponse> verifyOTP({
    required OtpType type,
    String? token,
    String? tokenHash,
    String? phone,
    String? email,
    String? redirectTo,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ResendResponse> resend({
    required OtpType type,
    String? email,
    String? phone,
    String? emailRedirectTo,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> resetPasswordForEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResponse> refreshSession([String? refreshToken]) {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {}
}

HistorySummary _emptySummary() => HistorySummary(
  runs: const [],
  completedModules: const [],
  practiceSessions: const [],
  comparison: null,
);

AssessmentRunHistory _runHistory({
  required String id,
  required String type,
  required String status,
  required DateTime startedAt,
  DateTime? completedAt,
  List<RunGameRecord> games = const [],
  double overallAccuracy = 0.0,
  List<SkillBreakdownEntry> skills = const [],
  String? recommendedModule,
  String? overallSummary,
}) => AssessmentRunHistory(
  run: AssessmentRunRecord(
    id: id,
    childId: 'child-1',
    type: type,
    status: status,
    startedAt: startedAt,
    completedAt: completedAt,
  ),
  games: games,
  overallAccuracy: overallAccuracy,
  skills: skills,
  recommendedModule: recommendedModule,
  overallSummary: overallSummary,
);

RunGameRecord _game({
  required String gameId,
  required String gameName,
  required int score,
  required int errorCount,
  double? accuracy,
  String? configLabel,
  required DateTime endedAt,
}) => RunGameRecord(
  gameId: gameId,
  gameName: gameName,
  score: score,
  totalItems: 10,
  errorCount: errorCount,
  accuracy: accuracy ?? (score / (score + errorCount)),
  configLabel: configLabel,
  endedAt: endedAt,
);

HistorySummary _populatedSummary() {
  final preRun = _runHistory(
    id: 'run-a',
    type: 'pre',
    status: 'completed',
    startedAt: DateTime(2026, 8, 1, 9),
    completedAt: DateTime(2026, 8, 2, 9),
    games: [
      _game(
        gameId: 'match_it',
        gameName: 'Match It',
        score: 8,
        errorCount: 2,
        accuracy: 0.8,
        configLabel: '3-round flow',
        endedAt: DateTime(2026, 8, 1, 9, 5),
      ),
      _game(
        gameId: 'copy_me',
        gameName: 'Copy Me',
        score: 5,
        errorCount: 5,
        accuracy: 0.5,
        configLabel: 'Legacy 4-round',
        endedAt: DateTime(2026, 8, 1, 10, 5),
      ),
    ],
    overallAccuracy: 0.65,
    skills: const [
      SkillBreakdownEntry(area: 'Communication', label: 'Strength'),
    ],
    recommendedModule: 'Emotions Module',
    overallSummary: 'Great progress!',
  );

  final postRun = _runHistory(
    id: 'run-b',
    type: 'post',
    status: 'completed',
    startedAt: DateTime(2026, 8, 10, 9),
    completedAt: DateTime(2026, 8, 11, 9),
    games: [
      _game(
        gameId: 'match_it',
        gameName: 'Match It',
        score: 9,
        errorCount: 1,
        accuracy: 0.9,
        configLabel: 'Legacy 4-round',
        endedAt: DateTime(2026, 8, 10, 9, 5),
      ),
    ],
    overallAccuracy: 0.9,
    skills: const [
      SkillBreakdownEntry(area: 'Communication', label: 'Emerging'),
    ],
  );

  return HistorySummary(
    runs: [preRun, postRun],
    completedModules: [
      CompletedModuleRecord(
        moduleId: 'my_path',
        moduleName: 'My Path',
        completedAt: DateTime(2026, 8, 25, 10),
        status: 'completed',
        level: 0,
        maxLevel: 0,
        source: 'my_path',
        gameCount: 3,
      ),
    ],
    practiceSessions: [
      GameplaySession(
        id: 'p1',
        childId: 'child-1',
        gameId: 'match_it',
        context: 'practice',
        score: 10,
        totalItems: 10,
        errorCount: 0,
        totalResponseTimeMs: 3000,
        startedAt: DateTime(2026, 8, 27, 9),
        endedAt: DateTime(2026, 8, 27, 9, 5),
      ),
    ],
    comparison: ProgressComparison(
      pre: preRun,
      post: postRun,
      areas: const [
        AreaComparisonRow(
          area: 'Communication',
          before: 'Strength',
          after: 'Emerging',
        ),
      ],
    ),
  );
}
