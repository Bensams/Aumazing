import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/child_mode/game_end_choice_dialog.dart';
import 'package:aumazing/features/child_mode/pending_path_launch.dart';
import 'package:aumazing/model/ai_assessment_response.dart';
import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/module_recommendation.dart';
import 'package:aumazing/model/star_ledger_entry.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/model/module_progress.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/stars_provider.dart';
import 'package:aumazing/providers/progress_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aumazing/features/child_mode/child_mode_lobby_screen.dart';
import 'package:aumazing/features/premium/premium_upgrade_screen.dart';
final _profile = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Test',
  birthDate: DateTime(2022, 4, 20),
  avatar: 'bear',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

/// Two-step path: Match It then Copy Me. Finishing the first unlocks the
/// second, which is the "Next" the dialog should park rather than swap to.
const _prediction = AiAssessmentResponse(
  predictedProfile: 'play_support',
  confidence: 0.9,
  summary: 'test',
  supportLevel: 'moderate',
  recommendedModules: ['match_it', 'copy_me'],
  moduleDetails: [
    ModuleRecommendation(
      gameId: 'match_it',
      name: 'Match It',
      startingLevel: 2,
    ),
    ModuleRecommendation(gameId: 'copy_me', name: 'Copy Me', startingLevel: 2),
  ],
  areaLevels: {
    'play': AreaLevel(
      level: 'needs_support',
      levelInt: 0,
      levelName: 'Needs Support',
      confidence: 0.9,
    ),
  },
);

const _completedPathPrediction = AiAssessmentResponse(
  predictedProfile: 'play_support',
  confidence: 0.9,
  summary: 'test',
  supportLevel: 'moderate',
  recommendedModules: ['match_it'],
  moduleDetails: [
    ModuleRecommendation(
      gameId: 'match_it',
      name: 'Match It',
      startingLevel: 2,
    ),
  ],
  areaLevels: {
    'play': AreaLevel(
      level: 'needs_support',
      levelInt: 0,
      levelName: 'Needs Support',
      confidence: 0.9,
    ),
  },
);

void main() {
  setUpAll(() async {
    // The milestone celebration plays through the shared_audio audio-player
    // pool; without platform handlers the real players fail asynchronously and
    // leave service timers pending past teardown.
    for (final name in const [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async {
        return call.method == 'create' ? null : 1;
      });
    }
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-publishable-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ParentVerificationDialog.pinDelegate = null;
    PendingPathLaunch.take();
  });

  tearDown(() {
    ParentVerificationDialog.pinDelegate = null;
    PendingPathLaunch.take();
  });

  testWidgets('path Next parks the launch and pops home instead of swapping', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const _LobbyWithGame()));
    await tester.pump();

    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();
    expect(find.text('finish'), findsOneWidget);

    await tester.tap(find.text('finish'));
    await tester.pumpAndSettle();

    // The next path step is offered by name, icon-first.
    expect(find.text('Copy Me'), findsOneWidget);

    await tester.tap(find.text('Copy Me'));
    await tester.pumpAndSettle();

    // Back on the lobby — the game was popped, not replaced with Copy Me.
    expect(find.text('play'), findsOneWidget);
    expect(find.text('finish'), findsNothing);

    expect(
      PendingPathLaunch.take(),
      ('copy_me', 2),
      reason: 'the lobby is what launches Copy Me, once the ship docks',
    );
  });

  testWidgets(
    'locked repeat cycle ignores path milestones and uses registry Next',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const _LobbyWithGame(),
          nextCycleLocked: true,
          prediction: _completedPathPrediction,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('play'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('finish'));
      await tester.pumpAndSettle();

      expect(
        find.text('Copy Me'),
        findsOneWidget,
        reason: 'locked paths fall back to the next registry game',
      );
      expect(find.text('Path Complete!'), findsNothing);
      expect(PendingPathLaunch.take(), isNull);

      await tester.tap(find.text('Lobby'));
      await tester.pumpAndSettle();
      expect(PendingPathLaunch.take(), isNull);
    },
  );

  testWidgets(
    'locked recommended path blocks Premium when parent PIN is incorrect',
    (tester) async {
      ParentVerificationDialog.pinDelegate = const _TestPinDelegate(
        expectedPin: '4907',
        result: ParentPinAttempt.incorrect,
      );
      await tester.pumpWidget(
        _wrap(
          const ChildModeLobbyScreen(openPath: true),
          nextCycleLocked: true,
          prediction: _completedPathPrediction,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Unlock'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Enter your parent PIN:'), findsOneWidget);

      for (final digit in '4907'.split('')) {
        await tester.tap(find.byKey(ValueKey('numpad_$digit')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('numpad_submit')));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PremiumUpgradeScreen), findsNothing);
      expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);
      expect(PendingPathLaunch.take(), isNull);

      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PremiumUpgradeScreen), findsNothing);
    },
  );

  testWidgets(
    'locked recommended path opens Premium after parent PIN verification',
    (tester) async {
      ParentVerificationDialog.pinDelegate = const _TestPinDelegate(
        expectedPin: '4907',
        result: ParentPinAttempt.correct,
      );
      await tester.pumpWidget(
        _wrap(
          const ChildModeLobbyScreen(openPath: true),
          nextCycleLocked: true,
          prediction: _completedPathPrediction,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Fresh Learning Path Locked'), findsOneWidget);
      await tester.tap(find.text('Unlock'));
      await tester.pump(const Duration(milliseconds: 500));

      for (final digit in '4907'.split('')) {
        await tester.tap(find.byKey(ValueKey('numpad_$digit')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('numpad_submit')));
      await tester.pump();
      expect(find.byType(ParentVerificationDialog), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PremiumUpgradeScreen), findsOneWidget);
      expect(find.text('Aumazing Premium'), findsOneWidget);
      expect(find.text('Continuous AI recommendations'), findsOneWidget);
      expect(
        find.text('Fresh learning paths after every assessment'),
        findsOneWidget,
      );
      expect(PendingPathLaunch.take(), isNull);
      expect(find.text('play'), findsNothing);
    },
  );


  testWidgets('path Lobby pops home without parking a launch', (tester) async {
    await tester.pumpWidget(_wrap(const _LobbyWithGame()));
    await tester.pump();

    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('finish'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lobby'));
    await tester.pumpAndSettle();

    expect(find.text('play'), findsOneWidget);
    expect(PendingPathLaunch.take(), isNull);
  });

  testWidgets(
    'the path victory stands the completion watchdog down and lands on the '
    'lobby',
    (tester) async {
      // AUM-317 regression: the celebration is a fifteen-second surface, and
      // `onShown` used to be called only once it had finished. That let the
      // watchdog's own 15s window expire mid-victory and ferry the child out
      // to the parent dashboard instead of back to the child lobby.
      var shown = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          _LobbyWithGame(onShown: () => shown++),
          prediction: _completedPathPrediction,
          progressProvider: _TestProgressProvider(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('play'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('finish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      // The celebration is on screen — and the watchdog has already been told,
      // so it cannot fire out from under it.
      expect(
        find.text('You finished every activity on your path!'),
        findsOneWidget,
      );
      expect(
        shown,
        greaterThan(0),
        reason: 'the watchdog must stand down before the long celebration, '
            'not after it',
      );

      // Continuing takes the child back to the child lobby underneath — never
      // onward to a parent surface.
      await tester.pump(const Duration(seconds: 16));
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded),
          warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('play'), findsOneWidget, reason: 'back at the lobby');
      semantics.dispose();
    },
  );

  testWidgets(
    'finishing the last path game stamps the My Path history row and '
    'shows the victory',
    (tester) async {
      final progress = _TestProgressProvider();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          const _LobbyWithGame(),
          prediction: _completedPathPrediction,
          progressProvider: progress,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('play'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('finish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      // The durable parent-history stamp is written exactly once, with the
      // deterministic child+path id and the completed path length.
      final stamped = progress.lastUpdate!;
      expect(stamped.id, startsWith('my_path_child-1_'));

      // The milestone celebration for the completed path.
      expect(
        find.text('You finished every activity on your path!'),
        findsOneWidget,
      );
      expect(stamped.id, startsWith('my_path_child-1_'));
      expect(stamped.moduleId, 'my_path');
      expect(stamped.moduleName, 'My Path');
      expect(stamped.childId, 'child-1');
      expect(stamped.status, 'completed');
      expect(stamped.currentLevel, 1);
      expect(stamped.maxLevel, 1);
      expect(stamped.completedAt, isNotNull);

      // Dismiss the celebration so its hold timers are cancelled before the
      // test tears the tree down. The celebration is now a playable stage held
      // for twelve seconds (a child who pops every reward leaves sooner), with
      // the safety valve revealing the continue control by fifteen regardless
      // of the staged intro state.
      await tester.pump(const Duration(seconds: 16));
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      semantics.dispose();
    },
  );
}

/// A stand-in for the child-mode stack: a lobby route with a game pushed
/// on top, which is where [GameEndChoiceDialog.show] is called from.
class _LobbyWithGame extends StatelessWidget {
  const _LobbyWithGame({this.onShown});

  /// Forwarded to [GameEndChoiceDialog.show] — this is what a real game screen
  /// wires its completion watchdog to.
  final void Function()? onShown;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder:
                  (_) => Scaffold(
                    body: Builder(
                      builder:
                          (gameContext) => TextButton(
                            onPressed:
                                () => GameEndChoiceDialog.show(
                                  gameContext,
                                  currentGameId: 'match_it',
                                  onShown: onShown,
                                ),
                            child: const Text('finish'),
                          ),
                    ),
                  ),
            ),
          );
        },
        child: const Text('play'),
      ),
    );
  }
}

Widget _wrap(
  Widget home, {
  bool nextCycleLocked = false,
  AiAssessmentResponse prediction = _prediction,
  ProgressProvider? progressProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(),
      ),
      ChangeNotifierProvider<AssessmentProvider>(
        create:
            (_) => _TestAssessmentProvider(
              nextCycleLocked: nextCycleLocked,
              prediction: prediction,
            ),
      ),
      ChangeNotifierProvider<StarsProvider>(
        create: (_) => _SilentStarsProvider(),
      ),
      if (progressProvider != null)
        ChangeNotifierProvider<ProgressProvider>.value(value: progressProvider),
    ],
    child: MaterialApp(theme: AppTheme.light, home: home),
  );
}

/// Awards nothing so the star overlay never opens and the choice is next.
class _SilentStarsProvider extends StarsProvider {
  @override
  Future<void> bind(String? childId) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<StarAwardResult> awardForPlay({
    required String playKey,
    StarReason reason = StarReason.gamePlayed,
  }) async => const StarAwardResult(StarAwardOutcome.noChild);
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider()
    : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  @override
  ChildProfile? get profile => _profile;

  @override
  Future<void> loadProfile() async {}
}

class _TestAssessmentProvider extends AssessmentProvider {
  _TestAssessmentProvider({
    required this.nextCycleLocked,
    required this.prediction,
  });

  @override
  final bool nextCycleLocked;

  final AiAssessmentResponse prediction;

  @override
  AiAssessmentResponse? get aiPrediction => prediction;

  @override
  Set<String> get pathCompletedGameIds => const {'match_it'};

  @override
  bool get hasPreAssessment => true;

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

/// Captures the last module-progress write without touching a database.
class _TestProgressProvider extends ProgressProvider {
  ModuleProgress? lastUpdate;

  @override
  Future<void> updateModuleProgress(ModuleProgress progress) async {
    lastUpdate = progress;
  }
}

class _TestPinDelegate implements ParentPinDelegate {
  const _TestPinDelegate({required this.expectedPin, required this.result});

  final String expectedPin;
  final ParentPinAttempt result;

  @override
  bool get hasPin => true;

  @override
  Future<ParentPinAttempt> verify(String pin) async {
    if (pin != expectedPin) return ParentPinAttempt.incorrect;
    return result;
  }

  @override
  Duration? get lockoutRemaining => null;

  @override
  Future<bool> onForgotPin(BuildContext context) async => false;
}
