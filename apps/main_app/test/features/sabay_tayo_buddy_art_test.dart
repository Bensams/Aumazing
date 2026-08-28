import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

/// The buddy in "Sabay Tayo!" is drawn from the mascot sprite sheets in
/// `shared_ui`, loaded through Flame rather than through [CharacterSprites].
///
/// This test lives in main_app for the same reason `mascot_render_test` does:
/// the `shared_ui` assets are only bundled where an app declares them, so a
/// load failure is invisible from inside `game_core`'s own test bundle.
///
/// It exists because the failure mode is silent. [BuddyArtCache] is
/// deliberately best-effort — a sheet that will not decode is logged and
/// [BuddyPainter] takes over, so the child still gets a playable game instead
/// of a crashed session. The cost of that kindness is that a broken asset path,
/// a renamed sheet, or a `layout` entry that no longer matches the PNG grid all
/// look exactly like "it works", right up until someone notices the buddy is a
/// flat cartoon head. Nothing else in the suite would catch it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(BuddyArtCache.resetForTest);

  test('every sheet the game draws decodes from the shared_ui bundle',
      () async {
    await BuddyArtCache.ensureLoaded('bps');

    expect(BuddyArtCache.isLoaded, isTrue);
    for (final action in BuddyArtCache.usedActions) {
      final sheet = BuddyArtCache.sheet(action);
      expect(sheet, isNotNull,
          reason: '$action did not decode, so the buddy silently falls back '
              'to the painted version');
      expect(sheet!.width, greaterThan(0));
      expect(sheet.height, greaterThan(0));
    }
  });

  test('both characters can gaze', () async {
    // `canGaze` is the floor: without the horizontal pair the buddy cannot aim
    // at objects arranged around an arc, and the game has no cue at all.
    for (final character in ['bps', 'reiz']) {
      BuddyArtCache.resetForTest();
      await BuddyArtCache.ensureLoaded(character);
      expect(BuddyArtCache.canGaze, isTrue,
          reason: '$character has no usable gaze grid');
    }
  });

  test('every slot an object can stand in resolves to a decoded sheet',
      () async {
    await BuddyArtCache.ensureLoaded('bps');

    for (final slot in AttentionSlot.values) {
      final action = resolvedGazeAction(slot.fx, slot.fy);
      expect(action, isNotNull,
          reason: '${slot.name} has no gaze pose — an object could stand '
              'somewhere the buddy is unable to look');
      expect(BuddyArtCache.sheet(action!), isNotNull,
          reason: '${slot.name} resolves to $action, which did not decode');
    }
  });
}
