import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flutter/foundation.dart';

/// One buddy's sprite sheets, decoded for use inside Flame.
///
/// `CharacterSprites` in shared_ui is Flutter-side — it hands back
/// [ImageProvider]s, which a Flame component cannot draw — so this mirrors the
/// pattern `anong_susunod/routine_art_cache.dart` established: an [Images]
/// cache with an empty prefix and full package paths, loaded best-effort.
///
/// Best-effort matters more here than it does for a routine card. The buddy is
/// the game: if a sheet is missing the game still runs, drawing a painted
/// stand-in (see `components/buddy.dart`), because a child's session must never
/// end because an asset went missing.
///
/// Named for its game rather than the generic `BuddyArtCache` it started as:
/// Sabay Tayo!, Kumusta! and Tulong, Kaibigan! each grew their own version of
/// this loader independently, and all three are exported from the one
/// `game_core` barrel, where a shared name is an ambiguous export. They should
/// be unified into `games/shared/` — they differ only in which sheets they
/// pull and how they slice them — but that is a refactor, not a merge fix.
class KumustaBuddyArt {
  KumustaBuddyArt._(this.character, this._sheets, this._layout);

  /// `bps` or `reiz`. One character for a whole session — never both, so the
  /// child is greeting *someone* rather than a rotating cast.
  final String character;

  final Map<String, ui.Image> _sheets;
  final Map<String, _Grid> _layout;

  static final Images _images = Images(prefix: '');

  /// Resolved caches, and the in-flight loads that produce them.
  ///
  /// The resolved instance is kept separately from its future so a second
  /// [load] hands back a *fresh* future rather than the original one. A future
  /// completed in an earlier zone never fires its callbacks inside a widget
  /// test's `fake_async` zone, which would hang `onLoad` forever — silently,
  /// and only under test.
  static final Map<String, KumustaBuddyArt> _ready = {};
  static final Map<String, Future<KumustaBuddyArt>> _inFlight = {};

  /// Grids of the sheets this game plays. Mirrors `CharacterSprites.layout`;
  /// duplicated rather than imported because that map is a Flutter-side
  /// constant and game_core must be able to cut a sheet without it.
  static const Map<String, _Grid> _grids = {
    'idle': _Grid(3, 2, 5),
    'wave': _Grid(4, 3, 12),
    'present': _Grid(3, 2, 6),
    'celebrate': _Grid(4, 3, 12),
    // Dedicated greeting art. Present for bps only so far; absent sheets load
    // best-effort and Greeting.fallbackAction covers the gap.
    'high_five': _Grid(3, 2, 6),
    'fist_bump': _Grid(3, 2, 6),
    'encourage': _Grid(1, 1, 1),
    'nod': _Grid(3, 2, 6),
    'walk': _Grid(4, 3, 12),
  };

  /// Loads [character]'s sheets once per process.
  static Future<KumustaBuddyArt> load(String character) {
    final ready = _ready[character];
    if (ready != null) return SynchronousFuture(ready);

    return _inFlight.putIfAbsent(character, () async {
      final sheets = <String, ui.Image>{};
      for (final action in _grids.keys) {
        final path =
            'packages/shared_ui/assets/characters/${character}_$action.png';
        try {
          sheets[action] = await _images.load(path);
        } catch (e) {
          // The painted stand-in covers this action. Worth a log line: a buddy
          // silently falling back is easy to miss in review.
          debugPrint('[Kumusta] sheet missing: $path ($e)');
        }
      }
      final cache = KumustaBuddyArt._(character, sheets, _grids);
      _ready[character] = cache;
      _inFlight.remove(character);
      return cache;
    });
  }

  /// Whether [action] decoded and can be drawn.
  bool has(String action) => _sheets.containsKey(action);

  /// Number of frames in [action], or 0 when it is unavailable.
  int frameCount(String action) =>
      _sheets.containsKey(action) ? (_layout[action]?.frames ?? 0) : 0;

  /// Draws frame [index] of [action] into [dest], letterboxed to preserve the
  /// character's proportions.
  ///
  /// Returns false when the sheet is absent, which is the caller's cue to paint
  /// the fallback instead.
  bool drawFrame(
    ui.Canvas canvas,
    String action,
    int index,
    ui.Rect dest,
  ) {
    final sheet = _sheets[action];
    final grid = _layout[action];
    if (sheet == null || grid == null) return false;

    final i = index % grid.frames;
    final cellW = sheet.width / grid.cols;
    final cellH = sheet.height / grid.rows;
    final src = ui.Rect.fromLTWH(
      (i % grid.cols) * cellW,
      (i ~/ grid.cols) * cellH,
      cellW,
      cellH,
    );

    // Cells are taller than they are wide; fitting to height and centring
    // keeps the buddy the same size across every sheet, which is the whole
    // point of the shared cell geometry (see scripts/SPRITES.md).
    final scale = dest.height / cellH;
    final w = cellW * scale;
    final fitted = ui.Rect.fromLTWH(
      dest.center.dx - w / 2,
      dest.top,
      w,
      dest.height,
    );

    canvas.drawImageRect(
      sheet,
      src,
      fitted,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    return true;
  }

  @visibleForTesting
  static void resetForTest() {
    _ready.clear();
    _inFlight.clear();
  }
}

class _Grid {
  const _Grid(this.cols, this.rows, this.frames);
  final int cols;
  final int rows;
  final int frames;
}
