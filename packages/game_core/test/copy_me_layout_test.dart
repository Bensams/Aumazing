import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
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

  group('palette tap vs drag', () {
    late FlameGame host;
    late SequenceShape card;
    var tapped = 0;
    Vector2? dropped;

    setUp(() async {
      host = FlameGame();
      host.onGameResize(Vector2(800, 600));
      tapped = 0;
      dropped = null;
      card = SequenceShape(
        shapeType: CopyMeShapeType.circle,
        shapeColor: const Color(0xFF43A047),
        index: 0,
        onTapped: (_) => tapped++,
        onDragDropped: (_, at) => dropped = at,
        position: Vector2(100, 400),
        size: Vector2.all(120),
      )..inputEnabled = true;
      await host.add(card);
      await host.ready();
    });

    DragStartEvent start(Vector2 at) =>
        DragStartEvent(1, host, DragStartDetails(globalPosition: at.toOffset()));
    DragUpdateEvent move(Vector2 to) => DragUpdateEvent(
        1, host, DragUpdateDetails(globalPosition: to.toOffset()));

    test('a still (or wobbly) press registers as a tap, not a drag', () {
      final home = card.position.clone();
      card.onDragStart(start(Vector2(160, 460)));
      card.onDragUpdate(move(Vector2(166, 464))); // ~7px, under the slop
      card.onDragEnd(DragEndEvent(1, DragEndDetails()));

      expect(tapped, 1, reason: 'a press that barely moves is a tap');
      expect(dropped, isNull);
      expect(card.position, home, reason: 'a tap must not move the card');
    });

    test('a real drag reports a drop, not a tap', () {
      card.onDragStart(start(Vector2(160, 460)));
      card.onDragUpdate(move(Vector2(300, 200))); // well past the slop
      card.update(1 / 60);
      card.onDragUpdate(move(Vector2(400, 150)));
      card.update(1 / 60);
      card.onDragEnd(DragEndEvent(1, DragEndDetails()));

      expect(dropped, isNotNull, reason: 'a drag reports where it was dropped');
      expect(tapped, 0, reason: 'a drag is not a tap');
    });
  });
}
