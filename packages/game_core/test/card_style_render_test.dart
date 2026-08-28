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
  bool showBorder = false,
  Color? borderColor,
  double borderWidth = 3.0,
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
    showBorder: showBorder,
    borderColor: borderColor,
    borderWidth: borderWidth,
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

  test('the outline is drawn on the card edge', () async {
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
    expect(
      Contrast.contrastRatio(withOutline, card),
      greaterThanOrEqualTo(Contrast.graphicalObjectMinimum),
    );
  });

  group('the standing outline is the same on every object', () {
    // The whole defect: an outline picked from each card's own luminance put
    // dark outlines and white ones on the same board, and a child reads the
    // odd one out as the answer.

    // Auto card colour, so each card's fill really is a different colour —
    // exactly the input that used to make the outline flip.
    const style = GameObjectStyle(
      outline: ObjectOutline.solid,
      outlineWidth: 8,
    );

    // Spanning near-white to near-black, plus the saturated game colours.
    const fills = <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFFDD835),
      Color(0xFFFFB300),
      Color(0xFF43A047),
      Color(0xFF1E88E5),
      Color(0xFF8E24AA),
      Color(0xFF2E2E33),
      Color(0xFF000000),
    ];

    test('differently coloured cards render an identical outline', () async {
      final seen = <Color>{};
      for (final fill in fills) {
        final image = await _renderCard(
          shapeColour: fill,
          alpha: 255, // opaque fill, so nothing white leaks through
          style: style,
        );
        // Deep inside an 8px stroke on the left edge: fully covered, so the
        // pixel is the outline colour itself rather than a blend.
        seen.add(await _pixel(image, 2, 30));
      }
      expect(
        seen,
        hasLength(1),
        reason: 'the outline varied with the card colour: $seen',
      );
      expect(seen.single, GameObjectStyle.standingOutline);
    });

    test('a dark card does not get a light outline', () async {
      // The specific flip that produced white standing outlines.
      final image = await _renderCard(
        shapeColour: const Color(0xFF1E2438),
        alpha: 255,
        style: style,
      );
      final edge = await _pixel(image, 2, 30);
      expect(edge, GameObjectStyle.standingOutline);
      expect(
        Contrast.relativeLuminance(edge),
        lessThan(0.2),
        reason: 'a neutral card must never be outlined in white',
      );
    });
  });

  group('outline style and width', () {
    const card = Color(0xFFFFFFFF);

    Future<Color> edgeOf(GameObjectStyle style, {int x = 2}) async =>
        _pixel(await _renderCard(shapeColour: gold, style: style), x, 30);

    test('None leaves the edge unstroked, Solid and Dashed do not', () async {
      final none = await edgeOf(
        const GameObjectStyle(cardColour: card, outline: ObjectOutline.none),
      );
      final solid = await edgeOf(
        const GameObjectStyle(
          cardColour: card,
          outline: ObjectOutline.solid,
          outlineWidth: 8,
        ),
      );
      expect(solid, GameObjectStyle.standingOutline);
      expect(none, isNot(solid));

      // Dashed walks the path in segments, so it strokes some of the edge and
      // leaves the rest bare — both must be true for it to read as dashed.
      final dashedImage = await _renderCard(
        shapeColour: gold,
        style: const GameObjectStyle(
          cardColour: card,
          outline: ObjectOutline.dashed,
          outlineWidth: 8,
        ),
      );
      final samples = <Color>[
        for (var y = 10; y < 50; y++) await _pixel(dashedImage, 2, y),
      ];
      expect(samples, contains(GameObjectStyle.standingOutline));
      expect(
        samples.any((c) => c != GameObjectStyle.standingOutline),
        isTrue,
        reason: 'a dashed outline must have gaps',
      );
    });

    test('1px and 8px produce visibly different strokes', () async {
      // Sampled 3px in: outside a 1px stroke, well inside an 8px one.
      final thin = await edgeOf(
        const GameObjectStyle(
          cardColour: card,
          outline: ObjectOutline.solid,
          outlineWidth: 1,
        ),
        x: 3,
      );
      final thick = await edgeOf(
        const GameObjectStyle(
          cardColour: card,
          outline: ObjectOutline.solid,
          outlineWidth: 8,
        ),
        x: 3,
      );
      expect(thick, GameObjectStyle.standingOutline);
      expect(thin, isNot(thick));
    });

    test('an out-of-range width is clamped, not obeyed', () async {
      final clamped = await edgeOf(
        const GameObjectStyle(
          cardColour: card,
          outline: ObjectOutline.solid,
          outlineWidth: 99,
        ),
        x: 3,
      );
      final atMax = await edgeOf(
        const GameObjectStyle(
          cardColour: card,
          outline: ObjectOutline.solid,
          outlineWidth: GameObjectStyle.maxWidth,
        ),
        x: 3,
      );
      expect(clamped, atMax);
    });
  });

  group('state borders', () {
    const style = GameObjectStyle(
      cardColour: Color(0xFFFFFFFF),
      outline: ObjectOutline.solid,
      outlineWidth: 8,
    );

    Future<Color> edgeWith({bool showBorder = false, Color? border}) async =>
        _pixel(
          await _renderCard(
            shapeColour: gold,
            style: style,
            showBorder: showBorder,
            borderColor: border,
            borderWidth: 8,
          ),
          2,
          30,
        );

    test(
      'a neutral card takes the standing outline, not a white border',
      () async {
        final neutral = await edgeWith();
        expect(neutral, GameObjectStyle.standingOutline);
        expect(neutral, isNot(const Color(0xFFFFFFFF)));
      },
    );

    test('each real state overrides the standing outline', () async {
      const states = <String, Color>{
        'correct': Color(0xFFB8E8D4), // mint
        'wrong': Color(0xFFE88888),
        'hint': Color(0xFFFFA726),
        'selected': Color(0xFF9B82C4),
      };
      for (final entry in states.entries) {
        final edge = await edgeWith(showBorder: true, border: entry.value);
        expect(edge, entry.value, reason: entry.key);
        expect(edge, isNot(GameObjectStyle.standingOutline), reason: entry.key);
      }
    });
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
