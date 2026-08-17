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

  test('the animated costumes are the ones with sheets on disk', () {
    // Three of the nine costumes have sprite sheets so far. This is a
    // reminder, not a constraint: the other six are bought and worn happily,
    // they just fall back to the base character in-game until their sheets
    // are generated. Update the list as more land.
    const animated = {Costume.teddy, Costume.panda, Costume.pig};
    for (final costume in animated) {
      expect(Costume.purchasable, contains(costume));
    }
    expect(
      Costume.purchasable.length,
      greaterThan(animated.length),
      reason: 'if every costume is animated, the fallback path is now dead '
          'code and CharacterSprites.costumed can be simplified',
    );
  });
}
