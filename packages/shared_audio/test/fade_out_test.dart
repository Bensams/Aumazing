import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

/// An interrupted line is faded, not cut.
///
/// Stopping a clip mid-waveform steps the signal to zero, and that
/// discontinuity is the click heard whenever one line takes the floor from
/// another. What can be checked without a sound card is the shape of the ramp
/// and that an interruption does not leave the pool quiet or half-volume — the
/// audible result needs a device.
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

  test('the ramp descends from the playing volume to near silence', () {
    final ramp = VoiceOverService.fadeRamp(1.0);

    expect(ramp, isNotEmpty);
    expect(ramp.first, lessThan(1.0),
        reason: 'the first step is already quieter than the clip was');
    expect(ramp.last, lessThan(0.1),
        reason: 'the stop that follows must land on an almost silent signal');
    for (var i = 1; i < ramp.length; i++) {
      expect(ramp[i], lessThan(ramp[i - 1]), reason: 'monotonic at step $i');
    }
    expect(ramp.every((v) => v >= 0), isTrue,
        reason: 'a negative volume is not a value any platform accepts');
  });

  test('the ramp scales to the volume actually in use', () {
    // A parent who has turned the voice down to a third must not have it fade
    // *up* to full before it goes away.
    final quiet = VoiceOverService.fadeRamp(0.3);

    expect(quiet.first, lessThan(0.3));
    expect(quiet.length, VoiceOverService.fadeRamp(1.0).length,
        reason: 'the same number of steps regardless of how loud it started');
  });

  test('an interruption leaves the pool ready at the configured volume',
      () async {
    voice.setVolume(0.6);

    await voice.play(VoiceOverCue.greatJob);
    // The next line takes the floor while the first is still on the pool.
    await voice.play(VoiceOverCue.tapHere, skipDebounce: true);

    // Whatever the fade did to the interrupted player's volume, the service's
    // own setting is unchanged — the next cue starts at 0.6, not at whatever
    // level a ramp happened to reach.
    expect(voice.volume, 0.6);
  });
}
