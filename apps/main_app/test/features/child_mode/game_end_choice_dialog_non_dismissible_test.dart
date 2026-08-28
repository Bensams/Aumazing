import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/child_mode/game_end_choice_dialog.dart';
import 'package:aumazing/features/child_mode/pending_path_launch.dart';
import 'package:aumazing/model/ai_assessment_response.dart';
import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/module_recommendation.dart';
import 'package:aumazing/model/star_ledger_entry.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/stars_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Two-step path (Match It then Copy Me), so "Next" is offered by name.
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

void main() {
  setUpAll(() async {
    // The milestone celebration plays through shared_audio's audio-player
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

  testWidgets(
    'choice dialog cannot be dismissed by barrier tap or system back',
    (tester) async {
      await tester.pumpWidget(_wrap(const _LobbyWithGame()));
      await tester.pump();

      await tester.tap(find.text('play'));
      await tester.pumpAndSettle();
      expect(find.text('finish'), findsOneWidget);

      await tester.tap(find.text('finish'));
      await tester.pumpAndSettle();

      // The choice dialog is up, offering the next path step by name.
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Copy Me'), findsOneWidget);

      // Barrier tap does not dismiss.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Copy Me'), findsOneWidget);

      // System back does not dismiss (PopScope canPop: false).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Copy Me'), findsOneWidget);

      // A deliberate choice still works and closes the dialog.
      await tester.tap(find.text('Lobby'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

/// A stand-in for the child-mode stack: a lobby route with a game pushed on
/// top, which is where [GameEndChoiceDialog.show] is called from.
class _LobbyWithGame extends StatelessWidget {
  const _LobbyWithGame();

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

Widget _wrap(Widget home) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(),
      ),
      ChangeNotifierProvider<AssessmentProvider>(
        create: (_) => _TestAssessmentProvider(),
      ),
      ChangeNotifierProvider<StarsProvider>(
        create: (_) => _SilentStarsProvider(),
      ),
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
  @override
  AiAssessmentResponse? get aiPrediction => _prediction;

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
