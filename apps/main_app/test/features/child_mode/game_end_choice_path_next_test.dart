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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PendingPathLaunch.take();
  });

  tearDown(PendingPathLaunch.take);

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
}

/// A stand-in for the child-mode stack: a lobby route with a game pushed
/// on top, which is where [GameEndChoiceDialog.show] is called from.
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

Widget _wrap(
  Widget home, {
  bool nextCycleLocked = false,
  AiAssessmentResponse prediction = _prediction,
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
