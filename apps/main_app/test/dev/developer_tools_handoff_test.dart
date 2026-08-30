import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/dev/developer_tools_config.dart';
import 'package:aumazing/dev/developer_tools_overlay.dart';
import 'package:aumazing/dev/developer_tools_panel.dart';
import 'package:aumazing/dev/developer_tools_service.dart';
import 'package:aumazing/features/post_assessment/post_assessment_handoff_screen.dart';
import 'package:aumazing/features/post_assessment/post_assessment_result_screen.dart';
import 'package:aumazing/features/pre_assessment/pre_assessment_result_screen.dart';
import 'package:aumazing/features/pre_assessment/waiting_for_parent_screen.dart';
import 'package:aumazing/model/ai_assessment_response.dart';
import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/assessment_run_snapshot.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/widgets/assessment_handoff.dart';

/// The whole point of the assessment shortcuts is that they skip the *time*
/// spent playing, not the child-facing ending: the child is told the games are
/// finished, asked to hand the device over, and the parent-facing results stay
/// behind verification. These pin that, and that a failure never dresses
/// itself up as a finished run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeveloperToolsConfig.debugAvailableOverride = true;
  });

  tearDown(() {
    DeveloperToolsPanel.resetOpenStateForTest();
    DeveloperToolsConfig.debugAvailableOverride = null;
  });

  Widget app(DeveloperToolsService service,
      {AssessmentProvider? provider, ChildProvider? childProvider}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChildProvider>(
              create: (_) => childProvider ?? _TestChildProvider()),
          ChangeNotifierProvider<AssessmentProvider>(
              create: (_) => provider ?? AssessmentProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useRootNavigator: true,
                    builder: (_) => DeveloperToolsPanel(
                      service: service,
                      handoffVoiceOverFactory: (_) => _NoopVoiceOver(),
                    ),
                  ),
                  child: const Text('open toolbox'),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> openToolbox(WidgetTester tester) async {
    await tester.tap(find.text('open toolbox'));
    await tester.pumpAndSettle();
    expect(find.text('Developer Tools'), findsOneWidget);
  }

  Future<void> runAction(WidgetTester tester, Key key,
      {String confirm = 'Complete', bool settleAfter = true}) async {
    // The sheet scrolls; the lower actions are below the fold in a small
    // test window.
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, confirm));
    if (settleAfter) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the DEV button opens exactly one toolbox, however often tapped',
      (tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ChildProvider>(create: (_) => _TestChildProvider()),
        ChangeNotifierProvider<AssessmentProvider>(
            create: (_) => AssessmentProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        navigatorKey: DeveloperToolsOverlay.navigatorKey,
        builder: DeveloperToolsOverlay.wrap,
        home: const Scaffold(body: Text('app content')),
      ),
    ));

    await tester.tap(find.text('DEV'));
    await tester.pumpAndSettle();
    expect(find.text('Developer Tools'), findsOneWidget);
    expect(DeveloperToolsPanel.isOpen, isTrue);

    // The button stays on top of the sheet by design, so it is still tappable
    // — tapping it again must not stack a second identical sheet.
    await tester.tap(find.text('DEV'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Developer Tools'), findsOneWidget,
        reason: 'still exactly one toolbox');

    // Closing releases the latch, so it can be reopened afterwards.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Developer Tools'), findsNothing);
    expect(DeveloperToolsPanel.isOpen, isFalse);

    await tester.tap(find.text('DEV'));
    await tester.pumpAndSettle();
    expect(find.text('Developer Tools'), findsOneWidget,
        reason: 'reopening still works after a clean close');
  });

  testWidgets('the floating button opens the toolbox from the root navigator',
      (tester) async {
    // The overlay lives above the navigator, so it has no Navigator.of() of
    // its own — it goes through the global key. Exercise that for real.
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ChildProvider>(create: (_) => _TestChildProvider()),
        ChangeNotifierProvider<AssessmentProvider>(
            create: (_) => AssessmentProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        navigatorKey: DeveloperToolsOverlay.navigatorKey,
        builder: DeveloperToolsOverlay.wrap,
        home: const Scaffold(body: Text('app content')),
      ),
    ));

    await tester.tap(find.text('DEV'));
    await tester.pumpAndSettle();

    expect(find.text('Developer Tools'), findsOneWidget);
    expect(find.text('Test (child-1)'), findsOneWidget,
        reason: 'the readout reflects the real providers, not a second tree');
  });

  group('pre-assessment shortcut', () {
    testWidgets('lands on the existing child hand-off, not on the results',
        (tester) async {
      await tester.pumpWidget(app(_ScriptedService()));
      await openToolbox(tester);

      await runAction(tester, const Key('developerToolsCompletePre'));

      expect(find.byType(WaitingForParentScreen), findsOneWidget);
      expect(find.byType(PreAssessmentResultScreen), findsNothing,
          reason: 'the child is still holding the device');
      expect(find.text('Developer Tools'), findsNothing,
          reason: 'the toolbox closes before the hand-off is installed');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('carries this run\'s real finalized values through',
        (tester) async {
      final service = _ScriptedService();
      await tester.pumpWidget(app(service));
      await openToolbox(tester);

      await runAction(tester, const Key('developerToolsCompletePre'));

      final screen = tester
          .widget<WaitingForParentScreen>(find.byType(WaitingForParentScreen));
      expect(screen.results, service.preResult.results);
      expect(screen.profile, service.preResult.profile);
      expect(screen.aiResponse, service.preResult.aiResponse);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the results stay behind the parent verification gate',
        (tester) async {
      await tester.pumpWidget(app(_ScriptedService()));
      await openToolbox(tester);
      await runAction(tester, const Key('developerToolsCompletePre'));

      // runAction settles past the milestone celebration into the child
      // hand-off (the celebration-first ordering is pinned in
      // assessment_handoff_test / milestone_victory_test). What matters here is
      // that the parent-facing results stay locked behind verification: the
      // spoken instruction and the gate are on screen, the results are not.
      await tester.pump(kHandoffVoiceDelay);
      expect(find.text(kHandoffInstructionText), findsOneWidget);
      expect(find.text('I\'m the Parent'), findsOneWidget);
      expect(find.byType(PreAssessmentResultScreen), findsNothing);
    });
  });

  group('post-assessment shortcut', () {
    testWidgets('lands on the existing hand-off with the run\'s numbers',
        (tester) async {
      final service = _ScriptedService();
      await tester.pumpWidget(
          app(service, provider: _ProviderWithPreAssessment()));
      await openToolbox(tester);

      await runAction(tester, const Key('developerToolsCompletePost'));

      final screen = tester.widget<PostAssessmentHandoffScreen>(
          find.byType(PostAssessmentHandoffScreen));
      expect(screen.improvement, service.postResult.improvement);
      expect(
        screen.nextModulePremiumRequired,
        service.postResult.nextModulePremiumRequired,
      );
      expect(find.byType(PostAssessmentResultScreen), findsNothing);
    });

    testWidgets('the comparison stays behind the parent verification gate',
        (tester) async {
      await tester.pumpWidget(
          app(_ScriptedService(), provider: _ProviderWithPreAssessment()));
      await openToolbox(tester);
      await runAction(tester, const Key('developerToolsCompletePost'));

      await tester.pump(kHandoffCelebrationDuration);
      await tester.pump(kHandoffVoiceDelay);
      await tester.pumpAndSettle();

      expect(find.text(kHandoffInstructionText), findsOneWidget);
      expect(find.text('I\'m the Parent'), findsOneWidget);
      expect(find.byType(PostAssessmentResultScreen), findsNothing);
    });

    testWidgets('is disabled without a pre-assessment baseline',
        (tester) async {
      await tester.pumpWidget(app(_ScriptedService()));
      await openToolbox(tester);

      // Both post-assessment routes — instant completion and auto-play —
      // refuse without a baseline, and both say why.
      for (final key in const [
        Key('developerToolsCompletePost'),
        Key('developerAutoPlayPost'),
      ]) {
        await tester.ensureVisible(find.byKey(key));
        await tester.pumpAndSettle();
        expect(tester.widget<ListTile>(find.byKey(key)).enabled, isFalse,
            reason: '$key must not be reachable without a pre-assessment');
      }
      expect(find.text('Needs a completed pre-assessment baseline'),
          findsNWidgets(2));
    });
  });

  group('critical pre-assessment preview', () {
    testWidgets('opens the existing non-clinical Therapy Center prompt and dismisses safely',
        (tester) async {
      await tester.pumpWidget(app(_ScriptedService()));
      await openToolbox(tester);

      await runAction(
        tester,
        const Key('developerToolsPreviewCritical'),
        confirm: 'Preview',
        settleAfter: false,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Explore Therapy Center support'), findsOneWidget);
      expect(find.textContaining('not a medical diagnosis'), findsOneWidget);
      expect(find.text('Browse Therapy Centers'), findsOneWidget);
      expect(find.byType(PreAssessmentResultScreen), findsOneWidget);

      await tester.tap(find.text('Maybe Later'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Explore Therapy Center support'), findsNothing);
      expect(find.text('Browse Therapy Centers'), findsNothing);
      expect(find.byType(PreAssessmentResultScreen), findsOneWidget);
      expect(find.text('Developer Tools'), findsNothing);
    });

    testWidgets('is disabled without an active child', (tester) async {
      await tester.pumpWidget(
        app(_ScriptedService(), childProvider: _EmptyChildProvider()),
      );
      await openToolbox(tester);

      final tile = tester.widget<ListTile>(
        find.byKey(const Key('developerToolsPreviewCritical')),
      );
      expect(tile.enabled, isFalse);
      expect(find.descendant(
        of: find.byKey(const Key('developerToolsPreviewCritical')),
        matching: find.text('Needs an active child profile'),
      ), findsOneWidget);
    });
  });

 // ── Doubles ────────────────────────────────────────────────────────────
  group('failures and duplicate taps', () {
    testWidgets('a failed run never navigates to a hand-off', (tester) async {
      await tester.pumpWidget(app(_FailingService()));
      await openToolbox(tester);

      await runAction(tester, const Key('developerToolsCompletePre'));

      expect(find.byType(WaitingForParentScreen), findsNothing);
      expect(find.byType(PreAssessmentResultScreen), findsNothing);
      expect(find.text('Developer Tools'), findsOneWidget,
          reason: 'the toolbox stays open with the error');
      expect(find.text('simulated failure'), findsOneWidget);
    });

    testWidgets('a second tap while running creates no second run',
        (tester) async {
      final service = _ScriptedService(gate: Completer<void>());
      await tester.pumpWidget(app(service));
      await openToolbox(tester);

      await tester.tap(find.byKey(const Key('developerToolsCompletePre')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Complete'));
      await tester.pump(); // the pipeline is now in flight

      // Everything is locked out while it runs.
      final tile = tester.widget<ListTile>(
          find.byKey(const Key('developerToolsCompletePre')));
      expect(tile.enabled, isFalse);
      final toggle = tester.widget<SwitchListTile>(
          find.byKey(const Key('developerToolsPremiumToggle')));
      expect(toggle.onChanged, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byKey(const Key('developerToolsCompletePre')),
          warnIfMissed: false);
      await tester.pump();

      service.gate!.complete();
      await tester.pumpAndSettle();

      expect(service.preCalls, 1);
      expect(find.byType(WaitingForParentScreen), findsOneWidget);
      // Past VoiceOverService's 4s native-operation backstop from the
      // hand-off prompt, so no pending timer is left when the tree disposes.
      await tester.pump(const Duration(seconds: 5));
    });
  });
}

// ── Doubles ────────────────────────────────────────────────────────────

class _NoopVoiceOver extends VoiceOverService {
  _NoopVoiceOver() : super(languageCode: 'en_adult_woman');

  @override
  Future<void> play(
    VoiceOverCue cue, {
    bool awaitCompletion = false,
    bool skipDebounce = false,
  }) async {}
}

/// Returns canned results instead of writing to SQLite and running the model
/// — the pipeline itself is covered in developer_tools_service_test.dart; what
/// matters here is where the toolbox lands afterwards.
class _ScriptedService extends DeveloperToolsService {
  _ScriptedService({this.gate});

  /// When set, the simulated run only completes once this is completed.
  final Completer<void>? gate;

  int preCalls = 0;
  int postCalls = 0;

  final preResult = SimulatedPreAssessment(
    results: [
      AssessmentResult(
        id: 'result-1',
        childId: 'child-1',
        type: 'pre',
        gameId: 'copy_me',
        score: 6,
        totalItems: 10,
        errorCount: 4,
        avgResponseTimeMs: 3400,
        completedAt: DateTime(2026, 8, 15),
      ),
    ],
    profile: _profile,
    aiResponse: _prediction(const {'communication': _emerging}),
  );

  final postResult = SimulatedPostAssessment(
    improvement: const {'has_data': true, 'accuracy_improvement': 0.2},
    nextModulePremiumRequired: true,
  );

  @override
  Future<SimulatedPreAssessment> completePreAssessment({
    required AssessmentProvider provider,
    required String childId,
  }) async {
    preCalls++;
    await gate?.future;
    return preResult;
  }

  @override
  Future<SimulatedPostAssessment> completePostAssessment({
    required AssessmentProvider provider,
    required String childId,
  }) async {
    postCalls++;
    await gate?.future;
    return postResult;
  }
}

class _FailingService extends DeveloperToolsService {
  @override
  Future<SimulatedPreAssessment> completePreAssessment({
    required AssessmentProvider provider,
    required String childId,
  }) async =>
      throw const DeveloperToolsException('simulated failure');
}

/// A provider that already has a finalized pre-assessment, so the
/// post-assessment shortcut's precondition is satisfied.
class _ProviderWithPreAssessment extends AssessmentProvider {
  @override
  AssessmentRunSnapshot? get preSnapshot => AssessmentRunSnapshot(
        assessmentType: 'pre',
        childId: 'child-1',
        assessmentRunId: 'run-1',
        completedAt: DateTime(2026, 8, 1),
        results: const [],
        prediction: _prediction(const {'communication': _emerging}),
      );
}

const _emerging = AreaLevel(
  level: 'emerging',
  levelInt: 1,
  levelName: 'Emerging',
  confidence: 0.7,
);

const _profile = SupportProfile(
  communication: 'emerging',
  socialInteraction: 'emerging',
  playSkills: 'emerging',
  attention: 'moderate',
  sensoryNotes: [],
  recommendedDifficulty: 'foundation',
  recommendedPromptStyle: 'combined',
  recommendedSessionMinutes: 5,
  promptRepetition: 2,
);

AiAssessmentResponse _prediction(Map<String, AreaLevel> areaLevels) =>
    AiAssessmentResponse(
      predictedProfile: 'mixed_support',
      confidence: 0.7,
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
class _EmptyChildProvider extends ChildProvider {
  _EmptyChildProvider()
      : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  @override
  ChildProfile? get profile => null;

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
