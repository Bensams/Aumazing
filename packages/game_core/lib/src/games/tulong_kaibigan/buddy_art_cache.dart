import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flutter/foundation.dart';

enum BuddyKind { bps, reiz }

enum BuddyPose {
  present(cols: 3, rows: 2, frames: 6),
  celebrate(cols: 4, rows: 3, frames: 12),
  oops(cols: 3, rows: 2, frames: 6),
  encourage(cols: 1, rows: 1, frames: 1);

  const BuddyPose({required this.cols, required this.rows, required this.frames});
  final int cols;
  final int rows;
  final int frames;
}

/// Flame-side character sheets. Missing art is deliberately non-fatal: the
/// buddy component paints a friendly fallback so a packaging mistake can
/// never end a child's session.
///
/// Named for its game rather than the generic `BuddyArtCache` it started as.
/// Sabay Tayo!, Kumusta! and Tulong, Kaibigan! each grew their own version of
/// this loader independently, and all three are exported from the one
/// `game_core` barrel, where a shared class name is an ambiguous export — a
/// collision none of the three branches could hit on its own. They differ only
/// in which sheets they pull and how they slice them, and belong in
/// `games/shared/`; that is a refactor rather than a merge fix.
class TulongBuddyArt {
  TulongBuddyArt._();

  static final Images _images = Images(prefix: '');
  static final Map<String, ui.Image> _decoded = {};
  static bool _loaded = false;

  static ui.Image? of(BuddyKind buddy, BuddyPose pose) =>
      _decoded['${buddy.name}_${pose.name}'];

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    for (final buddy in BuddyKind.values) {
      for (final pose in BuddyPose.values) {
        final key = '${buddy.name}_${pose.name}';
        final path = 'packages/shared_ui/assets/characters/$key.png';
        try {
          _decoded[key] = await _images.load(path);
        } catch (error) {
          debugPrint('[TulongKaibigan] buddy art missing: $path ($error)');
        }
      }
    }
    _loaded = true;
  }

  @visibleForTesting
  static void resetForTest() {
    _decoded.clear();
    _loaded = false;
  }
}
