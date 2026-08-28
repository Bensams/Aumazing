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
    // Ano'ng Susunod speaks a routine name as each round opens and a step name
    // on every correct placement; Hintay! speaks its instruction and its
    // escalated prompt. `routines/` is a folder the pubspec had never listed
    // before these games, which is the exact failure this test exists to catch.
    VoiceOverCue.routineMorning,
    VoiceOverCue.stepWashHands,
    VoiceOverCue.waitForTheStar,
    VoiceOverCue.tapTheStar,
    // Sabay Tayo! speaks its instruction as the game opens and its escalated
    // prompt when a gaze has gone unfollowed. Both are the newest cues in the
    // library, so they are the likeliest to have been added to the enum and
    // the asset table without the recordings ever reaching the packs.
    VoiceOverCue.lookWhereImLooking,
    VoiceOverCue.lookOverThere,
    // Kumusta! opens every round with this line, and it is the only thing that
    // tells the child the task is to greet *back* rather than to pick a
    // picture. A pack missing it does not degrade — it changes the game.
    VoiceOverCue.sayHelloBack,
    // The four greeting names Kumusta! speaks as the buddy offers each bid.
    // fistBump is the sample because it is the one whose absence is hardest to
    // notice: it previously borrowed "Now you try", so a missing clip does not
    // fall silent in review, it simply sounds like the old behaviour.
    VoiceOverCue.greetingFistBump,
    // Tulong, Kaibigan! composes its request from `canIHaveThe` plus an item
    // name, and thanks the child with `thankYouFriend`. The composed half is
    // why both are sampled here: a missing `canIHaveThe` does not fall silent,
    // it plays a bare item name — which sounds like the game naming an object
    // rather than a friend asking for one.
    VoiceOverCue.canIHaveThe,
    VoiceOverCue.thankYouFriend,
    // Ano'ng Nararamdaman narrates each situation as it appears, and
    // `emotions/scenes/` is a folder of its own — Flutter's asset globs are not
    // recursive, so listing `emotions/` in the pubspec does not carry it. That
    // is exactly the "on disk but not in the bundle" gap this file exists to
    // catch.
    VoiceOverCue.sceneIceCreamFell,
    // The milestone victory scene draws no written headline — this line *is*
    // the headline, spoken. `milestone/` is a folder of its own that the
    // pubspec had never listed before, the exact "on disk but not bundled" gap
    // this file catches; a pack missing it degrades to "You finished it!".
    VoiceOverCue.milestoneLearningPathComplete,
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

  /// The assessment hand-off is the one screen with no next step the child can
  /// find on their own: the written line is the only instruction, and a
  /// pre-reader cannot use it. A pack missing this recording degrades to the
  /// generic "Wait." cue, which does not say to fetch anyone — so the child
  /// sits there. Checked per pack rather than sampled, because that degrade is
  /// silent-by-design and would never surface as a failure.
  group('the assessment hand-off cue is in the asset bundle', () {
    for (final pack in kVoicePacks) {
      // Lexianne is human-recorded, deliberately incomplete, and not a
      // default; she falls back to ceb_adult_woman. Nothing to bundle.
      if (pack.assetFolder == 'ceb_lexianne') continue;

      test('${pack.id} bundles its own hand-off recording', () async {
        final path = VoiceOverService.assetPathCandidates(
          VoiceOverCue.giveTheDeviceToYourParent,
          pack.assetFolder,
        ).first;
        final data = await rootBundle.load(path);
        expect(data.lengthInBytes, greaterThan(0),
            reason: '$path is bundled but empty');
      });
    }
  });

  test('the end-of-game cheer is bundled', () async {
    final data = await rootBundle
        .load('packages/shared_audio/assets/audio/sfx/cheer_clap.wav');
    expect(data.lengthInBytes, greaterThan(0));
  });
}
