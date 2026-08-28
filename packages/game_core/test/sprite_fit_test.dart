import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

/// The mascot sheets all share one cell size, and every game that draws a
/// character has to honour it. Tulong, Kaibigan! shipped without doing so and
/// the buddy was stretched 2.6x wide on a 800x360 phone while looking correct
/// on a 1280x720 tablet — which is exactly why this is a test and not a review
/// note. Nobody catches a distortion that only appears on one class of device.
void main() {
  // 406x490 as generated; see scripts/SPRITES.md.
  const cellW = 406.0;
  const cellH = 490.0;
  const cellAspect = cellW / cellH;

  /// The landscape shapes the games actually lay out against, including the
  /// short ones where a proportional box collapses.
  const boxes = [
    Rect.fromLTWH(0, 0, 310, 378), // roomy tablet
    Rect.fromLTWH(0, 0, 272, 126), // 800x360 phone — the reported bug
    Rect.fromLTWH(0, 0, 310, 84), // 960x300 — the worst case
    Rect.fromLTWH(0, 0, 120, 600), // tall and narrow
    Rect.fromLTWH(0, 0, 200, 200), // square
  ];

  group('fitSpriteCell', () {
    test('always preserves the cell aspect ratio', () {
      for (final box in boxes) {
        final fitted = fitSpriteCell(box, cellW, cellH);
        expect(fitted.width / fitted.height, closeTo(cellAspect, 0.001),
            reason: 'a ${box.width}x${box.height} box distorted the character');
      }
    });

    test('never overflows the box it was given', () {
      for (final box in boxes) {
        final fitted = fitSpriteCell(box, cellW, cellH);
        expect(fitted.width, lessThanOrEqualTo(box.width + 0.001));
        expect(fitted.height, lessThanOrEqualTo(box.height + 0.001));
      }
    });

    test('stands the character on the floor of the box', () {
      // Spare height belongs above the head. A character centred vertically
      // would float, and one anchored to the top would hang in mid-air with a
      // gap under its feet — both read as a bug to anyone watching a child
      // play, even when the proportions are right.
      for (final box in boxes) {
        final fitted = fitSpriteCell(box, cellW, cellH);
        expect(fitted.bottom, closeTo(box.bottom, 0.001));
        expect(fitted.center.dx, closeTo(box.center.dx, 0.001));
      }
    });

    test('fills the limiting dimension exactly', () {
      // Tall box: width is the constraint. Wide box: height is.
      final tall = fitSpriteCell(const Rect.fromLTWH(0, 0, 120, 600), cellW, cellH);
      expect(tall.width, closeTo(120, 0.001));

      final wide = fitSpriteCell(const Rect.fromLTWH(0, 0, 800, 200), cellW, cellH);
      expect(wide.height, closeTo(200, 0.001));
    });

    test('a degenerate box is returned untouched rather than dividing by zero', () {
      const empty = Rect.fromLTWH(0, 0, 0, 0);
      expect(fitSpriteCell(empty, cellW, cellH), empty);
      expect(fitSpriteCell(boxes.first, 0, cellH), boxes.first);
      expect(fitSpriteCell(boxes.first, cellW, 0), boxes.first);
    });
  });
}
