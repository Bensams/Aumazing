import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

import 'mock_audio_channels.dart';

/// The tail of a sequence survives an immediate-feedback floor grab (AUM-316).
///
/// `playSceneCaption(id, alsoAsk: true)` speaks the scene caption and the
/// "How is he feeling?" question as ONE `playSequence`. When the child's fast
/// tap fires the correct/wrong label mid-caption, the label takes the floor
/// and the sequence used to lose its tail — the question silently vanished,
/// and the child was left with a picture nobody asked them about.
///
/// Now the unspoken tail re-queues in the single narration slot: it waits the
/// feedback episode out and speaks after it — unless a full narration (not
/// feedback) claimed the floor, in which case the tail is stale by design and
/// must stay dropped.
///
/// The caption is held mid-playback with [MockAudioChannels.holdNextResume]:
/// the resume call blocks, so the sequence is provably between its cues when
/// the label grabs the floor. What reached the speaker is witnessed by
/// [VoiceOverService.spokenCues].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoiceOverService voice;
  late MockAudioChannels mock;

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    mock = MockAudioChannels(messenger);
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

  /// Pumps until [predicate] holds, or the deadline passes — one
  /// [pumpEventQueue] is not enough to walk prepare/play/resume through the
  /// real adapter.
  Future<void> poll(bool Function() predicate,
      {Duration limit = const Duration(seconds: 8)}) async {
    final deadline = DateTime.now().add(limit);
    while (!predicate() && DateTime.now().isBefore(deadline)) {
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  test('a fast tap mid-caption does not swallow the instruction question',
      () async {
    // Hold the caption in playback: the sequence is between its cues.
    mock.holdNextResume();
    final caption = voice.playSceneCaption('ice_cream_fell', alsoAsk: true);
    await poll(() => transcript().contains('sceneIceCreamFell'),
        limit: const Duration(seconds: 2));
    expect(transcript(), contains('sceneIceCreamFell'),
        reason: 'precondition: the caption is the cue currently on the air');
    expect(voice.isImmediateFeedbackActive, isFalse);

    // The fast tap: the correct-answer label claims the floor mid-caption.
    final label = voice.playAnswerLabel(color: 'red', shape: 'star');
    await pumpEventQueue();
    expect(voice.isImmediateFeedbackActive, isTrue,
        reason: 'precondition: the label owns the floor');

    // The caption's player await must settle LATE — past the three-second
    // feedback hold. On a real device the label's fade-out never completes
    // the caption's player, so the clip-completion backstop does, long after
    // the hold expired; the tail must still be re-queued, because what
    // matters is THAT the floor was claimed as feedback, not that the hold
    // is still open. Holding the release here reproduces exactly that.
    await Future<void>.delayed(const Duration(milliseconds: 3500));
    mock.releaseResume();
    await label.timeout(const Duration(seconds: 8));
    await caption.timeout(const Duration(seconds: 8));

    await poll(() => transcript().contains('howIsHeFeeling'));
    final full = transcript();
    expect(full, contains('phraseRedStar'),
        reason: 'the tap label spoke when it claimed the floor');
    expect(full, contains('howIsHeFeeling'),
        reason: 'the instruction question must survive a mid-caption tap — '
            'a child left with a picture and no question cannot answer it');
    expect(full.lastIndexOf('phraseRedStar'),
        lessThan(full.indexOf('howIsHeFeeling')),
        reason: 'the question speaks after the label, never on top of it');
  });

  test('a full narration taking the floor still drops the tail as stale',
      () async {
    mock.holdNextResume();
    final caption = voice.playSceneCaption('ice_cream_fell', alsoAsk: true);
    await poll(() => transcript().contains('sceneIceCreamFell'),
        limit: const Duration(seconds: 2));
    expect(transcript(), contains('sceneIceCreamFell'),
        reason: 'precondition: the caption is the cue currently on the air');

    // Not feedback: another scene's narration takes the floor outright. A
    // narration superseding a sequence is last-wins — the tail is the
    // child's previous context and must stay dropped. (A transition line
    // would NOT do here: it waits for current speech instead of claiming.)
    final interrupter = voice.playSceneCaption('gift');
    await poll(() => transcript().contains('sceneGift'),
        limit: const Duration(seconds: 2));
    expect(voice.isImmediateFeedbackActive, isFalse,
        reason: 'precondition: the claimant is a narration, not feedback');

    mock.releaseResume();
    await caption.timeout(const Duration(seconds: 8));
    await interrupter.timeout(const Duration(seconds: 8));

    final full = transcript();
    expect(full, contains('sceneIceCreamFell'),
        reason: 'the caption itself was heard before the interruption');
    expect(full, contains('sceneGift'),
        reason: 'the superseding narration spoke');
    expect(full, isNot(contains('howIsHeFeeling')),
        reason: 'a narration-owned floor makes the tail stale by design — '
            'the game re-triggers what it still needs');
  });
}
