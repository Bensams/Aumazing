import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
// Not exported from the package barrel — the overlay band is an internal
// layout contract between the app chrome and the games, and this test exists
// precisely to hold the game to it.
import 'package:game_core/src/games/shared/game_layout.dart';
import 'package:shared_ui/shared_ui.dart';

/// "Sabay Tayo!" — the joint-attention game.
///
/// The failures these cover are all invisible until a child hits them, and all
/// of them look to the child like "I followed the gaze and the game said no":
///
///  * two objects landing in the same gaze cell, where no amount of gaze-
///    following can pick between them;
///  * a slot in the middle column at a tier that points, where the pointing arm
///    aims somewhere the target is not;
///  * an object with no shipped voice recording, which turns a correct answer
///    into silence in the one game whose reward is being told what you found.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('gaze slots', () {
    /// The band a fraction falls in: -1 near edge, 0 middle third, 1 far edge.
    /// Mirrors `CharacterSprites.gazeFrameFor`, which is what the game's
    /// [gazeActionFor] follows.
    int band(double v) {
      if (v < 1 / 3) return -1;
      if (v > 2 / 3) return 1;
      return 0;
    }

    test('every slot sits in its own gaze cell', () {
      final cells = AttentionSlot.values
          .map((s) => '${band(s.fx)},${band(s.fy)}')
          .toList();
      expect(cells.toSet(), hasLength(cells.length),
          reason: 'two slots share a gaze cell, so the buddy would look at '
              'both of them at once and neither answer could be wrong');
    });

    test('no slot sits in the bottom row, where the buddy stands', () {
      for (final slot in AttentionSlot.values) {
        expect(band(slot.fy), isNot(1),
            reason: '${slot.name} would be drawn on top of the buddy');
      }
    });

    test('exactly one slot is in the middle column', () {
      // The middle column is the one the pointing arm cannot indicate, so the
      // gaze has to carry it alone — which only works if nothing else shares
      // the column.
      final centre =
          AttentionSlot.values.where((s) => s.isCentreColumn).toList();
      expect(centre, hasLength(1));
      expect(centre.single, AttentionSlot.up);
    });

    test('isCentreColumn agrees with the gaze banding', () {
      for (final slot in AttentionSlot.values) {
        expect(slot.isCentreColumn, band(slot.fx) == 0,
            reason: '${slot.name} disagrees with the gaze grid about which '
                'column it is in');
      }
    });

    test('every slot resolves to a real gaze sheet name', () {
      for (final slot in AttentionSlot.values) {
        final action = gazeActionFor(slot.fx, slot.fy);
        if (slot.isCentreColumn && band(slot.fy) == 0) {
          // The centre cell is the resting pose, correctly nameless.
          expect(action, isNull);
          continue;
        }
        expect(action, isNotNull, reason: '${slot.name} has no gaze pose');
        expect(CharacterSprites.layout.containsKey(action), isTrue,
            reason: '$action is not a sheet any character has');
      }
    });

    test('gaze actions name the direction the child sees', () {
      expect(gazeActionFor(0.1, 0.1), 'look_up_left');
      expect(gazeActionFor(0.9, 0.1), 'look_up_right');
      expect(gazeActionFor(0.1, 0.5), 'look_left');
      expect(gazeActionFor(0.9, 0.5), 'look_right');
      expect(gazeActionFor(0.5, 0.1), 'look_up');
      // The middle cell is rest, not a pose.
      expect(gazeActionFor(0.5, 0.5), isNull);
    });
  });

  group('object catalogue', () {
    final catalogue = SabayTayoGame.catalogue;

    /// The item recordings shipped with the app, from the `item*` cues in
    /// `VoiceOverService`. An object outside this set succeeds in silence.
    const recordedItems = {
      'Tinapay',
      'Biskwit',
      'Kendi',
      'Saging',
      'Mansanas',
      'Tubig',
      'Gatas',
      'Juice',
      'Softdrink',
      'Kape',
      'Sabon',
      'Sipilyo',
      'Tisyu',
      'Syampu',
      'Bola',
      'Manika',
      'Kotse',
      'Teddy',
    };

    test('every object has a shipped voice recording', () {
      for (final object in catalogue) {
        expect(recordedItems, contains(object.name),
            reason: '${object.name} has no recording, so finding it would be '
                'the one correct answer in this game that says nothing back');
      }
    });

    test('object names are unique', () {
      final names = catalogue.map((d) => d.name).toList();
      expect(names.toSet(), hasLength(names.length));
    });

    test('there are enough objects for the widest tier without repeats', () {
      // Tier 3 puts four on screen, and the picker avoids recent repeats, so
      // the catalogue has to comfortably clear that.
      expect(catalogue.length, greaterThanOrEqualTo(8));
    });

    test('every object prints an English word in an English session', () {
      const stillFilipino = {
        'Bola',
        'Manika',
        'Kotse',
        'Tinapay',
        'Saging',
        'Mansanas',
        'Gatas',
        'Tubig',
        'Sabon',
        'Sipilyo',
        'Syampu',
      };
      for (final object in catalogue) {
        final en = object.label(GameLanguage.english);
        expect(en.trim(), isNotEmpty,
            reason: '${object.name} has no English label');
        expect(stillFilipino, isNot(contains(en)),
            reason: '${object.name} still prints Filipino in English');
      }
    });

    test('Tagalog and Cebuano keep the Filipino object name', () {
      for (final object in catalogue) {
        expect(object.label(GameLanguage.tagalog), object.name);
        expect(object.label(GameLanguage.cebuano), object.name);
      }
    });

    test('every object has its own colour and picture', () {
      expect(catalogue.map((d) => d.emoji).toSet(), hasLength(catalogue.length));
      expect(catalogue.map((d) => d.color).toSet(), hasLength(catalogue.length));
    });
  });

  group('instruction strings', () {
    test('resolve to a non-empty line in all three languages', () {
      for (final language in GameLanguage.values) {
        final strings = AppStrings(language);
        expect(strings.sabayTayoInstruction.trim(), isNotEmpty);
        expect(strings.sabayTayoComplete.trim(), isNotEmpty);
      }
    });

    test('Tagalog and Cebuano are translated, not English left in place', () {
      final english = AppStrings(GameLanguage.english);
      for (final language in [GameLanguage.tagalog, GameLanguage.cebuano]) {
        final strings = AppStrings(language);
        expect(strings.sabayTayoInstruction,
            isNot(english.sabayTayoInstruction),
            reason: '${language.name} instruction is still the English one');
        expect(strings.sabayTayoComplete, isNot(english.sabayTayoComplete),
            reason: '${language.name} completion line is still English');
      }
    });
  });

  group('registry', () {
    test('the game is registered under Social Interaction', () {
      final entry = GameRegistry.find('sabay_tayo');
      expect(entry, isNotNull);
      expect(entry!.categories, contains(SkillCategory.socialInteraction));
    });

    test('the registry name matches the DB join key exactly', () {
      // `learning_modules.title` is joined against this string in
      // ActiveGamesService._titleToGameId. A drifting exclamation mark makes
      // the game invisible with no error anywhere.
      expect(GameRegistry.find('sabay_tayo')!.name, 'Sabay Tayo!');
    });
  });

  group('tap tolerance', () {
    test('a tap just outside the card still counts', () {
      // An imprecise tap is a motor miss, not a social-cognition miss. This is
      // the guard on the game not measuring the wrong thing.
      expect(AttentionObject.tapTolerance, greaterThanOrEqualTo(0.15));
    });
  });

  group('layout', () {
    /// A phone and a tablet in landscape, plus a deliberately short canvas —
    /// the case where a proportional layout is most likely to push a card up
    /// under the overlay band.
    const canvases = [
      [800.0, 360.0],
      [1280.0, 720.0],
      [960.0, 300.0],
    ];

    Future<SabayTayoGame> boot(double w, double h) async {
      final game = SabayTayoGame(
        childId: 'test-child',
        onStepChanged: (_) {},
        onGameComplete: ({
          required int score,
          required int totalItems,
          required int errorCount,
          required int totalResponseTimeMs,
          required Map<String, dynamic> extras,
          GameSessionMetrics? analytics,
        }) {},
      );
      game.onGameResize(Vector2(w, h));
      await game.onLoad();
      await game.ready();
      return game;
    }

    for (final canvas in canvases) {
      final w = canvas[0];
      final h = canvas[1];

      test('no object hides under the overlay band at ${w}x$h', () async {
        final game = await boot(w, h);
        final objects = game.children.whereType<AttentionObject>().toList();
        expect(objects, isNotEmpty,
            reason: 'the game built no objects to look at');

        for (final object in objects) {
          // Cards are centre-anchored, so the top edge is half a card up.
          final top = object.position.y - object.size.y / 2;
          expect(top, greaterThanOrEqualTo(kTopOverlayBand),
              reason: '${object.data.name} reaches y=$top, inside the '
                  '$kTopOverlayBand px overlay band — the overlay eats the tap, '
                  'so the child follows the gaze correctly and nothing happens');
          expect(object.position.y + object.size.y / 2,
              lessThanOrEqualTo(h + 0.5),
              reason: '${object.data.name} runs off the bottom edge');
        }
      });

      test('objects never overlap each other or the buddy at ${w}x$h',
          () async {
        final game = await boot(w, h);
        final objects = game.children.whereType<AttentionObject>().toList();

        Rect boundsOf(PositionComponent c) => Rect.fromCenter(
              center: Offset(c.position.x, c.position.y),
              width: c.size.x,
              height: c.size.y,
            );

        for (var i = 0; i < objects.length; i++) {
          for (var j = i + 1; j < objects.length; j++) {
            expect(boundsOf(objects[i]).overlaps(boundsOf(objects[j])), isFalse,
                reason: '${objects[i].data.name} and ${objects[j].data.name} '
                    'overlap, so one of them is partly untappable');
          }
        }

        // The buddy is bottom-anchored; an object drawn over it would be a
        // target the child cannot see the cue for.
        final buddy = game.children.whereType<BuddyCharacter>().single;
        final buddyBounds = Rect.fromLTWH(
          buddy.position.x - buddy.size.x / 2,
          buddy.position.y - buddy.size.y,
          buddy.size.x,
          buddy.size.y,
        );
        for (final object in objects) {
          expect(boundsOf(object).overlaps(buddyBounds), isFalse,
              reason: '${object.data.name} is drawn over the buddy');
        }
      });

      test('every object lands in a distinct gaze cell at ${w}x$h', () async {
        // The invariant the whole game rests on, checked against the real
        // pixel positions rather than the slot table: a layout that squeezes
        // two cards into one gaze cell makes the correct answer unknowable.
        final game = await boot(w, h);
        final objects = game.children.whereType<AttentionObject>().toList();

        final cells = objects.map((o) {
          final f = o.fractionOf(Vector2(w, h), playfieldTop: kTopOverlayBand);
          return gazeActionFor(f.x, f.y) ?? 'rest';
        }).toList();

        expect(cells.toSet(), hasLength(cells.length),
            reason: 'two objects share the gaze cell $cells — the buddy would '
                'be looking at both and neither answer could be wrong');
      });
    }
  });
}
