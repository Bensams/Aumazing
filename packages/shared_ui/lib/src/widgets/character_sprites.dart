import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Grid layout of one sprite sheet: [cols] × [rows] cells read left-to-right,
/// top-to-bottom, of which the first [frames] cells hold real frames (trailing
/// cells may be empty padding).
class SheetSpec {
  const SheetSpec({
    required this.cols,
    required this.rows,
    required this.frames,
    this.optional = false,
  }) : assert(frames > 0 && frames <= cols * rows);

  final int cols;
  final int rows;
  final int frames;

  /// Whether the character still loads when this sheet is absent.
  ///
  /// A new action is declared here before its art is generated, and the sheets
  /// for the two characters land at different times. Without this, adding a
  /// row to [CharacterSprites.layout] would take the *whole* mascot off screen
  /// until every PNG existed — a far worse failure than one missing gesture,
  /// which simply doesn't play.
  final bool optional;
}

/// Sliced sprite-sheet frames for one mascot character, ready to feed into
/// [CalmMascot] — which stays a plain-Flutter widget and never sees a sheet.
///
/// The sheets live under `assets/characters/` in this package and are sliced
/// once at runtime (then cached process-wide), so adding a character is just
/// two PNGs plus a named constructor below — no offline splitting step.
class CharacterSprites {
  const CharacterSprites._(this._actions);

  /// Frames per action, keyed by the names in [layout].
  final Map<String, List<ImageProvider>> _actions;

  /// The resting pose (first idle frame). Use as `CalmMascot.image`.
  ImageProvider get rest => _actions['idle']!.first;

  /// Slow blink cycle from the idle sheet. Play as an occasional gesture
  /// (`gestureFrames`), not a continuous loop — breathing is the idle motion.
  List<ImageProvider> get blinkFrames => frames('idle');

  /// Wave gesture cycle. Pass as `gestureFrames` and bump `gestureTrigger`
  /// to greet; CalmMascot clamps playback to 3–8 fps and rests afterwards.
  List<ImageProvider> get waveFrames => frames('wave');

  /// Frames for any action in [layout]; empty if that sheet isn't loaded.
  /// Single-frame actions ([still]) return a one-element list.
  List<ImageProvider> frames(String action) =>
      _actions[action] ?? const <ImageProvider>[];

  /// The single pose of a still action (`encourage`, `listen`, `sleepy`,
  /// `think`). Null if the action isn't loaded.
  ImageProvider? still(String action) => _actions[action]?.first;

  /// Grid of every action sheet. All characters share this layout, and all of
  /// a character's sheets share one cell size, so the mascot never changes
  /// size or slides sideways when switching between them.
  static const Map<String, SheetSpec> layout = {
    'idle': SheetSpec(cols: 3, rows: 2, frames: 5),
    'wave': SheetSpec(cols: 4, rows: 3, frames: 12),
    // Stepped in place; horizontal travel belongs to the widget playing it.
    'walk': SheetSpec(cols: 4, rows: 3, frames: 12),
    'celebrate': SheetSpec(cols: 4, rows: 3, frames: 12),
    'nod': SheetSpec(cols: 3, rows: 2, frames: 6),
    'point': SheetSpec(cols: 3, rows: 2, frames: 6),
    // Open palm rather than `point`'s index finger: an invitation to look at
    // something instead of an instruction. Same side as `point`.
    'present': SheetSpec(cols: 3, rows: 2, frames: 6, optional: true),
    // Mouth-only cycle, and unlike every other sheet the frame ORDER carries
    // no meaning — these are distinct mouth openings to shuffle through while
    // a line plays, not a gesture with a beginning and an end.
    'talk': SheetSpec(cols: 3, rows: 2, frames: 6, optional: true),
    // The reaction to a wrong answer. Short on purpose: it is a soft "oh, not
    // quite" that hands straight over to `encourage`, never a sheet the
    // character can sit in. See MascotController.reassure.
    'oops': SheetSpec(cols: 3, rows: 2, frames: 6, optional: true),
    'encourage': SheetSpec(cols: 1, rows: 1, frames: 1),
    'listen': SheetSpec(cols: 1, rows: 1, frames: 1),
    'sleepy': SheetSpec(cols: 1, rows: 1, frames: 1),
    'think': SheetSpec(cols: 1, rows: 1, frames: 1),
  };

  static final Map<String, Future<CharacterSprites>> _cache = {};

  /// BPS, the first mascot.
  static Future<CharacterSprites> bps() => _load('bps');

  /// Reiz.
  static Future<CharacterSprites> reiz() => _load('reiz');

  // Upcoming characters register here once their sheets land:
  // static Future<CharacterSprites> lexianne() => _load('lexianne');

  /// Loads every sheet in [layout] for [name]. Sheets are generated offline by
  /// `scripts/generate_sprites.py`; see that script for the grid contract.
  static Future<CharacterSprites> _load(String name) {
    return _cache.putIfAbsent(name, () async {
      try {
        final actions = <String, List<ImageProvider>>{};
        for (final entry in layout.entries) {
          try {
            actions[entry.key] = await _sliceSheet(
              'packages/shared_ui/assets/characters/${name}_${entry.key}.png',
              entry.value,
            );
          } catch (_) {
            // An optional sheet that hasn't been generated yet leaves that one
            // action empty; callers already treat an empty frame list as "this
            // character can't do that" and skip it.
            if (!entry.value.optional) rethrow;
          }
        }
        return CharacterSprites._(actions);
      } catch (_) {
        // Don't leave a failed load cached: a missing sheet would otherwise
        // keep the character permanently broken for the rest of the process,
        // even after a hot reload that fixes the asset.
        _cache.remove(name);
        rethrow;
      }
    });
  }

  /// Decodes [assetKey], cuts the uniform grid, and re-encodes each used cell
  /// as its own in-memory PNG. Runs once per character per process.
  static Future<List<ImageProvider>> _sliceSheet(
      String assetKey, SheetSpec spec) async {
    final data = await rootBundle.load(assetKey);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final sheet = (await codec.getNextFrame()).image;
    final frameWidth = sheet.width ~/ spec.cols;
    final frameHeight = sheet.height ~/ spec.rows;

    final frames = <ImageProvider>[];
    for (var i = 0; i < spec.frames; i++) {
      final src = ui.Rect.fromLTWH(
        (i % spec.cols) * frameWidth.toDouble(),
        (i ~/ spec.cols) * frameHeight.toDouble(),
        frameWidth.toDouble(),
        frameHeight.toDouble(),
      );
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        sheet,
        src,
        ui.Rect.fromLTWH(0, 0, frameWidth.toDouble(), frameHeight.toDouble()),
        ui.Paint(),
      );
      final frame =
          await recorder.endRecording().toImage(frameWidth, frameHeight);
      final png = await frame.toByteData(format: ui.ImageByteFormat.png);
      frame.dispose();
      frames.add(MemoryImage(png!.buffer.asUint8List()));
    }
    sheet.dispose();
    return frames;
  }
}
