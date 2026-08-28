import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/src/games/trace_it/trace_glyphs.dart';

void main() {
  const expectedByLevel = {
    1: {'circle', 'square'},
    2: {'triangle', 'diamond'},
    3: {'star', 'heart'},
  };

  test('shape glyphs are distributed from simple to complex', () {
    for (final entry in expectedByLevel.entries) {
      final labels = TraceGlyphs.forLevel(
        entry.key,
      ).map((glyph) => glyph.label);
      expect(labels, containsAll(entry.value), reason: 'level ${entry.key}');
    }
  });

  test('every shape is a closed, normalized single stroke', () {
    final shapes = expectedByLevel.values.expand((labels) => labels).toSet();
    final glyphs = [
      ...TraceGlyphs.level1,
      ...TraceGlyphs.level2,
      ...TraceGlyphs.level3,
    ].where((glyph) => shapes.contains(glyph.label));

    expect(glyphs, hasLength(shapes.length));
    for (final glyph in glyphs) {
      expect(glyph.strokes, hasLength(1), reason: glyph.label);
      final stroke = glyph.strokes.single;
      expect(stroke.length, greaterThanOrEqualTo(4), reason: glyph.label);
      expect(
        (stroke.first - stroke.last).distance,
        lessThan(0.001),
        reason: '${glyph.label} must close at its starting point',
      );
      for (final point in stroke) {
        expect(
          _isNormalized(point),
          isTrue,
          reason: '${glyph.label} contains $point outside the 0..1 box',
        );
      }
    }
  });

  test('existing letter and number glyphs remain in their original tiers', () {
    expect(
      TraceGlyphs.level1.map((glyph) => glyph.label),
      containsAll(['V', '1']),
    );
    expect(
      TraceGlyphs.level2.map((glyph) => glyph.label),
      containsAll(['L', 'C', 'U', '7', '2', '3']),
    );
    expect(
      TraceGlyphs.level3.map((glyph) => glyph.label),
      containsAll(['A', 'T', 'H', 'E', '4', '5']),
    );
  });
}

bool _isNormalized(Offset point) =>
    point.dx >= 0 && point.dx <= 1 && point.dy >= 0 && point.dy <= 1;
