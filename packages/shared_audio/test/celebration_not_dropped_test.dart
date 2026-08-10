import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

/// The end-of-game praise is the reinforcer the whole reward system is built
/// on, and it was silently never playing.
///
/// Games fire it in the same synchronous breath as the final correct answer's
/// naming cue — see `match_it_game.dart`, where `onPlayCorrectVo` and
/// `onPlayCelebrationVo` are 26 lines apart with no await between them. The
/// naming cue stamps the debounce clock; the celebration then arrives inside
/// the 300 ms window and gets discarded. No error, no log a tester would
/// notice, just no praise.
///
/// These tests pin the two halves of the fix: the hazard is real, and the
/// celebration is exempt from it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoiceOverService voice;

  // There is no audio device in a unit test, and there does not need to be:
  // the debounce decision is made in Dart, before anything reaches the
  // platform. Stubbing the channels lets the real service run far enough to
  // exercise it.
  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in const [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        // `create` is the only call whose result is inspected; the rest are
        // fire-and-forget as far as this test is concerned.
        return call.method == 'create' ? null : 1;
      });
    }
  });

  setUp(() {
    voice = VoiceOverService(languageCode: 'en_adult_woman');
  });

  tearDown(() async {
    await voice.dispose();
  });

  test('an ordinary cue fired right after another is dropped', () async {
    await voice.play(VoiceOverCue.shapeCircle);
    expect(voice.debouncedCount, 0);

    // Same breath — this is what the games do.
    await voice.play(VoiceOverCue.greatJob);
    expect(voice.debouncedCount, 1,
        reason: 'the debounce window is what swallowed the celebration');
  });

  test('the celebration survives being fired in the same breath', () async {
    // Exactly the game-completion sequence, minus the label: nothing was named,
    // so the celebration is the only line the child gets and must be heard.
    await voice.playAnswerLabel(); // no recorded name — stays silent
    final droppedBefore = voice.debouncedCount;

    await voice.playRewardCelebration();

    expect(voice.debouncedCount, droppedBefore,
        reason: 'the celebration must never be dropped by the debounce');
    expect(voice.praiseSuppressedCount, 0,
        reason: 'nothing named the answer, so nothing outranks the praise');
  });

  // The round-transition line ("Next one!") sits in the same synchronous block
  // as the naming cue when a round ends, so it was being dropped identically.
  test('the round-transition line survives the same way', () async {
    await voice.playAnswerLabel(color: 'purple', shape: 'circle');
    final droppedAfterLabel = voice.debouncedCount;

    await voice.playTransition();

    expect(voice.debouncedCount, droppedAfterLabel,
        reason: 'the transition line must not be dropped by the debounce');
  });

  test('a disabled service still stays silent', () async {
    voice.setEnabled(false);
    await voice.playRewardCelebration();
    expect(voice.debouncedCount, 0);
  });
}
