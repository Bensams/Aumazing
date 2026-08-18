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
    test('is one constant, not a per-card derivation', () {
      // The defect: an outline chosen per card put black outlines and white
      // outlines on the same board, and the odd one out reads to a child as
      // the answer. There is one outline colour and it is a compile-time
      // constant, so there is nothing left that *could* vary per object.
      expect(GameObjectStyle.standingOutline, const Color(0xFF1A1A1F));
    });

    test('the dark neutral is a child-appropriate ink, not pure black', () {
      // Pure black on a colourful card is harsh; the near-black keeps the
      // edge soft while still separating the card from a light background.
      expect(GameObjectStyle.standingOutline, isNot(const Color(0xFF000000)));
      expect(
        Contrast.contrastRatio(
          GameObjectStyle.standingOutline,
          const Color(0xFFFFFFFF),
        ),
        greaterThanOrEqualTo(Contrast.graphicalObjectMinimum),
      );
    });

    test('chrome may still pick per-surface — game objects may not', () {
      // A tick on a colour swatch is judged alone, so Contrast.legibleOn
      // still flips. It is a separate helper precisely so nobody reaches for
      // it when drawing an object.
      expect(Contrast.legibleOn(const Color(0xFFFFFFFF)), Contrast.ink);
      expect(Contrast.legibleOn(const Color(0xFF1E2438)), Contrast.paper);
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

    test('the default outline is a 1px hairline', () {
      // Thin enough to be a boundary rather than a decoration. A parent can
      // widen it; nothing should ship a heavy frame around every object.
      const style = GameObjectStyle();
      expect(style.outlineWidth, 1);
      expect(style.effectiveWidth, GameObjectStyle.minWidth);
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

      // A fixed card has no relationship to the shape colour, so the shape
      // stands clear of the card it sits on.
      const fixed = Color(0xFF2E2E33);
      expect(Contrast.contrastRatio(gold, fixed),
          greaterThanOrEqualTo(Contrast.graphicalObjectMinimum));
    });

    test('the uniform outline still separates a card from a light screen', () {
      // The accepted trade of making the outline uniform: it is chosen
      // against the *background* a game is played on, not against the card
      // fill. Both stock backgrounds are light, so the ink outline reads.
      for (final background in const [Color(0xFFEDE7F6), Color(0xFFFAF9F6)]) {
        expect(
          Contrast.contrastRatio(GameObjectStyle.standingOutline, background),
          greaterThanOrEqualTo(Contrast.graphicalObjectMinimum),
          reason: '$background',
        );
      }
    });
  });

  group('persistence', () {
    test('values written before the outline was made uniform still read', () {
      // The outline colour was never one of the three stored fields, so
      // nothing on a device needs migrating. Literals, not round-trips, so
      // this fails if the format is ever quietly widened.
      expect(
        GameObjectStyle.decode('solid|3.0|-'),
        const GameObjectStyle(outline: ObjectOutline.solid, outlineWidth: 3),
      );
      expect(
        GameObjectStyle.decode('dashed|8.0|ff2e2e33'),
        const GameObjectStyle(
          cardColour: Color(0xFF2E2E33),
          outline: ObjectOutline.dashed,
          outlineWidth: 8,
        ),
      );
      expect(
        GameObjectStyle.decode('none|1.0|ffffffff'),
        const GameObjectStyle(
          cardColour: Color(0xFFFFFFFF),
          outline: ObjectOutline.none,
          outlineWidth: 1,
        ),
      );
    });

    test('the extreme thicknesses survive a save and load', () {
      for (final w in [GameObjectStyle.minWidth, GameObjectStyle.maxWidth]) {
        final style = GameObjectStyle(outlineWidth: w);
        final back = GameObjectStyle.decode(style.encode());
        expect(back, style);
        expect(back!.effectiveWidth, w);
      }
    });

    test('an out-of-range stored width is clamped rather than obeyed', () {
      // A hand-edited or corrupted preference must not produce a hairline or
      // a stroke that swallows the card.
      expect(
        GameObjectStyle.decode('solid|0.0|-')!.effectiveWidth,
        GameObjectStyle.minWidth,
      );
      expect(
        GameObjectStyle.decode('solid|400.0|-')!.effectiveWidth,
        GameObjectStyle.maxWidth,
      );
      expect(
        GameObjectStyle.decode('solid|-9.0|-')!.effectiveWidth,
        GameObjectStyle.minWidth,
      );
    });
  });
}
