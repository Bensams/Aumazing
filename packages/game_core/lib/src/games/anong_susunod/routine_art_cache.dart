import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flutter/foundation.dart';

import 'routine_steps.dart';

/// Decoded routine-card pictures, held for the lifetime of the process.
///
/// The cards are bundled in `shared_ui`, outside Flame's default
/// `assets/images/` prefix, so this uses an [Images] cache with an empty prefix
/// and full package paths.
///
/// Loading is best-effort by design. If a picture fails to decode we simply
/// leave it out and the caller falls back to [RoutineArtPainter]; a child's
/// session must never end because an asset went missing.
class RoutineArtCache {
  RoutineArtCache._();

  static final Images _images = Images(prefix: '');
  static final Map<RoutineArt, ui.Image> _decoded = {};

  static bool _loading = false;
  static bool _loaded = false;

  /// True once a load pass has finished, whatever it managed to decode.
  static bool get isLoaded => _loaded;

  /// The picture for [art], or null while loading or if it failed to decode.
  static ui.Image? of(RoutineArt art) => _decoded[art];

  /// Decodes every card picture. Safe to call more than once.
  static Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;

    for (final art in RoutineArt.values) {
      try {
        _decoded[art] = await _images.load(art.assetPath);
      } catch (e) {
        // Fallback art covers this one. Worth a log line: a card silently
        // rendering as the painted version is easy to miss in review.
        debugPrint('[AnongSusunod] card art missing: ${art.assetPath} ($e)');
      }
    }

    _loading = false;
    _loaded = true;
  }

  @visibleForTesting
  static void resetForTest() {
    _decoded.clear();
    _loaded = false;
    _loading = false;
  }
}

/// Draws [art] into a [size] × [size] box at [origin], preferring the bundled
/// picture and falling back to the painted version.
///
/// Cards are square and pre-trimmed, so the picture fills the box directly with
/// no letterboxing arithmetic needed here.
void drawRoutineArt(
  ui.Canvas canvas,
  RoutineArt art,
  ui.Offset origin,
  double size,
) {
  final image = RoutineArtCache.of(art);
  if (image == null) {
    RoutineArtPainter.paint(canvas, art, origin, size);
    return;
  }

  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    ui.Rect.fromLTWH(origin.dx, origin.dy, size, size),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
}
