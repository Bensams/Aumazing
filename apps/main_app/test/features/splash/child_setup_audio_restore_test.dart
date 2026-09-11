import 'package:aumazing/features/splash/auth/child_profile_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';

/// Adding a sibling borrows the parent's audio session for previews, then
/// gives it back: the original track resumes AND the service reports the
/// original category. `playMusic` has no category context, so a preview of a
/// different style must not leak its category into the resumed session — the
/// dashboard's category check would restart the track that just came back.
void main() {
  testWidgets(
    'restoring after a different-style preview puts the original category back',
    (tester) async {
      final audio = _RecordingAudioService();
      audio.category = bgmCategoryOrDefault('calm').key;
      audio.track = bgmCategoryOrDefault(
        'calm',
      ).trackPath(bgmCategoryOrDefault('calm').tracks.first);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AudioService>.value(value: audio),
            Provider<HapticService>.value(value: _FakeHapticService()),
          ],
          child: const MaterialApp(home: ChildProfileSetupScreen.addAnother()),
        ),
      );
      await tester.pump();

      // Snapshot before the preview mutates the live fields.
      final originalTrack = audio.track;
      final originalCategory = audio.category;

      // The parent auditions a track from another style before dismissing.
      final playful = bgmCategoryOrDefault('playful');
      await audio.playCategoryTrack(playful, playful.tracks.first);
      expect(
        audio.category,
        playful.key,
        reason: 'precondition: the preview moved the category',
      );

      // Dismiss: swap the tree so the sibling screen is disposed — the
      // dispose path runs the same restore the save path does.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(
        audio.calls,
        contains('playMusic:$originalTrack'),
        reason: 'the track that was playing before setup must resume',
      );
      expect(
        audio.calls,
        contains('setCurrentCategory:$originalCategory'),
        reason:
            'the resumed session must report the original category, not the '
            'previewed style, or the dashboard restarts the track',
      );
      expect(audio.category, originalCategory);
      expect(audio.currentTrack, originalTrack);
    },
  );
}

class _RecordingAudioService implements AudioService {
  @override
  AudioConfig config = AudioConfig.defaults;
  bool playing = true;
  String? track;
  String? category;
  final List<String> calls = [];

  @override
  bool get isMusicPlaying => playing;

  @override
  String? get currentTrack => track;

  @override
  String? get currentCategory => category;

  @override
  void updateConfig(AudioConfig config) => this.config = config;

  @override
  Future<void> playMusic(String trackName) async {
    track = trackName;
    playing = true;
    calls.add('playMusic:$trackName');
  }

  @override
  Future<void> stopMusic() async {
    playing = false;
    track = null;
    category = null;
    calls.add('stopMusic');
  }

  @override
  Future<void> playCategoryTrack(BgmCategory category, BgmTrack track) async {
    if (!config.musicEnabled) return;
    this.category = category.key;
    this.track = category.trackPath(track);
    calls.add('playCategoryTrack:${category.key}');
  }

  @override
  void setCurrentCategory(String? categoryKey) {
    category = categoryKey;
    calls.add('setCurrentCategory:$categoryKey');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHapticService implements HapticService {
  @override
  HapticConfig config = HapticConfig.defaults;

  @override
  void updateConfig(HapticConfig config) => this.config = config;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
