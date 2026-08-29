import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/features/games/session_recording.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/progress_provider.dart';
import 'package:aumazing/services/assessment_service.dart';
import 'package:aumazing/services/rubric/rubric_result.dart';

/// The completion guard's escape surface is a real [HomeScreen] by default; a
/// test host overrides it so the timeout test can assert the escape without
/// dragging in the whole lobby provider stack.
class _FallbackLanding extends StatelessWidget {
  const _FallbackLanding();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('landing'));
}

/// Inert defaults for every [AssessmentGateway] member, so the concrete fakes
/// below only need to override [recordSession].
class _BaseGateway implements AssessmentGateway {
  @override
  Future<String> startAssessmentRun({
    required String childId,
    required String type,
  }) async => 'run-1';

  @override
  Future<void> completeAssessmentRun(String runId) async {}

  @override
  Future<int> abandonOpenRuns(String childId) async => 0;

  @override
  Future<OpenAssessmentRun?> openAssessmentRun(String childId) async => null;

  @override
  Future<AssessmentResult> createAssessmentResult({
    required String childId,
    required String type,
    required String gameId,
    required List<GameplaySession> sessions,
    String? assessmentRunId,
    RubricResult? rubric,
  }) async => throw UnimplementedError();

  @override
  Future<void> saveModuleRecommendation({
    required String childId,
    required String assessmentRunId,
    required String moduleId,
    required String moduleName,
    required int startingLevel,
    double? confidence,
    String? rationale,
  }) async {}

  @override
  Future<void> saveAssessmentComparison({
    required String childId,
    required String preAssessmentId,
    required String postAssessmentId,
    double? accuracyImprovement,
    int? responseTimeImprovementMs,
    double? overallImprovementPercent,
    String? summary,
  }) async {}

  @override
  Map<String, dynamic> recommendModule(List<AssessmentResult> preResults) => {};

  @override
  Map<String, dynamic> compareAssessments({
    required List<AssessmentResult> preResults,
    required List<AssessmentResult> postResults,
  }) => {};

  @override
  Future<GameplaySession> recordSession({
    required String childId,
    required String gameId,
    required String context,
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required DateTime startedAt,
    String? assessmentRunId,
    GameSessionMetrics? analytics,
    String? configurationVersionOverride,
    bool bgMusicEnabled = true,
    bool hapticFeedbackEnabled = true,
    bool applySessionSensoryDefaults = true,
  }) async => throw UnimplementedError();
}

/// Gateway whose writes always fail, so [GameSessionRecording.record] walks
/// the retry path a real storage outage would produce.
class _ThrowingGateway extends _BaseGateway {
  @override
  Future<GameplaySession> recordSession({
    required String childId,
    required String gameId,
    required String context,
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required DateTime startedAt,
    String? assessmentRunId,
    GameSessionMetrics? analytics,
    String? configurationVersionOverride,
    bool bgMusicEnabled = true,
    bool hapticFeedbackEnabled = true,
    bool applySessionSensoryDefaults = true,
  }) async {
    throw Exception('gateway down');
  }

  @override
  Future<void> saveModuleRecommendation({
    required String childId,
    required String assessmentRunId,
    required String moduleId,
    required String moduleName,
    required int startingLevel,
    double? confidence,
    String? rationale,
  }) async {}

  @override
  Future<void> saveAssessmentComparison({
    required String childId,
    required String preAssessmentId,
    required String postAssessmentId,
    double? accuracyImprovement,
    int? responseTimeImprovementMs,
    double? overallImprovementPercent,
    String? summary,
  }) async {}
}

/// Gateway whose writes always succeed, so no retry dialog interrupts the
/// completion chain.
class _SucceedingGateway extends _BaseGateway {
  @override
  Future<GameplaySession> recordSession({
    required String childId,
    required String gameId,
    required String context,
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required DateTime startedAt,
    String? assessmentRunId,
    GameSessionMetrics? analytics,
    String? configurationVersionOverride,
    bool bgMusicEnabled = true,
    bool hapticFeedbackEnabled = true,
    bool applySessionSensoryDefaults = true,
  }) async {
    return GameplaySession(
      id: 'session-1',
      childId: childId,
      assessmentRunId: assessmentRunId,
      gameId: gameId,
      context: context,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      totalResponseTimeMs: totalResponseTimeMs,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 2)),
    );
  }
}

/// A minimal [GameCompletionGuard] host mirroring the anong completion chain
/// (latch -> record -> reward marker -> choice marker), so the contract is
/// exercised on the real record + real guard without a Flame game.
class _GuardHost extends StatefulWidget {
  const _GuardHost({required this.gateway});

  final AssessmentGateway gateway;

  @override
  State<_GuardHost> createState() => _GuardHostState();
}

class _GuardHostState extends State<_GuardHost> with GameCompletionGuard {
  bool? _firstLatch;
  bool? _secondLatch;
  bool _rewardShown = false;
  bool _choiceShown = false;

  Future<void> _complete() async {
    final first = beginCompletion();
    setState(() {
      if (_firstLatch == null) {
        _firstLatch = first;
      } else {
        _secondLatch = first;
      }
    });
    if (!first) return;

    try {
      await GameSessionRecording.record(
        context,
        childId: 'child-1',
        gameId: 'anong_nararamdaman',
        assessmentContext: 'practice',
        score: 8,
        totalItems: 10,
        errorCount: 2,
        totalResponseTimeMs: 12000,
        startedAt: DateTime(2026, 8, 1, 9),
      );
    } catch (_) {
      // Last-resort net; record already swallows its own failures.
    }
    if (!mounted) return;

    armCompletionWatchdog();
    setState(() => _rewardShown = true);
  }

  /// Reward overlay's onComplete: the choice is about to appear, so the
  /// watchdog stands down exactly as [GameEndChoiceDialog.show]'s onShown does.
  void _rewardComplete() {
    cancelCompletionWatchdog();
    setState(() => _choiceShown = true);
  }

  @override
  Widget completionFallbackSurface() => const _FallbackLanding();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(onPressed: _complete, child: const Text('complete')),
          TextButton(
            onPressed: () => beginCompletion(),
            child: const Text('latch-only'),
          ),
          if (_rewardShown)
            TextButton(onPressed: _rewardComplete, child: const Text('REWARD')),
          if (_choiceShown) const Text('CHOICE'),
          Text('first=$_firstLatch second=$_secondLatch'),
        ],
      ),
    );
  }
}

Future<void> pumpHost(WidgetTester tester, AssessmentGateway gateway) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AssessmentProvider>(
          create: (_) => AssessmentProvider(assessmentService: gateway),
        ),
        ChangeNotifierProvider<ProgressProvider>(
          create: (_) => ProgressProvider(),
        ),
      ],
      child: MaterialApp(home: _GuardHost(gateway: gateway)),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('recording failure still shows reward and choice (no strand)', (
    tester,
  ) async {
    await pumpHost(tester, _ThrowingGateway());
    await tester.tap(find.text('complete'));
    await tester.pumpAndSettle();

    // The write failed, so the parent is offered a retry.
    expect(find.text('Could not save this game'), findsOneWidget);
    await tester.tap(find.text('Continue anyway'));
    await tester.pumpAndSettle();

    // The reward still appears despite the failed write.
    expect(find.text('REWARD'), findsOneWidget);
    expect(find.text('CHOICE'), findsNothing);

    // Completing the reward hands off to the choice.
    await tester.tap(find.text('REWARD'));
    await tester.pumpAndSettle();
    expect(find.text('CHOICE'), findsOneWidget);
    expect(find.byType(_FallbackLanding), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmount during completion cancels the watchdog without crash', (
    tester,
  ) async {
    await pumpHost(tester, _ThrowingGateway());
    await tester.tap(find.text('complete'));
    await tester.pump();

    // Tear the host down mid-completion (the retry dialog is pending).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 16));

    // No crash, and the watchdog cannot navigate from a disposed host.
    expect(tester.takeException(), isNull);
    expect(find.byType(_FallbackLanding), findsNothing);
  });

  testWidgets('timeout fallback navigates when no surface ever appears', (
    tester,
  ) async {
    await pumpHost(tester, _SucceedingGateway());

    // Latches completion and then stalls: no reward/choice is ever shown, so
    // the watchdog must fire after 15s.
    await tester.tap(find.text('latch-only'));
    await tester.pump();
    expect(find.byType(_GuardHost), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();

    expect(find.byType(_FallbackLanding), findsOneWidget);
    expect(find.byType(_GuardHost), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completion latches once and stands down when a surface appears',
    (tester) async {
      await pumpHost(tester, _SucceedingGateway());
      await tester.tap(find.text('complete'));
      await tester.pumpAndSettle();

      // Reward appeared and the completion latched.
      expect(find.text('REWARD'), findsOneWidget);
      expect(find.text('first=true second=null'), findsOneWidget);

      // A second completion callback is refused (latched).
      await tester.tap(find.text('complete'));
      await tester.pump();
      expect(find.text('first=true second=false'), findsOneWidget);

      // Standing down (choice shown) means the watchdog can never escape.
      await tester.tap(find.text('REWARD'));
      await tester.pump();
      expect(find.text('CHOICE'), findsOneWidget);

      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(find.byType(_FallbackLanding), findsNothing);
      expect(find.byType(_GuardHost), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
