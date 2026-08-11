import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

/// check_library.py verifies the cue files exist on disk. This verifies the
/// separate thing that can still be wrong afterwards: that pubspec.yaml
/// actually declares the folder, so the file is in the asset bundle and
/// `AssetSource` can find it at runtime. A cue that exists but is not bundled
/// fails only on-device, as silence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// One representative cue per new naming family, plus the colour and shape
  /// cues that were unreachable until this change.
  const sampleCues = [
    VoiceOverCue.letterA,
    VoiceOverCue.numberThree,
    VoiceOverCue.itemGatas,
    VoiceOverCue.colorGold,
    VoiceOverCue.shapeHeart,
    // The Sari-Sari toy shelf: these four are the whole `toys` category, so a
    // missing clip is silence on every correct answer in that bin.
    VoiceOverCue.itemBola,
    VoiceOverCue.itemManika,
    VoiceOverCue.itemKotse,
    VoiceOverCue.itemTeddy,
  ];

  group('naming cues are in the asset bundle', () {
    for (final pack in kVoicePacks) {
      // The human-recorded Lexianne pack never had these cues and is not a
      // default, so it falls back to `ceb_adult_woman` — nothing to bundle.
      if (pack.assetFolder == 'ceb_lexianne') continue;

      test('${pack.id} bundles every sampled naming cue', () async {
        for (final cue in sampleCues) {
          final path =
              VoiceOverService.assetPathCandidates(cue, pack.assetFolder).first;
          final data = await rootBundle.load(path);
          expect(data.lengthInBytes, greaterThan(0),
              reason: '$path is bundled but empty');
        }
      });
    }
  });

  test('the end-of-game cheer is bundled', () async {
    final data = await rootBundle
        .load('packages/shared_audio/assets/audio/sfx/cheer_clap.wav');
    expect(data.lengthInBytes, greaterThan(0));
  });
}
