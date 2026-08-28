import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/widgets/mascot.dart';
import 'package:aumazing/widgets/milestone_victory_scene.dart';
import 'package:aumazing/widgets/milestone_victory_screen.dart';

/// The milestone victory is one coherent character-and-trophy scene: the
/// child's *own* companion (never inferred from anything) climbing to a drawn
/// golden trophy. These pin the parts a screenshot cannot: that the profile's
/// characterId/equippedCostume reach the scene, that the companion is present
/// in the celebration itself, that reduced motion drops the traversal without
/// changing the message, and that the continuation never fires twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // No audio device in a widget test — stub the channels so the real service
  // can be built. Sprite sheets are never driven here (no runAsync), so the
  // companion stays at its reserved fallback box and nothing decodes.
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

  Widget host(Widget home, {ChildProfile? profile}) =>
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(profile),
        child: MaterialApp(theme: AppTheme.light, home: home),
      );

  ChildProfile profileWith({
    String characterId = 'reiz',
    String equippedCostume = 'teddy',
  }) =>
      ChildProfile(
        id: 'child-1',
        userId: 'user-1',
        displayName: 'Test',
        birthDate: DateTime(2022, 4, 20),
        avatar: 'bear',
        characterId: characterId,
        equippedCostume: equippedCostume,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

  group('the scene', () {
    testWidgets('shows the subtitle; the title is voiced, not drawn',
        (tester) async {
      await tester.pumpWidget(host(
        const Scaffold(
          body: MilestoneVictoryScene(
            title: 'You Completed Your Learning Path!',
            subtitle: 'You finished every activity on your path!',
            reducedMotion: true,
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('You finished every activity on your path!'),
          findsOneWidget);
      // The headline is not drawn — it overflows and a pre-reader cannot use
      // it; it is spoken instead (and kept for screen readers via semantics).
      expect(find.text('You Completed Your Learning Path!'), findsNothing);
    });

    testWidgets('the companion uses the profile characterId and costume',
        (tester) async {
      await tester.pumpWidget(host(
        const Scaffold(
          body: MilestoneVictoryScene(
            title: 'Pre-Assessment Complete!',
            subtitle: 'You finished all the activities!',
            reducedMotion: true,
          ),
        ),
        profile: profileWith(characterId: 'reiz', equippedCostume: 'teddy'),
      ));
      await tester.pump();

      final mascot = tester.widget<Mascot>(find.byType(Mascot));
      expect(mascot.character, MascotCharacter.reiz,
          reason: 'the companion must be the profile choice, never inferred');
      expect(mascot.costumeId, 'teddy');
    });

    testWidgets('the companion and the trophy are both in the trophy phase',
        (tester) async {
      await tester.pumpWidget(host(
        const Scaffold(
          body: MilestoneVictoryScene(
            title: 'Post-Assessment Complete!',
            subtitle: 'You finished all the activities!',
            reducedMotion: true,
          ),
        ),
        profile: profileWith(),
      ));
      await tester.pump();

      expect(find.byType(Mascot), findsOneWidget,
          reason: 'the companion appears in the celebration itself, not only '
              'on a later panel');
      expect(find.byKey(kMilestoneTrophyKey), findsOneWidget,
          reason: 'a drawn, composed trophy — not a bare emoji');
      // The emoji trophy the old celebration used must be gone.
      expect(find.text('🏆'), findsNothing);
    });

    testWidgets('reduced motion stands the companion still, without traversal',
        (tester) async {
      var arrived = false;
      await tester.pumpWidget(host(
        Scaffold(
          body: MilestoneVictoryScene(
            title: 'Pre-Assessment Complete!',
            subtitle: 'You finished all the activities!',
            reducedMotion: true,
            onArrived: () => arrived = true,
          ),
        ),
        profile: profileWith(),
      ));
      await tester.pump();

      final mascot = tester.widget<Mascot>(find.byType(Mascot));
      expect(mascot.entrance, MascotEntrance.none,
          reason: 'nothing walks across the scene under reduced motion');
      expect(arrived, isTrue,
          reason: 'arrival is immediate — the companion is already at the top');

      // No lingering animations: the scene settles.
      await tester.pumpAndSettle();
    });

    testWidgets('full motion walks the companion in with the walk entrance',
        (tester) async {
      await tester.pumpWidget(host(
        const Scaffold(
          body: MilestoneVictoryScene(
            title: 'Pre-Assessment Complete!',
            subtitle: 'You finished all the activities!',
            reducedMotion: false,
          ),
        ),
        profile: profileWith(),
      ));
      await tester.pump();
      // Let the staged intro timers fire so none are left pending at teardown.
      await tester.pump(const Duration(milliseconds: 700));

      final mascot = tester.widget<Mascot>(find.byType(Mascot));
      expect(mascot.entrance, MascotEntrance.fromLeft);
      expect(mascot.gesture, MascotGesture.celebrate,
          reason: 'it celebrates on reaching the top');
    });
  });

  group('the learning-path screen', () {
    testWidgets('speaks the milestone line for its kind', (tester) async {
      final narrator = _RecordingVoiceOver();
      await tester.pumpWidget(host(
        MilestoneVictoryScreen(
          kind: MilestoneKind.learningPath,
          reducedMotion: true,
          playSfx: false,
          holdDuration: const Duration(milliseconds: 50),
          voiceOverFactory: (_) => narrator,
          onContinue: () {},
        ),
        profile: profileWith(),
      ));
      await tester.pump();
      // The line is spoken a beat into the celebration, after the chime.
      await tester.pump(const Duration(milliseconds: 700));

      expect(narrator.played, [VoiceOverCue.milestoneLearningPathComplete]);
    });

    testWidgets('reveals a continue control and fires onContinue exactly once',
        (tester) async {
      var continued = 0;
      await tester.pumpWidget(host(
        MilestoneVictoryScreen(
          kind: MilestoneKind.learningPath,
          reducedMotion: true,
          playSfx: false,
          holdDuration: const Duration(milliseconds: 50),
          voiceOverFactory: (_) => _RecordingVoiceOver(),
          onContinue: () => continued++,
        ),
        profile: profileWith(),
      ));
      await tester.pump();
      // Arrival is immediate under reduced motion; hold, then the control fades
      // in (400 ms) — pump past it so it is on screen and tappable.
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 450));

      final continueButton = find.bySemanticsLabel('Continue');
      expect(continueButton, findsOneWidget);

      // A frantic double tap must not run the continuation twice or open two
      // screens.
      await tester.tap(continueButton, warnIfMissed: false);
      await tester.tap(continueButton, warnIfMissed: false);
      await tester.pump();

      expect(continued, 1);
    });

    testWidgets('is not left without a way forward — the max hold frees it',
        (tester) async {
      var continued = 0;
      await tester.pumpWidget(host(
        MilestoneVictoryScreen(
          kind: MilestoneKind.learningPath,
          reducedMotion: true,
          playSfx: false,
          voiceOverFactory: (_) => _RecordingVoiceOver(),
          // The normal post-arrival hold is long; the max-hold safety valve is
          // short, so it is what actually reveals the control here.
          holdDuration: const Duration(seconds: 30),
          maxHold: const Duration(milliseconds: 50),
          onContinue: () => continued++,
        ),
        profile: profileWith(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 450));

      final continueButton = find.bySemanticsLabel('Continue');
      expect(continueButton, findsOneWidget,
          reason: 'the max-hold fallback must free a stuck celebration');

      // Tap to continue — this also cancels the long hold timer so none is left
      // pending at teardown.
      await tester.tap(continueButton, warnIfMissed: false);
      await tester.pump();
      expect(continued, 1);
    });
  });
}

/// Records the cues asked for instead of reaching a platform player.
class _RecordingVoiceOver extends VoiceOverService {
  _RecordingVoiceOver() : super(languageCode: 'en_adult_woman');

  final List<VoiceOverCue> played = [];

  @override
  Future<void> play(
    VoiceOverCue cue, {
    bool awaitCompletion = false,
    bool skipDebounce = false,
  }) async {
    played.add(cue);
  }
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider(this._profile)
      : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  final ChildProfile? _profile;

  @override
  ChildProfile? get profile => _profile;

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
