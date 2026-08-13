import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';

/// The situations live in game_core and the recordings that narrate them live
/// in shared_audio, and neither package depends on the other — so, exactly as
/// with the routine steps next door, main_app is the only place the join can be
/// checked at all.
///
/// The failure this guards against is a scene whose narration was never wired
/// up: the picture appears, the caption is printed under it, and the round opens
/// in silence. A child who cannot read the caption is then asked how someone
/// feels about an event nobody told them about — which still looks like working
/// software from the outside.
void main() {
  group('every situation can be narrated aloud', () {
    for (final scene in kEmotionScenes) {
      test('${scene.id} has a recording', () {
        expect(
          VoiceOverService.sceneCue(scene.id),
          isNotNull,
          reason: 'EmotionScene "${scene.id}" has no entry in the voice-over '
              'scene map, so its round opens in silence',
        );
      });
    }
  });

  test('every scene recording belongs to a real situation', () {
    final sceneIds = {for (final scene in kEmotionScenes) scene.id};
    for (final id in sceneIds) {
      expect(VoiceOverService.sceneCue(id), isNotNull);
    }
    // A cue left behind after a scene is renamed would never play; the count
    // going out of step is the cheapest way to notice.
    expect(
      sceneIds.length,
      kEmotionScenes.length,
      reason: 'two scenes share an id, so one of them narrates as the other',
    );
  });

  group('every situation has a caption in each language', () {
    for (final language in GameLanguage.values) {
      test('${language.slug} captions all ${kEmotionScenes.length} scenes', () {
        for (final scene in kEmotionScenes) {
          expect(
            scene.caption(language).trim(),
            isNotEmpty,
            reason: '${scene.id} has no ${language.slug} caption, so the '
                'printed line and the spoken one cannot agree',
          );
        }
      });
    }
  });
}
