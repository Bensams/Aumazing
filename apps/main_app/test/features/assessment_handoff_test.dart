import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/post_assessment/post_assessment_handoff_screen.dart';
import 'package:aumazing/features/post_assessment/post_assessment_result_screen.dart';
import 'package:aumazing/features/pre_assessment/game_summary_dialog.dart';
import 'package:aumazing/features/pre_assessment/pre_assessment_result_screen.dart';
import 'package:aumazing/features/pre_assessment/waiting_for_parent_screen.dart';
import 'package:aumazing/model/assessment_run_snapshot.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/widgets/assessment_handoff.dart';
import 'package:aumazing/widgets/mascot.dart';
import 'package:aumazing/widgets/milestone_victory_scene.dart';

/// The child finishes an assessment holding the device, and the next screen is
/// written for their parent. Two things therefore have to hold: the child is
/// told out loud to fetch a grown-up (they usually cannot read the line), and
/// the parent-facing numbers stay behind verification until a parent is
/// actually there.
///
/// The post-assessment had neither — it pushed its result screen straight out
/// of the last game — so these pin both flows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // There is no audio device in a widget test. Stubbing the channels lets the
  // real service be constructed; the double below intercepts `play` before
  // anything would reach a platform player anyway.
  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in const [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        return call.method == 'create' ? null : 1;
      });
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ParentVerificationDialog.pinDelegate = null;
  });

  tearDown(() => ParentVerificationDialog.pinDelegate = null);

  // ── Helpers ──────────────────────────────────────────────────────────

  late _RecordingVoiceOver narrator;

  Widget host(
    Widget home, {
    AssessmentProvider? assessmentProvider,
  }) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChildProvider>(
            create: (_) => _TestChildProvider(),
          ),
          if (assessmentProvider != null)
            ChangeNotifierProvider<AssessmentProvider>(
              create: (_) => assessmentProvider,
            ),
        ],
        child: MaterialApp(theme: AppTheme.light, home: home),
      );

  /// Advances past the celebration and the voice delay, without relying on
  /// wall-clock time: every wait in this screen is a [Timer], so the test
  /// clock drives them exactly.
  Future<void> reachHandoff(WidgetTester tester) async {
    await tester.pump(kHandoffCelebrationDuration);
    await tester.pump(kHandoffVoiceDelay);
    await tester.pumpAndSettle();
  }

  /// Passes the verification gate through the injected PIN delegate.
  Future<void> verifyAsParent(WidgetTester tester) async {
    await tester.tap(find.text('I\'m the Parent'));
    await tester.pumpAndSettle();
    expect(find.byType(ParentVerificationDialog), findsOneWidget);

    for (final digit in [1, 2, 3, 4]) {
      await tester.tap(find.byKey(ValueKey('numpad_$digit')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('numpad_submit')));
    await tester.pumpAndSettle();
  }

  // ── The milestone victory scene ──────────────────────────────────────

  group('the celebration is the milestone victory scene', () {
    testWidgets('the companion appears in the trophy phase, not just later',
        (tester) async {
      narrator = _RecordingVoiceOver();
      await tester.pumpWidget(host(AssessmentHandoffScreen(
        title: 'Pre-Assessment Complete!',
        subtitle: 'You finished all the activities!',
        onParentVerified: (_) {},
        voiceOverFactory: (_) => narrator,
      )));
      await tester.pump();

      // The reusable scene, the child's companion and a drawn trophy are all on
      // screen while the celebration holds — and the hand-off line is not.
      expect(find.byType(MilestoneVictoryScene), findsOneWidget);
      expect(find.byType(Mascot), findsOneWidget);
      expect(find.byKey(kMilestoneTrophyKey), findsOneWidget);
      // The headline is voiced, not drawn; the subtitle is what shows.
      expect(find.text('You finished all the activities!'), findsOneWidget);
      expect(find.text('Pre-Assessment Complete!'), findsNothing);
      expect(find.text(kHandoffInstructionText), findsNothing);
    });
  });

  // ── The spoken hand-off ──────────────────────────────────────────────

  group('the hand-off instruction is spoken', () {
    testWidgets('not while the celebration is still on screen',
        (tester) async {
      narrator = _RecordingVoiceOver();
      await tester.pumpWidget(host(AssessmentHandoffScreen(
        onParentVerified: (_) {},
        voiceOverFactory: (_) => narrator,
      )));
      await tester.pump();

      expect(find.text('You finished all the activities!'), findsOneWidget);
      expect(find.text(kHandoffInstructionText), findsNothing);
      expect(narrator.played, isEmpty,
          reason: 'no milestone cue was supplied to the bare screen, and the '
              'hand-off line never plays during the celebration');

      // Still nothing part-way through the celebration.
      await tester.pump(kHandoffCelebrationDuration ~/ 2);
      expect(narrator.played, isEmpty);
    });

    testWidgets('exactly once, when the written instruction appears',
        (tester) async {
      narrator = _RecordingVoiceOver();
      await tester.pumpWidget(host(AssessmentHandoffScreen(
        onParentVerified: (_) {},
        voiceOverFactory: (_) => narrator,
      )));
      await reachHandoff(tester);

      expect(find.text(kHandoffInstructionText), findsOneWidget);
      expect(narrator.played, [VoiceOverCue.giveTheDeviceToYourParent]);
    });

    testWidgets('once only — rebuilds do not repeat it', (tester) async {
      narrator = _RecordingVoiceOver();
      await tester.pumpWidget(host(AssessmentHandoffScreen(
        onParentVerified: (_) {},
        voiceOverFactory: (_) => narrator,
      )));
      await reachHandoff(tester);
      expect(narrator.played, hasLength(1));

      // Opening and dismissing the gate rebuilds the screen underneath.
      await tester.tap(find.text('I\'m the Parent'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      expect(narrator.played, hasLength(1),
          reason: 'the child is asked to do one thing, once');
    });

    testWidgets('never after the screen is disposed', (tester) async {
      narrator = _RecordingVoiceOver();
      await tester.pumpWidget(host(AssessmentHandoffScreen(
        onParentVerified: (_) {},
        voiceOverFactory: (_) => narrator,
      )));

      // Past the celebration, but the cue is still waiting on its delay.
      await tester.pump(kHandoffCelebrationDuration);
      expect(narrator.played, isEmpty);

      // The screen goes away mid-delay.
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pump(kHandoffVoiceDelay * 4);

      expect(narrator.played, isEmpty,
          reason: 'a disposed screen has no player pool and nobody listening');
      expect(narrator.disposed, isTrue);
    });
  });

  // ── Pre-assessment ───────────────────────────────────────────────────

  group('pre-assessment', () {
    final results = [
      AssessmentResult(
        id: 'result-1',
        childId: 'child-1',
        type: 'pre',
        gameId: 'copy_me',
        score: 4,
        totalItems: 5,
        errorCount: 1,
        avgResponseTimeMs: 1200,
        completedAt: DateTime(2026, 8, 15),
      ),
    ];
    const profile = SupportProfile(
      communication: 'emerging',
      socialInteraction: 'emerging',
      playSkills: 'developing',
      attention: 'developing',
    );

    testWidgets('reaches the child hand-off before any result screen',
        (tester) async {
      narrator = _RecordingVoiceOver();
      await tester.pumpWidget(host(WaitingForParentScreen(
        results: results,
        profile: profile,
        voiceOverFactory: (_) => narrator,
      )));
      await reachHandoff(tester);

      expect(find.text(kHandoffInstructionText), findsOneWidget);
      // The milestone line is spoken first (during the celebration), then the
      // hand-off line after it — in that order, never overlapping.
      expect(narrator.played, [
        VoiceOverCue.milestonePreAssessmentComplete,
        VoiceOverCue.giveTheDeviceToYourParent,
      ]);
      expect(find.byType(PreAssessmentResultScreen), findsNothing);
      expect(find.byType(GameSummaryDialog), findsNothing);
    });

    testWidgets('the summary stays shut until verification succeeds',
        (tester) async {
      narrator = _RecordingVoiceOver();
      await tester.pumpWidget(host(WaitingForParentScreen(
        results: results,
        profile: profile,
        voiceOverFactory: (_) => narrator,
      )));
      await reachHandoff(tester);

      // Tapping the gate opens the challenge, not the results.
      await tester.tap(find.text('I\'m the Parent'));
      await tester.pumpAndSettle();
      expect(find.byType(ParentVerificationDialog), findsOneWidget);
      expect(find.byType(GameSummaryDialog), findsNothing);

      // Backing out leaves the results just as shut.
      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(GameSummaryDialog), findsNothing);
      expect(find.byType(PreAssessmentResultScreen), findsNothing);
    });

    testWidgets('verification opens the summary for this run', (tester) async {
      ParentVerificationDialog.pinDelegate = _AlwaysCorrectPin();
      narrator = _RecordingVoiceOver();
      await tester.pumpWidget(host(WaitingForParentScreen(
        results: results,
        profile: profile,
        voiceOverFactory: (_) => narrator,
      )));
      await reachHandoff(tester);
      await verifyAsParent(tester);

      expect(find.byType(GameSummaryDialog), findsOneWidget);
      final dialog =
          tester.widget<GameSummaryDialog>(find.byType(GameSummaryDialog));
      expect(dialog.results, same(results));
    });
  });

  // ── Post-assessment ──────────────────────────────────────────────────

  group('post-assessment', () {
    final improvement = {
      'has_data': true,
      'accuracy_improvement': 12.5,
    };
    const nextModulePremiumRequired = true;
    const profile = SupportProfile(
      communication: 'emerging',
      socialInteraction: 'developing',
      playSkills: 'developing',
      attention: 'developing',
    );
    final preSnapshot = AssessmentRunSnapshot(
      assessmentType: 'pre',
      childId: 'child-1',
      assessmentRunId: 'pre-run',
      completedAt: DateTime(2026, 8, 1),
      results: [
        AssessmentResult(
          id: 'pre-result',
          childId: 'child-1',
          assessmentRunId: 'pre-run',
          type: 'pre',
          gameId: 'copy_me',
          score: 3,
          totalItems: 5,
          errorCount: 2,
          avgResponseTimeMs: 1400,
          completedAt: DateTime(2026, 8, 1),
        ),
      ],
      profile: profile,
    );
    final postSnapshot = AssessmentRunSnapshot(
      assessmentType: 'post',
      childId: 'child-1',
      assessmentRunId: 'post-run',
      completedAt: DateTime(2026, 8, 15),
      results: [
        AssessmentResult(
          id: 'post-result',
          childId: 'child-1',
          assessmentRunId: 'post-run',
          type: 'post',
          gameId: 'copy_me',
          score: 4,
          totalItems: 5,
          errorCount: 1,
          avgResponseTimeMs: 1200,
          completedAt: DateTime(2026, 8, 15),
        ),
      ],
      profile: profile,
    );

    Widget handoff() => host(
          PostAssessmentHandoffScreen(
            improvement: improvement,
            nextModulePremiumRequired: nextModulePremiumRequired,
            voiceOverFactory: (_) => narrator,
          ),
          assessmentProvider: _SnapshotAssessmentProvider(
            preSnapshot: preSnapshot,
            postSnapshot: postSnapshot,
          ),
        );

    testWidgets('reaches the child hand-off before the result screen',
        (tester) async {
      narrator = _RecordingVoiceOver();
      await tester.pumpWidget(handoff());
      await reachHandoff(tester);

      expect(find.text(kHandoffInstructionText), findsOneWidget);
      expect(narrator.played, [
        VoiceOverCue.milestonePostAssessmentComplete,
        VoiceOverCue.giveTheDeviceToYourParent,
      ]);
      expect(find.byType(PostAssessmentResultScreen), findsNothing,
          reason: 'this screen compares the child\'s own before/after levels '
              'and is written for a parent');
    });

    testWidgets('the results stay shut until verification succeeds',
        (tester) async {
      narrator = _RecordingVoiceOver();
      await tester.pumpWidget(handoff());
      await reachHandoff(tester);

      await tester.tap(find.text('I\'m the Parent'));
      await tester.pumpAndSettle();
      expect(find.byType(ParentVerificationDialog), findsOneWidget);
      expect(find.byType(PostAssessmentResultScreen), findsNothing);

      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(PostAssessmentResultScreen), findsNothing);
    });

    testWidgets('verification continues with this run\'s exact numbers',
        (tester) async {
      ParentVerificationDialog.pinDelegate = _AlwaysCorrectPin();
      narrator = _RecordingVoiceOver();
      await tester.pumpWidget(handoff());
      await reachHandoff(tester);
      await verifyAsParent(tester);

      expect(find.byType(PostAssessmentResultScreen), findsOneWidget);
      final screen = tester.widget<PostAssessmentResultScreen>(
          find.byType(PostAssessmentResultScreen));
      expect(screen.improvement, same(improvement));
      expect(
        screen.nextModulePremiumRequired,
        same(nextModulePremiumRequired),
      );
      await tester.pump(const Duration(seconds: 4));
    });
  });
}

// ── Doubles ────────────────────────────────────────────────────────────

/// Records the cues asked for instead of reaching a platform player.
class _RecordingVoiceOver extends VoiceOverService {
  _RecordingVoiceOver() : super(languageCode: 'en_adult_woman');

  final List<VoiceOverCue> played = [];
  bool disposed = false;

  @override
  Future<void> play(
    VoiceOverCue cue, {
    bool awaitCompletion = false,
    bool skipDebounce = false,
  }) async {
    played.add(cue);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

/// Turns the verification gate into something a test can walk through, using
/// the delegate seam the app already installs at startup.
class _AlwaysCorrectPin implements ParentPinDelegate {
  @override
  bool get hasPin => true;

  @override
  Future<ParentPinAttempt> verify(String pin) async =>
      ParentPinAttempt.correct;

  @override
  Duration? get lockoutRemaining => null;

  @override
  Future<bool> onForgotPin(BuildContext context) async => false;
}

class _SnapshotAssessmentProvider extends AssessmentProvider {
  _SnapshotAssessmentProvider({
    required AssessmentRunSnapshot preSnapshot,
    required AssessmentRunSnapshot postSnapshot,
  })  : _preSnapshot = preSnapshot,
        _postSnapshot = postSnapshot;

  final AssessmentRunSnapshot _preSnapshot;
  final AssessmentRunSnapshot _postSnapshot;

  @override
  AssessmentRunSnapshot get preSnapshot => _preSnapshot;

  @override
  AssessmentRunSnapshot get postSnapshot => _postSnapshot;
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
