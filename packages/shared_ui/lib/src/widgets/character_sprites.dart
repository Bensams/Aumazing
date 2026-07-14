import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Grid layout of one sprite sheet: [cols] × [rows] cells read left-to-right,
/// top-to-bottom, of which the first [frames] cells hold real frames (trailing
/// cells may be empty padding).
class SheetSpec {
  const SheetSpec({required this.cols, required this.rows, required this.frames})
      : assert(frames > 0 && frames <= cols * rows);

  final int cols;
  final int rows;
  final int frames;
}

/// Sliced sprite-sheet frames for one mascot character, ready to feed into
/// [CalmMascot] — which stays a plain-Flutter widget and never sees a sheet.
///
/// The sheets live under `assets/characters/` in this package and are sliced
/// once at runtime (then cached process-wide), so adding a character is just
/// two PNGs plus a named constructor below — no offline splitting step.
class CharacterSprites {
  const CharacterSprites._({
    required this.rest,
    required this.blinkFrames,
    required this.waveFrames,
  });

  /// The resting pose (first idle frame). Use as `CalmMascot.image`.
  final ImageProvider rest;

  /// Slow blink cycle from the idle sheet. Play as an occasional gesture
  /// (`gestureFrames`), not a continuous loop — breathing is the idle motion.
  final List<ImageProvider> blinkFrames;

  /// Wave gesture cycle. Pass as `gestureFrames` and bump `gestureTrigger`
  /// to greet; CalmMascot clamps playback to 3–8 fps and rests afterwards.
  final List<ImageProvider> waveFrames;

  static final Map<String, Future<CharacterSprites>> _cache = {};

  /// BPS, the first mascot: 3×2 idle sheet (5 blink frames), 4×3 wave sheet
  /// (12 frames).
  static Future<CharacterSprites> bps() => _load(
        'bps',
        idle: const SheetSpec(cols: 3, rows: 2, frames: 5),
        wave: const SheetSpec(cols: 4, rows: 3, frames: 12),
      );

  // Upcoming characters (e.g. reiz) register here once their sheets land:
  // static Future<CharacterSprites> reiz() => _load('reiz', idle: ..., wave: ...);

  static Future<CharacterSprites> _load(
    String name, {
    required SheetSpec idle,
    required SheetSpec wave,
  }) {
    return _cache.putIfAbsent(name, () async {
      final idleFrames = await _sliceSheet(
          'packages/shared_ui/assets/characters/${name}_idle.png', idle);
      final waveFrames = await _sliceSheet(
          'packages/shared_ui/assets/characters/${name}_wave.png', wave);
      return CharacterSprites._(
        rest: idleFrames.first,
        blinkFrames: idleFrames,
        waveFrames: waveFrames,
      );
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
