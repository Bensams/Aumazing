import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

import 'package:game_core/game_core.dart';

/// The failure this guards against: a shape drawn on a tile of its own hue used
/// to melt into it (a gold star measured 1.00:1 against a gold-ish card). The
/// halo + contour added to every painted object exist to keep the object the
/// loudest thing in its cell whatever colour the tile is — so a child focuses
/// on the shape, not the square behind it.
Future<ui.Image> _renderShapeOnTile({
  required String shape,
  required Color shapeColour,
  required Color tileColour,
  Size size = const Size(120, 120),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // A tile of (nearly) the shape's own colour — the worst case for separation.
  canvas.drawRect(Offset.zero & size, Paint()..color = tileColour);
  ShapePainter3D.drawByName(
    canvas,
    shape,
    size.width / 2,
    size.height / 2,
    size.width * 0.3,
    shapeColour,
  );
  return recorder
      .endRecording()
      .toImage(size.width.round(), size.height.round());
}

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

  // Gold shape on a light-gold tile: same hue, close luminance — the exact
  // pairing that used to vanish.
  const gold = Color(0xFFFFB300);
  const goldTile = Color(0xFFFFE9B0);

  for (final shape in const ['star', 'triangle', 'diamond', 'heart', 'circle']) {
    test('$shape carries a dark contour that separates it from a same-hue tile',
        () async {
      final image = await _renderShapeOnTile(
        shape: shape,
        shapeColour: gold,
        tileColour: goldTile,
      );
      final pixels = await _pixels(image);

      // Somewhere on the object there is now an edge markedly darker than the
      // tile — the contour. Without it the darkest thing on screen was the
      // shape's own gradient, which stayed close to the tile.
      final contrastyEdge = pixels.any(
        (p) => Contrast.contrastRatio(p, goldTile) >=
            Contrast.graphicalObjectMinimum,
      );
      expect(contrastyEdge, isTrue,
          reason: 'no edge on the $shape cleared 3:1 against its own-hue tile');
    });
  }

  test('a light halo surrounds the object', () async {
    // A mid-tone tile of the shape's own hue: bright enough that a white halo
    // reads as clearly lighter, saturated enough to be a real same-hue case.
    const blue = Color(0xFF1E88E5);
    final image = await _renderShapeOnTile(
      shape: 'star',
      shapeColour: blue,
      tileColour: blue,
    );
    final pixels = await _pixels(image);

    // The halo leaks a light ring past the fill — lighter than both the tile
    // and the shape's own lightest gradient, so it cannot be either of them.
    final haloPresent = pixels.any(
      (p) => Contrast.relativeLuminance(p) >
          Contrast.relativeLuminance(blue) + 0.15,
    );
    expect(haloPresent, isTrue,
        reason: 'no pixel was lighter than the tile — the halo is missing');
  });
}
