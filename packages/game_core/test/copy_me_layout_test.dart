import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

/// The redesigned Copy Me board has two rows: a top *pattern row* of four
/// placeholder slots the pattern is shown in, and a bottom *palette* of the four
/// tappable / draggable shape cards the child copies it with.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CopyMeGame> loadGame() async {
    final game = CopyMeGame(
      totalRounds: 4,
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
    game.onGameResize(Vector2(1280, 800));
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.onLoad();
    await game.ready();
    return game;
  }

  List<PatternSlot> slots(FlameGame g) =>
      g.children.whereType<PatternSlot>().toList();
  List<SequenceShape> palette(FlameGame g) =>
      g.children.whereType<SequenceShape>().toList();

  test('lays out four pattern slots and four palette cards', () async {
    final game = await loadGame();

    expect(slots(game), hasLength(4));
    expect(palette(game), hasLength(4));
  });

  test('pattern slots start empty and sit above the palette', () async {
    final game = await loadGame();

    final topRow = slots(game)..sort((a, b) => a.index.compareTo(b.index));
    final bottomRow = palette(game)..sort((a, b) => a.index.compareTo(b.index));

    // Nothing is copied yet, so every slot is an empty placeholder.
    expect(topRow.every((s) => !s.isFilled), isTrue);

    // The pattern row is drawn above the palette it is copied from.
    for (var i = 0; i < 4; i++) {
      expect(topRow[i].position.y, lessThan(bottomRow[i].position.y));
    }
  });

  test('palette cards begin with input disabled during the demo', () async {
    final game = await loadGame();
    // Input is only handed to the child once the demo has played.
    expect(palette(game).every((c) => !c.inputEnabled), isTrue);
  });
}
