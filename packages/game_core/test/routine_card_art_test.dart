import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:game_core/game_core.dart';

/// Every routine card picture decodes, and a card actually draws one.
///
/// [RoutineArtCache] is deliberately best-effort: a picture that fails to
/// decode is skipped and [RoutineArtPainter] draws the step instead, so a
/// child's session never ends on a missing file. That safety net is also a
/// silencer — rename an asset, or drop one from `shared_ui`'s pubspec, and the
/// game keeps running while quietly showing fourteen different drawings from
/// the ones that were reviewed. Nothing else fails.
///
/// So the fallback is asserted against rather than relied on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    RoutineArtCache.resetForTest();
    await RoutineArtCache.ensureLoaded();
  });

  test('every routine step has a decodable picture', () {
    final missing = RoutineArt.values
        .where((a) => RoutineArtCache.of(a) == null)
        .map((a) => a.assetPath)
        .toList();
    expect(missing, isEmpty,
        reason: 'these fell back to the painted art: ${missing.join(', ')}');
  });

  test('cards are square, so one layout rule positions all of them', () {
    for (final art in RoutineArt.values) {
      final image = RoutineArtCache.of(art)!;
      expect(image.width, image.height, reason: art.assetName);
    }
  });

  test('a card renders its picture, not the painted fallback', () async {
    // The two paths differ everywhere, so rather than compare drawings, check
    // the one thing only the picture can produce: RoutineArtPainter fills a
    // fixed 100x100 box with flat pastels, while a photographed-out PNG covers
    // the art box edge to edge with many more distinct colours.
    const size = 200.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, size, size),
        Paint()..color = const Color(0xFFFFFFFF));
    drawRoutineArt(canvas, RoutineArt.wake, Offset.zero, size);

    final image =
        await recorder.endRecording().toImage(size.round(), size.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final colours = <int>{};
    for (var i = 0; i < data!.lengthInBytes; i += 4) {
      colours.add(data.getUint32(i));
    }

    expect(colours.length, greaterThan(64),
        reason: 'the art box came back nearly flat — the picture did not draw');
  });
}
