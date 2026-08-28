import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

/// bgm_library.dart is generated from the files install_bgm.py wrote, so the
/// list and the files agree by construction. The thing that can still be wrong
/// is pubspec.yaml: a category folder that is never declared is not in the
/// asset bundle, and `AssetSource` then fails only on-device, as silence.
///
/// This also pins the invariants the parent picker depends on — every category
/// has tracks to choose from, and the default key resolves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('background music is in the asset bundle', () {
    for (final category in kBgmCategories) {
      test('${category.key} bundles every track', () async {
        expect(category.tracks, isNotEmpty,
            reason: '${category.key} would leave the picker with a dead entry');

        for (final track in category.tracks) {
          expect(track.title, isNotEmpty,
              reason: '${track.file} would show as a blank row in the '
                  'settings preview');
          final path = 'packages/shared_audio/assets/audio/'
              '${category.trackPath(track)}';
          final data = await rootBundle.load(path);
          expect(data.lengthInBytes, greaterThan(0),
              reason: '$path is bundled but empty');
        }
      });
    }
  });

  group('category lookup', () {
    test('the default category exists', () {
      expect(bgmCategoryByKey(kDefaultBgmCategory), isNotNull,
          reason: 'kDefaultBgmCategory must name a real category, or every '
              'profile without a stored choice falls back to nothing');
    });

    test('category keys are unique', () {
      final keys = kBgmCategories.map((c) => c.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('an unknown key falls back to the default rather than throwing', () {
      // A profile written by a build that shipped a category this build does
      // not have must still produce music, not a crash or silence.
      expect(bgmCategoryByKey('category_that_was_removed'), isNull);
      expect(bgmCategoryOrDefault('category_that_was_removed').key,
          kDefaultBgmCategory);
      expect(bgmCategoryOrDefault(null).key, kDefaultBgmCategory);
    });
  });
}
