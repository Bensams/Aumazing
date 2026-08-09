import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/screens/audio_tester_screen.dart';
import 'package:game_lab/services/game_lab_services.dart';
import 'package:shared_audio/shared_audio.dart';

/// The Audio Tester is how the music library actually gets auditioned before
/// it ships, so a track missing from this screen means a track nobody checks.
/// This pins that every category and every track has a control.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // audioplayers is a plugin, so it has no implementation in the test VM.
  // Stub its channels: this screen is being tested for what it renders, not
  // for whether audio actually comes out.
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in const [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        // `create` is the only call whose return value the plugin inspects.
        return null;
      });
    }
    GameLabServices.instance.initialize();
  });

  Future<void> pumpTester(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AudioTesterScreen()),
    );
    await tester.pump();
  }

  testWidgets('every shipped track has a play control', (tester) async {
    // Tall enough that the scrolling panel lays out its whole child list.
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpTester(tester);

    for (final category in kBgmCategories) {
      expect(find.textContaining(category.label), findsWidgets,
          reason: '${category.key} has no heading in the tester');

      for (final track in category.tracks) {
        expect(find.text(track.title), findsOneWidget,
            reason: '${track.file} is shipped but cannot be auditioned');
      }
    }
  });

  testWidgets('stop is disabled until something is playing', (tester) async {
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpTester(tester);

    final stop = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Stop Music'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(stop.onPressed, isNull,
        reason: 'nothing is playing yet, so Stop should be inert');
  });
}
