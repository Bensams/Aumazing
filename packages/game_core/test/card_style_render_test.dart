import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

import 'package:game_core/game_core.dart';

/// Renders a card and reads back real pixels.
///
/// The settings preview and the running game both go through
/// `drawCard3D`, so these assertions cover both at once — which is the
/// point of having the preview call the game's painter instead of a copy.
Future<ui.Image> _renderCard({
  required Color shapeColour,
  GameObjectStyle? style,
  int alpha = 40,
  Size size = const Size(60, 60),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // Opaque white underneath, so anything translucent composites against a
  // known colour rather than transparent black.
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
  ShapePainter3D.drawCard3D(
    canvas,
    Offset.zero & size,
    color: shapeColour,
    alpha: alpha,
    cornerRadius: 8,
    styleOverride: style,
  );
  return recorder
      .endRecording()
      .toImage(size.width.round(), size.height.round());
}

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(
    data!.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const gold = Color(0xFFFFB300);

  test('Auto tints the card with the object colour', () async {
    final image = await _renderCard(
      shapeColour: gold,
      style: const GameObjectStyle(outline: ObjectOutline.none),
    );
    final centre = await _pixel(image, 30, 30);

    // A 16% gold wash over white: warm, and much lighter than gold itself.
    // This is the behaviour that made a gold shape invisible on its card.
    expect(
      Contrast.contrastRatio(centre, gold),
      lessThan(2.0),
      reason: 'the Auto card should sit close to the shape colour',
    );
  });

  test('a fixed card colour replaces the tint entirely', () async {
    const card = Color(0xFF2E2E33);
    final image = await _renderCard(
      shapeColour: gold,
      style: const GameObjectStyle(
        cardColour: card,
        outline: ObjectOutline.none,
      ),
    );
    final centre = await _pixel(image, 30, 30);

    // The card no longer has any relationship to the shape, so the shape
    // now stands well clear of it.
    expect(
      Contrast.contrastRatio(centre, gold),
      greaterThanOrEqualTo(Contrast.graphicalObjectMinimum),
    );
  });

  test('a matched card fades but keeps its colour', () async {
    const card = Color(0xFFFFFFFF);
    final resting = await _pixel(
      await _renderCard(
        shapeColour: gold,
        style: const GameObjectStyle(
            cardColour: card, outline: ObjectOutline.none),
      ),
      30,
      30,
    );
    final matched = await _pixel(
      await _renderCard(
        shapeColour: gold,
        alpha: 30, // what MatchableShape passes once matched
        style: const GameObjectStyle(
            cardColour: card, outline: ObjectOutline.none),
      ),
      30,
      30,
    );
    expect(matched, isNot(resting));
  });

  test('the outline is drawn on the card edge and derived from the card',
      () async {
    const card = Color(0xFFFFFFFF);
    final outlined = await _renderCard(
      shapeColour: gold,
      style: const GameObjectStyle(
        cardColour: card,
        outline: ObjectOutline.solid,
        outlineWidth: 6,
      ),
    );
    final bare = await _renderCard(
      shapeColour: gold,
      style: const GameObjectStyle(
          cardColour: card, outline: ObjectOutline.none),
    );

    // Mid-way down the left edge, inside the stroke.
    final withOutline = await _pixel(outlined, 2, 30);
    final without = await _pixel(bare, 2, 30);

    expect(withOutline, isNot(without));
    // On a white card the derived outline is the dark one.
    expect(
      Contrast.contrastRatio(withOutline, card),
      greaterThanOrEqualTo(Contrast.graphicalObjectMinimum),
    );
  });

  test('styleOverride does not disturb the global games read', () async {
    final before = GameObjectStyle.current;
    await _renderCard(
      shapeColour: gold,
      style: const GameObjectStyle(cardColour: Color(0xFF123456)),
    );
    expect(GameObjectStyle.current, same(before));
  });
}
