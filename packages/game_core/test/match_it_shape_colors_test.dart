import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

import 'package:game_core/game_core.dart';

/// shared_ui cannot import game_core (the dependency runs the other way), so
/// `GameArtColors.matchItShapes` is a hand-kept mirror of the colours Match
/// It actually paints. That mirror is what the parent-facing background
/// picker scores a chosen background against — if it drifts, the picker
/// quietly starts advising on colours the game no longer uses.
void main() {
  test('GameArtColors mirrors the real Match It shape colours', () {
    final inGame = MatchItGame.allPairs.map((p) => p.color).toSet();
    final mirrored = GameArtColors.matchItShapes.toSet();

    expect(
      mirrored,
      inGame,
      reason: 'Match It shape colours changed. Update '
          'GameArtColors.matchItShapes in shared_ui to match, then re-check '
          'the swatch scores in child_background_test.',
    );
  });

  test('the mirror lists each colour once', () {
    expect(
      GameArtColors.matchItShapes.length,
      GameArtColors.matchItShapes.toSet().length,
      reason: 'a duplicated colour would weight the contrast scoring',
    );
  });
}
