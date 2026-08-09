import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

void main() {
  // A typo in a logoAsset path is invisible at runtime: GameLogo quietly draws
  // the fallback icon instead. So the paths are checked against the files on
  // disk here rather than being trusted.
  test('every game points at logo artwork that exists', () {
    const prefix = 'packages/shared_ui/';
    for (final entry in GameRegistry.games) {
      expect(entry.logoAsset, startsWith(prefix),
          reason: '${entry.id}: logos live in the shared_ui bundle');
      // Tests run from packages/game_core, so resolve the package path to the
      // sibling checkout.
      final onDisk =
          File('../shared_ui/${entry.logoAsset.substring(prefix.length)}');
      expect(onDisk.existsSync(), isTrue,
          reason: '${entry.id}: missing ${entry.logoAsset}');
    }
  });
}
