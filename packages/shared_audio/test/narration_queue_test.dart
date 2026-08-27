import 'dart:io';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

import 'fake_audioplayers_platform.dart';

/// The correct-answer voice-over owns the narrator; next-round narration must
/// not cut it, stack on it, or arrive after the moment it belonged to.
///
/// A game fires the label ("red circle") and then, in the next synchronous
/// breath or a moment later, the line that moves to the next round. When both
/// reach the speaker the child hears either a doubled voice or praise landing
/// after the label it belonged to. The service parks the round line behind the
/// label and speaks it only if nothing newer took the floor while the label
/// was still finishing.
///
/// Phrases and sequences run against [FakeAudioplayersPlatform], which reports
/// native preparation and completion like a real device, so the queue advances
/// on real timing instead of the service's failure backstops. The witness for
/// what reached the speaker is [VoiceOverService.spokenCues]: a parked line
/// that gets discarded completes its future without registering a cue, so
/// future-completion alone would prove nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoiceOverService voice;

  setUpAll(() {
    AudioplayersPlatformInterface.instance = FakeAudioplayersPlatform();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // The service's shared global player (its event bus and reward sounds)
    // still runs on the real method-channel backend, which needs a mock in a
    // headless test so its create call resolves.
    messenger.setMockMethodCallHandler(
      MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => call.method == 'create' ? null : 1,
    );
    // audioplayers resolves a source URL through path_provider before the
    // native prepare; without the mock every setSource fails and a queued
    // playSequence never registers its first word.
    messenger.setMockMethodCallHandler(
      MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
  });

  setUp(() {
    voice = VoiceOverService(languageCode: 'en_adult_woman');
  });

  tearDown(() async {
    await voice.dispose();
  });

  List<String> transcript() => List.of(voice.spokenCues);

  test('a round line parked behind the label waits for it, then speaks',
      () async {
    await voice.playAnswerLabel(color: 'red', shape: 'star');
    expect(voice.isImmediateFeedbackActive, isTrue);
    final before = transcript();

    // The label's last word is still on the air.
    final phrase = voice.beginPhrase();
    final transition = voice.playTransition();
    await pumpEventQueue();
    expect(transcript(), before,
        reason: 'the round line must not cut the correct-answer feedback');

    phrase.complete();
    await transition.timeout(const Duration(seconds: 5));
    expect(transcript().length, before.length + 1,
        reason: 'the round line still belongs to the moment: speak it after '
            'the label');
    expect(voice.isImmediateFeedbackActive, isFalse,
        reason: 'the parked line took the floor and ended the episode');
  });

  test('a line fired in the same breath as the label waits out the episode',
      () async {
    final before = transcript();

    // A game fires the label and, with nothing awaited between, the round
    // line - the exact same-breath sequence that used to cut the label. The
    // label's native preparation is in flight: no phrase exists and no pool
    // player reports playing yet, which is the window the parked line once
    // slipped through. It must wait the feedback episode out instead.
    final label = voice.playAnswerLabel(color: 'red', shape: 'star');
    final transition = voice.playTransition();

    await transition.timeout(const Duration(seconds: 6));
    await label;
    expect(transcript().length, before.length + 2,
        reason: 'the label spoke first and the round line spoke after it, '
            'never on top of it');
    expect(transcript().first, 'phraseRedStar',
        reason: 'the label owns the episode; the round line is follow-up');
    expect(voice.isImmediateFeedbackActive, isFalse,
        reason: 'the parked line took the floor and ended the episode');
  });

  test('a round line parked behind the label is dropped by a newer round line',
      () async {
    await voice.playAnswerLabel(color: 'red', shape: 'star');
    final before = transcript();
    final phrase = voice.beginPhrase();

    // Round two queues its line, then round three's line replaces it before
    // the label finishes. One slot: only the newest round line may speak.
    final first = voice.playTransition();
    await pumpEventQueue();
    final second = voice.playTransition();
    await pumpEventQueue();

    phrase.complete();
    await Future.wait([
      first.timeout(const Duration(seconds: 5)),
      second.timeout(const Duration(seconds: 5)),
    ]);
    expect(transcript().length, before.length + 1,
        reason: 'one slot: the second line replaced the first');
  });

  test('a correct answer arriving while a round line waits supersedes it',
      () async {
    // No label is active yet, so the round line takes the wait path: it is
    // waiting on the phrase when the correct answer lands.
    voice.beginPhrase();
    final transition = voice.playTransition();
    await pumpEventQueue();
    final before = transcript();

    await voice.playAnswerLabel(color: 'green', shape: 'square');
    final afterLabel = transcript();
    expect(afterLabel.length, greaterThan(before.length),
        reason: 'the label claimed the floor itself');

    await transition.timeout(const Duration(seconds: 5));
    expect(transcript(), afterLabel,
        reason: 'a waiting round line is stale the moment a fresh answer lands');
    expect(voice.isImmediateFeedbackActive, isTrue,
        reason: 'the correct-answer feedback owns the floor');
  });

  test('a round line arriving after the feedback window speaks in the moment',
      () async {
    await voice.playAnswerLabel(color: 'red', shape: 'star');
    final before = transcript();

    // Longer than the three-second feedback episode: the label has finished,
    // so the round line belongs to a fresh moment and may speak at once.
    await Future<void>.delayed(const Duration(milliseconds: 3100));

    final transition = voice.playTransition();
    await transition.timeout(const Duration(seconds: 5));
    expect(transcript().length, before.length + 1,
        reason: 'the label is long gone; the round line is not stale');
    expect(voice.isImmediateFeedbackActive, isFalse);
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('rapid answers keep one coherent feedback episode, never doubled',
      () async {
    await voice.playAnswerLabel(color: 'red', shape: 'star');
    await voice.playAnswerLabel(color: 'green', shape: 'square');

    expect(voice.isImmediateFeedbackActive, isTrue);
    await pumpEventQueue();
    expect(voice.isImmediateFeedbackActive, isTrue,
        reason: 'the episode continues through rapid answers and nothing can '
            'stack on the label');
  });

  test('stop discards the parked round line', () async {
    await voice.playAnswerLabel(color: 'red', shape: 'star');
    final before = transcript();
    // The label is still on the air when the child navigates away.
    voice.beginPhrase();
    final transition = voice.playTransition();
    await pumpEventQueue();

    await voice.stop();

    await transition.timeout(const Duration(seconds: 5));
    expect(transcript(), before,
        reason: 'navigation away must end the round line, not play it later');
  });

  test('disabling the service discards the parked round line', () async {
    await voice.playAnswerLabel(color: 'red', shape: 'star');
    final before = transcript();
    // The label is still on the air when the service is muted.
    voice.beginPhrase();
    final transition = voice.playTransition();
    await pumpEventQueue();

    voice.setEnabled(false);

    await transition.timeout(const Duration(seconds: 5));
    expect(transcript(), before,
        reason: 'a muted service never plays a parked line');
  });

  test('the parked line does not outlive a fresh transitional tap', () async {
    await voice.playAnswerLabel(color: 'red', shape: 'star');
    final before = transcript();
    // The label is still on the air when the child taps through.
    voice.beginPhrase();
    final transition = voice.playTransition();
    await pumpEventQueue();

    // The child tapped through to the next instruction while the label was
    // still finishing; the instruction carries the moment now.
    await voice.play(VoiceOverCue.tapHere, skipDebounce: true);

    await transition.timeout(const Duration(seconds: 5));
    expect(transcript(), [...before, 'tapHere'],
        reason: 'the fresh instruction is what the child is hearing; the '
            'round line is stale');
    expect(voice.isImmediateFeedbackActive, isFalse,
        reason: 'the fresh instruction took the floor');
  });

  test(
      'a queued line in flight does not let narration cut a fresh label',
      () async {
    final fake =
        AudioplayersPlatformInterface.instance as FakeAudioplayersPlatform;
    fake.eventLog.clear();
    final before = transcript();

    await voice.playAnswerLabel(color: 'red', shape: 'star');
    final sequence = voice.playSequence([VoiceOverCue.letsBegin]);

    // Hold the queued line in playback the moment it fires - the exact
    // "slow device" window the guard bypass used to cover. The line is on
    // the floor, and anything leaking through the bypass can cut what the
    // child is about to hear.
    fake.holdNextResume();
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (!transcript().contains('letsBegin') &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(transcript(), contains('letsBegin'),
        reason: 'the queued round line fired once the label episode ended');

    // While that line is still on the floor, the child answers correctly and
    // ordinary narration is fired in the same breath. The fresh label must
    // win: the guard bypass that let the queued line fire must not leak to
    // this new narration, or it would take the floor and silence the label.
    final label =
        voice.playAnswerLabel(color: 'blue', shape: 'triangle');
    final narration = voice.play(VoiceOverCue.tapHere);

    await label.timeout(const Duration(seconds: 5));
    // The label's player is the one that just resumed: the proof below needs
    // its identity before anything else plays.
    final labelPlayer = fake.lastResumedPlayer;
    fake.releaseResume();
    await narration.timeout(const Duration(seconds: 15));
    await sequence.timeout(const Duration(seconds: 15));

    final spoken = transcript();
    expect(spoken, contains('phraseBlueTriangle'),
        reason: 'narration arriving while the queued line is in flight must '
            'not silence the fresh correct-answer label');
    expect(spoken.indexOf('tapHere'),
        greaterThan(spoken.indexOf('phraseBlueTriangle')),
        reason: 'ordinary narration parks behind the fresh label instead of '
            'cutting it');
    final resumeIndex = fake.eventLog.lastIndexOf('resume:$labelPlayer');
    final completeIndex = fake.eventLog.lastIndexOf('complete:$labelPlayer');
    final cut = fake.eventLog
        .sublist(resumeIndex + 1, completeIndex)
        .any((entry) => entry == 'stop:$labelPlayer');
    expect(cut, isFalse,
        reason: 'once the fresh label is on the air, nothing may stop its '
            'player before its own completion: that is the cut that parks '
            'this narration, and it applies to the narration too');
    expect(spoken.length, before.length + 4,
        reason: 'the stale sequence stops at the floor change: the label and '
            'the narration that followed it are spoken, nothing else');
  }, timeout: const Timeout(Duration(seconds: 25)));
}
