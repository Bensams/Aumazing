import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/rewards/reward_type.dart';
import 'package:aumazing/features/rewards/widgets/reward_overlay.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The reward's "Pop the bubbles!" hint used to be a white banner across the
/// top of the effect. A pre-reader could not use it and it covered the thing
/// they were meant to be playing with, so it is now spoken instead.
///
/// These tests pin both halves: no reward draws the words any more, and each
/// reward kind speaks its own line — after a delay, so it follows the game's
/// end-of-round celebration rather than cutting it off.
///
/// Supersedes reward_overlay_decoration_test.dart (AUM-312), which existed only
/// to keep that banner from inheriting a yellow underline. There is no banner
/// left to underline.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> drainReward(WidgetTester tester) async {
    // The reward's own auto-proceed/effect-completion timers go out to ~24s
    // (balloons advance past 12s), so advance well past them, then dispose the
    // overlay to stop its indefinitely-animating effects (rockets, balloons)
    // and flush every timer their launch chains queued. pumpAndSettle is never
    // used: these effects do not settle.
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<_RecordingVoiceOver> pumpReward(
    WidgetTester tester,
    RewardType type,
  ) async {
    final voice = _RecordingVoiceOver();
    await tester.pumpWidget(
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _QuietChild(),
        child: MaterialApp(
          home: RewardOverlay(
            rewardType: type,
            onComplete: () {},
            minDisplayDuration: const Duration(seconds: 10),
            voiceOverFactory: (_) => voice,
          ),
        ),
      ),
    );
    await tester.pump();
    return voice;
  }

  for (final (type, noun) in const [
    (RewardType.balloons, 'balloons'),
    (RewardType.fireworks, 'rockets'),
    (RewardType.bubbles, 'bubbles'),
    (RewardType.candy, 'candy'),
  ]) {
    testWidgets('${type.name} draws no written hint', (tester) async {
      await pumpReward(tester, type);

      // Matched on the noun alone, so a reworded banner or one carrying an
      // emoji prefix is caught too — any of these words on screen is a written
      // hint, and the point is that a pre-reader gets the instruction by ear.
      expect(find.textContaining(noun), findsNothing,
          reason: 'the ${type.name} hint must be spoken, not drawn');

      expect(tester.takeException(), isNull);
      await drainReward(tester);
    });
  }

  testWidgets('each reward speaks its own hint, after the celebration',
      (tester) async {
    for (final (type, cue) in const [
      (RewardType.balloons, VoiceOverCue.rewardHintBalloons),
      (RewardType.fireworks, VoiceOverCue.rewardHintFireworks),
      (RewardType.bubbles, VoiceOverCue.rewardHintBubbles),
      (RewardType.candy, VoiceOverCue.rewardHintCandy),
    ]) {
      final voice = await pumpReward(tester, type);

      // Nothing is said while the game's own "Well done!" is still landing.
      await tester.pump(kRewardHintDelay - const Duration(milliseconds: 100));
      expect(voice.played, isEmpty,
          reason: '${type.name} spoke over the celebration line');

      await tester.pump(const Duration(milliseconds: 200));
      expect(voice.played, [cue],
          reason: '${type.name} must speak $cue exactly once');

      await drainReward(tester);
    }
  });
}

class _RecordingVoiceOver extends VoiceOverService {
  final List<VoiceOverCue> played = [];

  @override
  Future<void> play(
    VoiceOverCue cue, {
    bool awaitCompletion = false,
    bool skipDebounce = false,
  }) async {
    played.add(cue);
  }

  @override
  Future<void> dispose() async {}
}

class _QuietChild extends ChildProvider {
  _QuietChild()
      : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuth()));

  // Avoid the celebration haptic read in _startRewardFlow: a widget test has
  // no HapticService, and the only consumer here is the overlay's own toggle.
  @override
  bool get vibrationEnabled => false;

  @override
  Future<void> loadProfile() async {}
}

class _FakeSupabaseAuth implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
