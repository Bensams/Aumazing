import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

/// Immediate feedback outranks praise.
///
/// Every game names what the child just answered and then, on the next line
/// with nothing awaited between, praises them. Both reaching the speaker means
/// either two voices at once or a "Great job!" landing after the moment it
/// belonged to. The label wins: it is tied to what the child is looking at and
/// it teaches the word.
///
/// The arbitration lives in the service rather than in any game, so these tests
/// stand in for all of them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoiceOverService voice;

  // No audio device in a unit test, and none needed: the layer decides in Dart,
  // before anything reaches the platform.
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
    voice = VoiceOverService(languageCode: 'en_adult_woman');
  });

  tearDown(() async {
    await voice.dispose();
  });

  test('praise is dropped when a label named the answer', () async {
    await voice.playAnswerLabel(color: 'purple', shape: 'circle');
    expect(voice.isImmediateFeedbackActive, isTrue);

    await voice.playCorrectPraise();

    expect(voice.praiseSuppressedCount, 1,
        reason: 'the label already said what the child got right');
  });

  test('the end-of-game celebration yields to the final label too', () async {
    await voice.playAnswerLabel(item: 'gatas');

    await voice.playRewardCelebration();

    expect(voice.praiseSuppressedCount, 1);
  });

  test('praise plays when the answer had no recorded name', () async {
    // AnswerLabel.none — what My Turn Your Turn passes on every correct turn.
    await voice.playAnswerLabel();
    expect(voice.isImmediateFeedbackActive, isFalse,
        reason: 'a silent label must not hold the floor against praise');

    await voice.playCorrectPraise();

    expect(voice.praiseSuppressedCount, 0);
  });

  test('a later line ends the feedback episode', () async {
    await voice.playAnswerLabel(letter: 'a');
    expect(voice.isImmediateFeedbackActive, isTrue);

    // An instruction for the next round takes the floor; the label is no longer
    // what the child is hearing, so it no longer speaks for them.
    await voice.play(VoiceOverCue.tapHere, skipDebounce: true);

    expect(voice.isImmediateFeedbackActive, isFalse);
  });

  test('the layer survives a disabled service', () async {
    voice.setEnabled(false);
    await voice.playAnswerLabel(color: 'red', shape: 'star');
    await voice.playCorrectPraise();

    expect(voice.praiseSuppressedCount, 0,
        reason: 'nothing spoke, so nothing was suppressed');
  });
}
