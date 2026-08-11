import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
// Not exported from the package barrel — the overlay band is an internal
// layout contract between the app chrome and the games, and this test exists
// precisely to hold the game to it.
import 'package:game_core/src/games/shared/game_layout.dart';
import 'package:shared_ui/shared_ui.dart';

/// The Sari-Sari Store Sorting game after the three-category rework
/// (toys / food / essentials).
///
/// These cover the failures that are invisible until a child hits them: a
/// catalogue whose items disagree with the list they sit in marks a correct
/// answer wrong, a bin label that resolves to English in a Cebuano session is
/// a word the child cannot read, and a basket pushed under the overlay band is
/// a target whose touch is eaten before the game ever sees it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('categories', () {
    test('the three sorted categories are toys, food and essentials', () {
      expect(
        StoreCategory.values.map((c) => c.slug),
        ['toys', 'food', 'essentials'],
      );
    });

    test('every category has its own picture and colour', () {
      final emoji = StoreCategory.values.map((c) => c.emoji).toSet();
      final colors = StoreCategory.values.map((c) => c.color).toSet();
      expect(emoji, hasLength(StoreCategory.values.length));
      expect(colors, hasLength(StoreCategory.values.length));
    });
  });

  group('catalogue', () {
    final catalogue = SariSariSortGame.catalogue;

    test('every category is stocked', () {
      for (final category in StoreCategory.values) {
        expect(catalogue[category], isNotNull,
            reason: '${category.slug} has no items at all');
        expect(catalogue[category], isNotEmpty);
      }
    });

    test('each item agrees with the category it is filed under', () {
      catalogue.forEach((category, items) {
        for (final item in items) {
          expect(item.category, category,
              reason: '${item.name} sits in ${category.slug} but claims '
                  '${item.category.slug} — the game would mark a correct drop '
                  'as wrong');
        }
      });
    });

    test('categories are balanced within one item of each other', () {
      final counts = catalogue.values.map((l) => l.length).toList();
      final spread = counts.reduce((a, b) => a > b ? a : b) -
          counts.reduce((a, b) => a < b ? a : b);
      expect(spread, lessThanOrEqualTo(1),
          reason: 'an over-stocked category dominates what the child ever '
              'meets across a session (counts: $counts)');
    });

    test('item names are unique across the whole catalogue', () {
      final names =
          catalogue.values.expand((l) => l.map((d) => d.name)).toList();
      expect(names.toSet(), hasLength(names.length));
    });

    test('drinks are folded into food, not a category of their own', () {
      final foodNames =
          catalogue[StoreCategory.food]!.map((d) => d.name).toList();
      expect(foodNames, containsAll(['Gatas', 'Tubig']));
    });

    test('every item prints an English word in an English session', () {
      // 'Teddy' is the same word in both, so identical labels are allowed —
      // what is not allowed is a blank or an untranslated Filipino staple.
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
        'Tisyu',
        'Syampu',
      };
      for (final item in catalogue.values.expand((l) => l)) {
        final en = item.label(GameLanguage.english);
        expect(en.trim(), isNotEmpty,
            reason: '${item.name} has no English label');
        expect(stillFilipino, isNot(contains(en)),
            reason: '${item.name} still prints Filipino in English');
      }
    });

    test('Tagalog and Cebuano keep the Filipino item name', () {
      for (final item in catalogue.values.expand((l) => l)) {
        expect(item.label(GameLanguage.tagalog), item.name);
        expect(item.label(GameLanguage.cebuano), item.name);
      }
    });
  });

  group('bin labels', () {
    test('resolve to a distinct, non-empty word in all three languages', () {
      for (final language in GameLanguage.values) {
        final strings = AppStrings(language);
        final labels = [
          strings.binToys,
          strings.binFood,
          strings.binEssentials,
        ];
        for (final label in labels) {
          expect(label.trim(), isNotEmpty,
              reason: 'a blank basket label in ${language.name}');
        }
        expect(labels.toSet(), hasLength(3),
            reason: 'two baskets share a label in ${language.name}, so the '
                'child cannot tell them apart');
      }
    });

    test('Tagalog and Cebuano are translated, not English left in place', () {
      final english = AppStrings(GameLanguage.english);
      for (final language in [GameLanguage.tagalog, GameLanguage.cebuano]) {
        final strings = AppStrings(language);
        expect(strings.binToys, isNot(english.binToys),
            reason: '${language.name} toys label is still the English one');
        expect(strings.sortInstruction, isNot(english.sortInstruction),
            reason: '${language.name} instruction is still the English one');
      }
    });

    test('the instruction names both the object and the action', () {
      // Retiring the bare verb "Sort": the child is told what to move and
      // where, not merely to sort.
      for (final language in GameLanguage.values) {
        final instruction = AppStrings(language).sortInstruction;
        expect(instruction.split(' ').length, greaterThanOrEqualTo(5),
            reason: '${language.name} instruction is too terse to name the '
                'object and the action');
        expect(instruction.toLowerCase(), contains('basket'));
      }
    });
  });

  group('layout', () {
    /// A phone and a tablet in landscape, plus a deliberately short canvas —
    /// the case where a proportional layout is most likely to push a basket up
    /// under the overlay band.
    const canvases = [
      [800.0, 360.0],
      [1280.0, 720.0],
      [960.0, 300.0],
    ];

    for (final canvas in canvases) {
      final w = canvas[0];
      final h = canvas[1];

      test('nothing collides with the overlay band at ${w}x$h', () async {
        final game = SariSariSortGame(
          childId: 'test-child',
          onStepChanged: (_) {},
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            GameSessionMetrics? analytics,
          }) {},
        );
        game.onGameResize(Vector2(w, h));
        await game.onLoad();
        await game.ready();

        final positioned = game.children.whereType<PositionComponent>().toList();
        expect(positioned, isNotEmpty,
            reason: 'the game built no visible components at all');

        for (final component in positioned) {
          expect(component.position.y, greaterThanOrEqualTo(kTopOverlayBand),
              reason: '${component.runtimeType} starts at '
                  'y=${component.position.y}, inside the $kTopOverlayBand px '
                  'overlay band — the overlay would eat its touches');
          expect(component.position.y + component.size.y,
              lessThanOrEqualTo(h + 0.5),
              reason: '${component.runtimeType} runs off the bottom edge');
        }
      });

      test('baskets and items never overlap at ${w}x$h', () async {
        final game = SariSariSortGame(
          childId: 'test-child',
          onStepChanged: (_) {},
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            GameSessionMetrics? analytics,
          }) {},
        );
        game.onGameResize(Vector2(w, h));
        await game.onLoad();
        await game.ready();

        // An item resting on top of a basket is a drop the child never had to
        // make, and a basket the child cannot see.
        final items = game.children.whereType<DraggableItem>();
        final bins = game.children.whereType<CategoryBin>();
        expect(bins, hasLength(StoreCategory.values.length));

        for (final item in items) {
          final itemBottom = item.position.y + item.size.y;
          for (final bin in bins) {
            expect(itemBottom, lessThanOrEqualTo(bin.position.y + 0.5),
                reason: '${item.data.name} overlaps a basket at rest');
          }
        }
      });
    }
  });
}
