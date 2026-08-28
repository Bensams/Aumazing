import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_ui/shared_ui.dart';

void main() {
  group('Contrast', () {
    test('matches the WCAG reference ratios', () {
      // Black on white is the definitional maximum.
      expect(
        Contrast.contrastRatio(
            const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.01),
      );
      // A colour against itself is the definitional minimum.
      expect(
        Contrast.contrastRatio(
            const Color(0xFF9B82C4), const Color(0xFF9B82C4)),
        closeTo(1.0, 0.0001),
      );
      // Order must not matter.
      expect(
        Contrast.contrastRatio(
            const Color(0xFFFFB300), const Color(0xFF9CCBE6)),
        closeTo(
          Contrast.contrastRatio(
              const Color(0xFF9CCBE6), const Color(0xFFFFB300)),
          0.0001,
        ),
      );
    });

    test('reproduces the measured Gold Star failure', () {
      const gold = Color(0xFFFFB300);
      const oceanMid = Color(0xFF9CCBE6);

      // Against the raw background the amber star is already near-invisible.
      expect(Contrast.contrastRatio(gold, oceanMid), closeTo(1.03, 0.02));

      // Worse in the game as actually drawn: MatchableShape paints the card
      // as the shape colour at alpha 40 and the icon on top at full colour,
      // so the icon is seen against that composite — where the luminances
      // coincide almost exactly.
      final card = Contrast.compositeOver(gold, oceanMid, 40 / 255);
      expect(Contrast.contrastRatio(gold, card), closeTo(1.00, 0.01));
    });
  });

  group('ChildBackground encoding', () {
    test('round-trips a solid background', () {
      const bg = ChildBackground.solid(Color(0xFFEDE7F6));
      expect(ChildBackground.decode(bg.encode()), bg);
    });

    test('round-trips a gradient background', () {
      const bg =
          ChildBackground.gradient(Color(0xFFA9E3CC), Color(0xFF1E2438));
      expect(ChildBackground.decode(bg.encode()), bg);
    });

    test('a solid background paints a two-stop gradient of one colour', () {
      const bg = ChildBackground.solid(Color(0xFFFAF9F6));
      expect(bg.toGradient().colors, [bg.start, bg.start]);
      expect(bg.sampleColours, hasLength(1));
    });

    test('unparseable stored values decode to null, not an exception', () {
      // A corrupt pref must degrade to the preset theme rather than break
      // startup for the child.
      for (final bad in [
        null,
        '',
        'nonsense',
        'solid:',
        'solid:zzzzzzzz',
        'gradient:ffffffff', // gradient needs two colours
        'solid:ffffffff,ff000000', // solid takes only one
        'plaid:ffffffff',
      ]) {
        expect(ChildBackground.decode(bad), isNull, reason: '$bad');
      }
    });
  });

  group('shape legibility scoring', () {
    test('no colour can make all ten shapes clear 3:1', () {
      // The purple shape needs a light background and the yellow one needs a
      // dark background; the bands do not overlap. If this ever passes, the
      // shape palette changed and the "a background alone cannot fix every
      // shape" copy in the picker is no longer true.
      for (var i = 0; i <= 255; i += 5) {
        final grey = Color.fromARGB(255, i, i, i);
        expect(
          ChildBackground.solid(grey).shapesClearingMinimum,
          lessThan(ChildBackground.totalShapes),
        );
      }
    });

    test('the ready-made swatches beat the preset theme gradients', () {
      // Preset theme tones score 1-3 of 10; every offered swatch must do
      // better, or the picker is not worth having.
      for (final swatch in ChildBackgroundSwatches.ready) {
        final score =
            ChildBackground.solid(swatch.colour).shapesClearingMinimum;
        expect(score, greaterThanOrEqualTo(5),
            reason: '${swatch.name} only clears $score of 10');
      }
    });

    test('the dark swatches score highest', () {
      // Pins the finding that dark backgrounds are materially better for
      // shape legibility, so a future palette tweak cannot silently undo it.
      const navy = ChildBackground.solid(Color(0xFF1E2438));
      const white = ChildBackground.solid(Color(0xFFFAF9F6));
      expect(navy.shapesClearingMinimum, 9);
      expect(white.shapesClearingMinimum, 6);
    });

    test('a gradient is scored against both of its stops', () {
      // A shape has to survive the whole sweep, not just the nicer end.
      const light = Color(0xFFFAF9F6);
      const navy = Color(0xFF1E2438);
      const blend = ChildBackground.gradient(light, navy);
      expect(
        blend.shapesClearingMinimum,
        lessThanOrEqualTo(
          const ChildBackground.solid(light).shapesClearingMinimum,
        ),
      );
      expect(blend.sampleColours, [light, navy]);
    });
  });

  group('palette override', () {
    test('a custom background replaces every game background', () {
      const custom = ChildBackground.solid(Color(0xFF27333A));
      final palette =
          GamePalettes.neutral.withGameBackground(custom.toGradient());

      // Per-game variation is dropped: one chosen colour means one colour
      // everywhere, which is also the predictable thing for the child.
      for (final id in ['match_it', 'sari_sari_sort', 'trace_it', 'copy_me']) {
        expect(palette.gameBackgroundFor(id).colors, [custom.start, custom.start]);
      }
      // The parent dashboard keeps the preset gradient.
      expect(palette.parentBackground, GamePalettes.neutral.parentBackground);
    });
  });
}
