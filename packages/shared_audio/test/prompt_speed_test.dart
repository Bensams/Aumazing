import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

/// "Prompt speed" is a parent-facing percentage; what it has to do is change
/// the pace the voice-over actually speaks at. These tests pin the mapping
/// between the two, and that neither end of the slider can produce a rate
/// that would silence or garble a cue.
void main() {
  // The service builds its player pool in the constructor, which reaches the
  // audioplayers platform channels.
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('full speed plays cues at the recorded pace', () {
    expect(voiceRateForPromptSpeed(1.0), 1.0);
  });

  test('the slowest setting stretches speech, it does not stop it', () {
    // A naive rate == promptSpeed mapping would hand the player 0.0 here and
    // the child would hear nothing at all.
    expect(voiceRateForPromptSpeed(0.0), closeTo(0.6, 1e-9));
  });

  test('speed moves monotonically with the setting', () {
    expect(voiceRateForPromptSpeed(0.25),
        lessThan(voiceRateForPromptSpeed(0.75)));
    expect(voiceRateForPromptSpeed(0.75), lessThan(voiceRateForPromptSpeed(1)));
  });

  test('out-of-range settings are clamped rather than trusted', () {
    expect(voiceRateForPromptSpeed(-1), closeTo(0.6, 1e-9));
    expect(voiceRateForPromptSpeed(9), 1.0);
  });

  test('the service clamps the rate it is given', () {
    final service = VoiceOverService(speed: 5.0);
    addTearDown(service.dispose);
    expect(service.speed, 1.5);

    service.setSpeed(0.01);
    expect(service.speed, 0.5);

    service.setSpeed(0.8);
    expect(service.speed, 0.8);
  });
}
