import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:game_core/game_core.dart';

/// The picture/glyph counterpart to shape_emphasis_test: emoji and bundled
/// illustrations can't take the shapes' hard contour, so they get a soft drop
/// shadow instead. These lock in that the shadow is actually laid down, so a
/// focus object lifts off its card rather than melting into it.
Future<List<Color>> _pixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final out = <Color>[];
  for (var i = 0; i < data!.lengthInBytes; i += 4) {
    out.add(Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    ));
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('drawArtShadow lays a shadow that shows around the picture', () async {
    const size = 120.0;
    final rect = Rect.fromLTWH(30, 30, 60, 60); // picture box, inset in the cell

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // A flat card fills the cell — the same colour everywhere, so any darkening
    // can only be the shadow.
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, size, size), Paint()..color = const Color(0xFFEDEDED));
    ObjectEmphasis.drawArtShadow(canvas, rect, radius: 8);
    // The opaque picture on top — its own pixels are not the thing under test.
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));

    final image = await recorder.endRecording().toImage(size.round(), size.round());
    final pixels = await _pixels(image);

    // Somewhere on the card there is now a pixel darker than the flat card —
    // the shadow leaking out past the picture edge.
    const card = Color(0xFFEDEDED);
    final darkened = pixels.any((p) =>
        p.a == 1.0 &&
        p.r < card.r - 0.02 &&
        p.g < card.g - 0.02 &&
        p.b < card.b - 0.02);
    expect(darkened, isTrue,
        reason: 'no pixel was darker than the card — the shadow is missing');
  });

  test('glyphShadows scales with the glyph and is a soft, offset shadow', () {
    final small = ObjectEmphasis.glyphShadows(20);
    final large = ObjectEmphasis.glyphShadows(80);

    expect(small, isNotEmpty);
    expect(large.first.blurRadius, greaterThan(small.first.blurRadius),
        reason: 'a bigger glyph should get a proportionally bigger shadow');
    expect(large.first.offset.dy, greaterThan(0),
        reason: 'the shadow should sit below the glyph, lifting it');
  });
}
