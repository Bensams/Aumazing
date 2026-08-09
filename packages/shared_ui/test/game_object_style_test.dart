import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_ui/shared_ui.dart';

void main() {
  group('encoding', () {
    test('round-trips every field', () {
      const style = GameObjectStyle(
        cardColour: Color(0xFF3A4550),
        outline: ObjectOutline.dashed,
        outlineWidth: 5,
      );
      expect(GameObjectStyle.decode(style.encode()), style);
    });

    test('round-trips the Auto card colour', () {
      const style = GameObjectStyle(outline: ObjectOutline.none);
      expect(style.cardColour, isNull);
      expect(GameObjectStyle.decode(style.encode()), style);
    });

    test('unparseable values decode to null rather than throwing', () {
      for (final bad in [
        null,
        '',
        'solid',
        'solid|3.0',
        'plaid|3.0|ffffffff',
        'solid|wide|ffffffff',
        'solid|3.0|zzzzzzzz',
      ]) {
        expect(GameObjectStyle.decode(bad), isNull, reason: '$bad');
      }
    });
  });

  group('outline colour', () {
    test('clears 3:1 against any possible card colour', () {
      // The whole reason the outline colour is derived rather than chosen:
      // it has to be correct on every surface, including ones a parent
      // invents with the wheel. Sweep the RGB cube rather than spot-check.
      for (var r = 0; r <= 255; r += 17) {
        for (var g = 0; g <= 255; g += 17) {
          for (var b = 0; b <= 255; b += 17) {
            final surface = Color.fromARGB(255, r, g, b);
            final outline = GameObjectStyle.outlineColourFor(surface);
            expect(
              Contrast.contrastRatio(outline, surface),
              greaterThanOrEqualTo(Contrast.graphicalObjectMinimum),
              reason: 'outline failed on #$r,$g,$b',
            );
          }
        }
      }
    });

    test('flips from dark to light as the surface darkens', () {
      expect(GameObjectStyle.outlineColourFor(const Color(0xFFFFFFFF)),
          GameObjectStyle.darkOutline);
      expect(GameObjectStyle.outlineColourFor(const Color(0xFF1E2438)),
          GameObjectStyle.lightOutline);
    });
  });

  group('defaults and clamping', () {
    test('objects are outlined by default', () {
      // The standing outline is what makes a card separable from the
      // background. Off by default would ship the accessibility defect.
      const style = GameObjectStyle();
      expect(style.hasOutline, isTrue);
      expect(style.outline, ObjectOutline.solid);
    });

    test('width is clamped to a sane stroke', () {
      expect(const GameObjectStyle(outlineWidth: 0).effectiveWidth,
          GameObjectStyle.minWidth);
      expect(const GameObjectStyle(outlineWidth: 99).effectiveWidth,
          GameObjectStyle.maxWidth);
    });

    test('clearCardColour returns to the Auto tint', () {
      const style = GameObjectStyle(cardColour: Color(0xFFFFFFFF));
      expect(style.copyWith(clearCardColour: true).cardColour, isNull);
      // A plain copyWith must not resurrect it.
      expect(style.copyWith(outlineWidth: 4).cardColour,
          const Color(0xFFFFFFFF));
    });
  });

  group('the defect this fixes', () {
    test('a fixed card colour breaks the shape-tints-its-own-card loop', () {
      const gold = Color(0xFFFFB300);

      // Auto: the card is the shape at alpha 40, so the two share a
      // luminance and the shape is invisible against its own card.
      final autoCard = Contrast.compositeOver(
          gold, const Color(0xFF9CCBE6), 40 / 255);
      expect(Contrast.contrastRatio(gold, autoCard), lessThan(1.1));

      // A fixed card has no relationship to the shape colour, and the
      // derived outline then guarantees the card reads against anything.
      const fixed = Color(0xFF2E2E33);
      expect(Contrast.contrastRatio(gold, fixed),
          greaterThanOrEqualTo(Contrast.graphicalObjectMinimum));
      expect(
        Contrast.contrastRatio(
            GameObjectStyle.outlineColourFor(fixed), fixed),
        greaterThanOrEqualTo(Contrast.graphicalObjectMinimum),
      );
    });
  });
}
