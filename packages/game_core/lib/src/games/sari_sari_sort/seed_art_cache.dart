import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Decoded seed-object picture cards for the Sari-Sari Store Sorting game,
/// held for the process lifetime and keyed by full asset path.
///
/// The cards are the shared "seed" object bank in `shared_ui`
/// (`assets/seed_cards/…`), outside Flame's default `assets/images/` prefix, so
/// this uses an [Images] cache with an empty prefix and full package paths —
/// the same arrangement as `anong_susunod/routine_art_cache.dart` and
/// `anong_nararamdaman/emotion_art_cache.dart`.
///
/// Loading is best-effort by design. An item whose card fails to decode simply
/// keeps its emoji glyph (see [DraggableItem.render]); a child's session must
/// never end because an asset went missing.
class SeedArtCache {
  SeedArtCache._();

  static final Images _images = Images(prefix: '');
  static final Map<String, ui.Image> _decoded = {};

  static bool _loading = false;
  static bool _loaded = false;

  /// True once a load pass has finished, whatever it managed to decode.
  static bool get isLoaded => _loaded;

  /// The decoded card for [path], or null while loading or if it failed.
  static ui.Image? of(String? path) =>
      path == null ? null : _decoded[path];

  /// Decodes each card in [paths]. Safe to call more than once; already-decoded
  /// paths are skipped, so a second game instance pays nothing.
  static Future<void> ensureLoaded(Iterable<String> paths) async {
    if (_loading) return;
    _loading = true;

    for (final path in paths) {
      if (_decoded.containsKey(path)) continue;
      final image = await _tryLoad(path);
      if (image != null) _decoded[path] = image;
    }

    _loading = false;
    _loaded = true;
  }

  static Future<ui.Image?> _tryLoad(String path) async {
    try {
      // Probed through the bundle before Flame is asked for it. [Images.load]
      // memoises the in-flight future, so a failure surfaces twice — once to
      // this catch, and once as an unhandled async error on the memoised
      // future, which a test binding turns into a failed test even though the
      // game itself carried on perfectly well. Asking the bundle directly means
      // a missing card never creates that future in the first place.
      await rootBundle.load(path);
      return await _images.load(path);
    } catch (e) {
      // The emoji glyph covers this one. Worth a log line: an item silently
      // rendering as its emoji instead of the drawn card is easy to miss.
      debugPrint('[SariSari] seed card missing: $path ($e)');
      return null;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _decoded.clear();
    _loaded = false;
    _loading = false;
  }
}
