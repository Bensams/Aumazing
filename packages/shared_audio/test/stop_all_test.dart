import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

import 'mock_audio_channels.dart';

/// [VoiceOverService.stopAll] silences every live narrator when the app
/// blurs.
///
/// Voice-over instances are per-screen and not lifecycle-observed, so the
/// BGM pauser cannot reach them: each screen builds its own service and
/// keeps its own pool of players. [stopAll] is the one wedge that sees
/// across that boundary, iterating the shared [_live] registry.
///
/// These tests run against the real [AudioplayersPlatform] adapter with
/// [MockAudioChannels] standing in for the native side, so a "stop" is a
/// real crossing of the method channel, not an authoritative state flip.
///
/// The mock's stop tally is cumulative for the life of the suite, so
/// assertions are deltas not absolutes, and dispose() on the real
/// [AudioPlayer] issues native stops — the "disposed is skipped" test has to
/// prove stopAll adds *nothing* to the disposed instance, not that it has no
/// stops at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    // native prepare; without the mock every setSource fails.
    messenger.setMockMethodCallHandler(
      MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
  });

  test('stopAll with no live instances is a safe no-op', () async {
    // No service is constructed in this test, so the registry is empty.
    final stopsBefore = mock.totalStopCalls();

    await VoiceOverService.stopAll();

    expect(
      mock.totalStopCalls(),
      stopsBefore,
      reason:
          'nothing to stop: stopAll must not throw or add stop calls to '
          'the channel',
    );
  });

  test('stopAll stops every live instance\'s players', () async {
    final a = VoiceOverService(languageCode: 'en_adult_woman');
    final b = VoiceOverService(languageCode: 'en_adult_woman');

    // Give each live service a player that is (or was) speaking, so a stop
    // has a real native target. b takes the floor after a, so A's player may
    // already carry a floor-contention stop — bPlayer is the clean witness.
    await a.play(VoiceOverCue.tapHere);
    await pumpEventQueue();
    final aPlayer = mock.lastResumedPlayer;
    await b.play(VoiceOverCue.greatJob);
    await pumpEventQueue();
    final bPlayer = mock.lastResumedPlayer;

    final aStopsBefore = mock.stopCallsFor(aPlayer!);
    final bStopsBefore = mock.stopCallsFor(bPlayer!);

    await VoiceOverService.stopAll();

    expect(
      mock.stopCallsFor(bPlayer),
      greaterThan(bStopsBefore),
      reason:
          'the most recent live service\'s players are stopped by '
          'stopAll',
    );
    expect(
      mock.stopCallsFor(aPlayer),
      greaterThan(aStopsBefore),
      reason: 'stopAll reaches the earlier live service\'s players too',
    );

    await a.dispose();
    await b.dispose();
  });

  test('a disposed instance is not in _live and is not stopped', () async {
    final disposed = VoiceOverService(languageCode: 'en_adult_woman');
    await disposed.play(VoiceOverCue.tapHere);
    await pumpEventQueue();
    final disposedPlayer = mock.lastResumedPlayer!;
    await disposed.dispose();
    // dispose() issues native stops on the real AudioPlayer; let them settle
    // so the delta below is attributable only to stopAll.
    await pumpEventQueue();
    final disposedStopsAfterDispose = mock.stopCallsFor(disposedPlayer);

    // A live instance behind the disposed one: stopAll must stop it and only
    // it.
    final live = VoiceOverService(languageCode: 'en_adult_woman');
    await live.play(VoiceOverCue.greatJob);
    await pumpEventQueue();
    final livePlayer = mock.lastResumedPlayer!;

    await VoiceOverService.stopAll();

    expect(
      mock.stopCallsFor(disposedPlayer),
      disposedStopsAfterDispose,
      reason:
          'dispose() removed the instance from _live; stopAll skips it '
          'and adds no stops to its players',
    );
    expect(
      mock.stopCallsFor(livePlayer),
      greaterThan(0),
      reason: 'a live instance is still stopped by stopAll',
    );

    await live.dispose();
  });
}
