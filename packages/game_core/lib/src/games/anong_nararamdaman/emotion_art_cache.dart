import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'emotion_art_painter.dart';
import 'emotions.dart';

/// Decoded picture assets for Ano'ng Nararamdaman?, held for the process
/// lifetime.
///
/// Modelled on `RoutineArtCache`: the cards are bundled in `shared_ui`, outside
/// Flame's default `assets/images/` prefix, so this uses an [Images] cache with
/// an empty prefix and full package paths.
///
/// Loading is best-effort, and here that is load-bearing rather than tidy. The
/// other games degrade to a painted placeholder and remain playable; this one
/// cannot be played at all without a legible face, so [EmotionFacePainter]
/// draws a *real* schematic expression — mouth curve, brow angle, eye size per
/// emotion — and the game is still answerable with every PNG missing. A child's
/// session must never end because an asset went missing, and in this game that
/// promise costs more than a coloured box.
class EmotionArtCache {
  EmotionArtCache._();

  static final Images _images = Images(prefix: '');
  static final Map<FaceArt, ui.Image> _faces = {};
  static final Map<SceneArt, ui.Image> _scenes = {};
  static final Map<ResponseArt, ui.Image> _responses = {};

  static bool _loading = false;
  static bool _loaded = false;

  /// True once a load pass has finished, whatever it managed to decode.
  static bool get isLoaded => _loaded;

  static ui.Image? face(FaceArt art) => _faces[art];
  static ui.Image? scene(SceneArt art) => _scenes[art];
  static ui.Image? response(ResponseArt art) => _responses[art];

  /// Decodes every picture. Safe to call more than once.
  static Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;

    for (final art in FaceArt.values) {
      final image = await _tryLoad(art.assetPath);
      if (image != null) _faces[art] = image;
    }
    for (final art in SceneArt.values) {
      final image = await _tryLoad(art.assetPath);
      if (image != null) _scenes[art] = image;
    }
    for (final art in ResponseArt.values) {
      final image = await _tryLoad(art.assetPath);
      if (image != null) _responses[art] = image;
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
      // The painted fallback covers this one. Worth a log line: a card silently
      // rendering as the schematic version is easy to miss in review.
      debugPrint('[AnongNararamdaman] card art missing: $path ($e)');
      return null;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _faces.clear();
    _scenes.clear();
    _responses.clear();
    _loaded = false;
    _loading = false;
  }
}

/// Draws a face in a [size] × [size] box at [origin], somewhere between neutral
/// and [emotion].
///
/// [t] is the transition the buddy plays as a round opens: 0 is the rest pose,
/// 1 is the full expression. The movement is the point — see the note on
/// [FaceArt.neutral].
///
/// The bundled pictures always cross-fade, because that is all two PNGs can do.
/// The painted fallback normally *interpolates the geometry*, which is the
/// better reading of the same idea — you watch the brows go up. With
/// [crossFade] it cross-fades instead, which is what `GameMotion.reduced` asks
/// for: the before-and-after is preserved without anything on screen moving.
void drawFace(
  ui.Canvas canvas,
  Emotion emotion,
  ui.Offset origin,
  double size, {
  double t = 1.0,
  bool crossFade = false,
}) {
  final amount = t.clamp(0.0, 1.0);
  final target = EmotionArtCache.face(emotion.face);
  final neutral = EmotionArtCache.face(FaceArt.neutral);

  // Both pictures present: cross-fade, which is what the transition looks like
  // for the shipped art.
  if (target != null && neutral != null) {
    if (amount >= 1.0) {
      _drawImage(canvas, target, origin, size);
      return;
    }
    _drawImage(canvas, neutral, origin, size);
    if (amount > 0) _drawImage(canvas, target, origin, size, opacity: amount);
    return;
  }

  // Only the expression itself decoded: fade it up from nothing rather than
  // holding a blank box where a face should be.
  if (target != null) {
    _drawImage(canvas, target, origin, size, opacity: amount.clamp(0.35, 1.0));
    return;
  }

  if (!crossFade || amount >= 1.0 || amount <= 0.0) {
    EmotionFacePainter.paint(canvas, emotion, origin, size, t: amount);
    return;
  }

  // Painted fallback under reduced motion: two still drawings, one fading over
  // the other. The layer is what keeps the emotion's own outlines from showing
  // through the neutral face underneath as a doubled sketch.
  EmotionFacePainter.paint(canvas, emotion, origin, size, t: 0);
  canvas.saveLayer(
    ui.Rect.fromLTWH(origin.dx, origin.dy, size, size),
    ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, amount),
  );
  EmotionFacePainter.paint(canvas, emotion, origin, size, t: 1);
  canvas.restore();
}

/// Draws a situation picture, preferring the bundled art.
void drawScene(
    ui.Canvas canvas, SceneArt art, ui.Offset origin, double size) {
  final image = EmotionArtCache.scene(art);
  if (image == null) {
    SceneArtPainter.paint(canvas, art, origin, size);
    return;
  }
  _drawImage(canvas, image, origin, size);
}

/// Draws a caring-response picture, preferring the bundled art.
void drawResponse(
    ui.Canvas canvas, ResponseArt art, ui.Offset origin, double size) {
  final image = EmotionArtCache.response(art);
  if (image == null) {
    ResponseArtPainter.paint(canvas, art, origin, size);
    return;
  }
  _drawImage(canvas, image, origin, size);
}

/// Cards are square and pre-trimmed, so a picture fills its box directly with
/// no letterboxing arithmetic needed here.
void _drawImage(
  ui.Canvas canvas,
  ui.Image image,
  ui.Offset origin,
  double size, {
  double opacity = 1.0,
}) {
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    ui.Rect.fromLTWH(origin.dx, origin.dy, size, size),
    ui.Paint()
      ..filterQuality = ui.FilterQuality.medium
      ..color = ui.Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0)),
  );
}
