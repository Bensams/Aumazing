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

  /// Whether this character can track a point on screen — i.e. both gaze
  /// poses have been generated. Callers fall back to the resting pose.
  bool get canGaze =>
      still('look_left') != null && still('look_right') != null;

  /// The gaze pose for a point ([x], [y]) of the way across and down the
  /// screen, (0,0) being the top-left corner. Null if this character has no
  /// gaze poses at all.
  ///
  /// A 3x3 grid of held poses with the resting frame at its centre. The
  /// middle band on each axis is deliberately a full third: it keeps the
  /// character from staring off into a corner while a child drags around the
  /// middle of the screen, which is where most of a drag happens.
  ///
  /// Missing corners degrade rather than disappear — a character with only the
  /// horizontal poses generated still tracks left and right instead of
  /// dropping to the rest frame the moment a drag strays high or low.
  ImageProvider? gazeFrameFor(double x, double y) {
    if (!canGaze) return null;
    final col = _band(x);
    final row = _band(y);
    if (col == 0 && row == 0) return rest;
    return still(_gazeAction(row, col)) ??
        still(_gazeAction(0, col)) ??
        still(_gazeAction(row, 0)) ??
        rest;
  }

  /// -1 (near edge), 0 (middle third), or 1 (far edge).
  static int _band(double v) {
    final at = v.clamp(0.0, 1.0);
    if (at < 1 / 3) return -1;
    if (at > 2 / 3) return 1;
    return 0;
  }

  /// Sheet name for a grid cell, e.g. (-1, 1) -> `look_up_right`.
  static String _gazeAction(int row, int col) {
    final vertical = row < 0 ? 'up' : (row > 0 ? 'down' : '');
    final horizontal = col < 0 ? 'left' : (col > 0 ? 'right' : '');
    final parts = [vertical, horizontal].where((s) => s.isNotEmpty);
    return 'look_${parts.join('_')}';
  }

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
    // The gaze poses: an extreme side-eye toward each edge and corner of the
    // screen, forming a 3x3 grid with the idle rest frame at its centre. Named
    // for the direction the CHILD sees, not the one the character would feel.
    //
    // Held stills rather than a sweep because that is what the generator will
    // actually produce — see scripts/SPRITES.md. Nine cells is still coarse,
    // so [Mascot] layers a continuous lean over them rather than relying on
    // the eyes alone.
    'look_left': SheetSpec(cols: 1, rows: 1, frames: 1, optional: true),
    'look_right': SheetSpec(cols: 1, rows: 1, frames: 1, optional: true),
    'look_up': SheetSpec(cols: 1, rows: 1, frames: 1, optional: true),
    'look_down': SheetSpec(cols: 1, rows: 1, frames: 1, optional: true),
    'look_up_left': SheetSpec(cols: 1, rows: 1, frames: 1, optional: true),
    'look_up_right': SheetSpec(cols: 1, rows: 1, frames: 1, optional: true),
    'look_down_left': SheetSpec(cols: 1, rows: 1, frames: 1, optional: true),
    'look_down_right': SheetSpec(cols: 1, rows: 1, frames: 1, optional: true),
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
