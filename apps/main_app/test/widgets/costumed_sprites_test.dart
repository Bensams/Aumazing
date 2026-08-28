import 'package:aumazing/features/stars/star_catalogue.dart';
import 'package:aumazing/widgets/mascot.dart';
import 'package:flutter_test/flutter_test.dart';

/// STAR-F2 — the mascot wears the equipped costume, and degrades safely when
/// that costume has no sheets yet.
///
/// Deliberately does NOT load sprite sheets. Slicing a full character is 21
/// sheets decoded and re-encoded, and doing that for several costumes pushes
/// a unit test past the suite's timeout for no extra confidence —
/// `mascot_render_test.dart` already covers that sheets slice and render.
/// What is worth pinning here is the *mapping*, which is cheap and is the
/// part that can silently drift.
// NOTE: the character-level fallback this file used to warn about is gone.
// `MascotCharacter.loadCostumed` substituted BPS when a character had no
// sheets, which existed solely because Lexianne shipped in the picker before
// her 21 sheets were cut (AUM-280). Her sheets have landed, every character
// has a full set, and the branch was deleted — a wrong character is a worse
// failure than a loud one, because a parent cannot see or report it.
// `packages/shared_ui/test/character_sprites_test.dart` loads all three
// characters for real and is what now catches a missing sheet.
void main() {
  test('every ChildCharacter the picker offers can be drawn', () {
    // The picker offers ChildCharacter; the mascot renders MascotCharacter.
    // If the two drift, a parent could pick a character the mascot cannot
    // draw — so the correspondence is asserted rather than assumed.
    for (final c in ChildCharacter.values) {
      expect(
        MascotCharacter.values.map((m) => m.name),
        contains(c.id),
        reason: 'no MascotCharacter for ${c.id}',
      );
      expect(MascotCharacter.fromId(c.id).name, c.id);
    }
  });

  test('an unknown or missing character id falls back rather than throwing',
      () {
    expect(MascotCharacter.fromId('nobody'), MascotCharacter.bps);
    expect(MascotCharacter.fromId(null), MascotCharacter.bps);
  });

  test('the shop only stocks costumes the mascot can wear', () {
    // Three of the nine costumes have sprite sheets so far, and only those
    // three are sold. The other six keep their price and their still art in
    // the catalogue but stay out of the shop until their sheets land
    // (STAR-F3 / AUM-275) — a child must not spend stars on a costume that
    // then fails to appear on the mascot during play.
    const animated = {Costume.teddy, Costume.panda, Costume.pig};
    expect(Costume.inStock.toSet(), animated);
    for (final costume in Costume.purchasable) {
      expect(costume.hasSpriteSheets, animated.contains(costume),
          reason: costume.id);
    }
    expect(
      Costume.purchasable.length,
      greaterThan(Costume.inStock.length),
      reason: 'if every costume is animated, the fallback path in '
          'CharacterSprites.costumed is now dead code and both it and '
          'Costume.inStock can be simplified away',
    );
  });
}

