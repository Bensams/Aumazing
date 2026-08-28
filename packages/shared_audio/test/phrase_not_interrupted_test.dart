import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

/// A line fired after a phrase waits for the whole phrase.
///
/// A phrase — "purple" · "circle", "Tap the" · "yellow" · "star" — is spread
/// across the player pool, one word per player. So "is any player playing?" is
/// false in the gap between two words and true again a moment later, and a
/// caller that waited on whichever clip it happened to catch came back inside
/// that gap and spoke over the rest of the phrase. That is the doubled voice a
/// child hears at the end of a round.
///
/// A phrase is held open here with [VoiceOverService.beginPhrase] — the same
/// call `playSequence` makes — because there is no platform in a unit test to
/// keep one speaking.
///
/// What reached the speaker is witnessed by [VoiceOverService.spokenCues], not
/// by future completion: a line that is discarded still completes its future.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoiceOverService voice;

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

  test('a line fired during a phrase waits for all of it', () async {
    final phrase = voice.beginPhrase();

    var spoke = false;
    final transition = voice.playTransition().then((_) => spoke = true);
    await pumpEventQueue();

    expect(spoke, isFalse,
        reason: 'the transition must not come in between two words');

    // The last word ends, and with it the phrase.
    phrase.complete();

    await transition.timeout(const Duration(seconds: 5));
    expect(spoke, isTrue,
        reason: 'once the phrase is over the transition must still be heard');
  });

  test('a cancelled phrase does not strand the line waiting on it', () async {
    voice.beginPhrase();

    var spoke = false;
    final transition = voice.playTransition().then((_) => spoke = true);
    await pumpEventQueue();
    expect(spoke, isFalse);

    // The round moves on, so the phrase's remaining words are never spoken.
    // The waiter has to be released now rather than sitting out the backstop
    // timeout for a phrase that has already stopped — five seconds is well
    // inside that backstop, so passing here means it was released, not that it
    // expired.
    await voice.stop();

    await transition.timeout(const Duration(seconds: 5));
    expect(spoke, isTrue);
  });

  test('a fresh line taking the floor supersedes the waiting one', () async {
    voice.beginPhrase();

    // The round moved on while this line was waiting: the fresh line is what
    // the child is now hearing, and the round-transition line that never found
    // its moment is stale. The future still completes when the line is
    // discarded, so the witness is the spoken-cue transcript, not completion.
    final transition = voice.playTransition();
    await pumpEventQueue();
    expect(voice.spokenCues, isEmpty);

    await voice.play(VoiceOverCue.tapHere, skipDebounce: true);

    await transition.timeout(const Duration(seconds: 5));
    expect(voice.spokenCues, ['tapHere'],
        reason: 'the fresh line spoke while the transition waited; the '
            'transition must not cut it or arrive after its moment');
  });
}
