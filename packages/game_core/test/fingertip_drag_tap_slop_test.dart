import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/src/games/match_it/components/matchable_shape.dart';
import 'package:game_core/src/games/my_turn_your_turn/components/game_piece.dart';

/// Match It and My Turn Your Turn put tap and drag on the SAME component and
/// tell them apart by how far the pointer travelled. Fingertip-centring has to
/// respect that line: a child whose tap wobbles must not have the piece leap
/// under their finger, and a real drag must still end up centred.
///
/// Sari-Sari Sort is drag-only and has no such threshold — it is covered by
/// draggable_item_fingertip_test.dart.
void main() {
  late FlameGame game;

  setUp(() {
    game = FlameGame();
    game.onGameResize(Vector2(800, 600));
  });

  DragStartEvent start(Vector2 at) =>
      DragStartEvent(1, game, DragStartDetails(globalPosition: at.toOffset()));

  DragUpdateEvent move(Vector2 to) =>
      DragUpdateEvent(1, game, DragUpdateDetails(globalPosition: to.toOffset()));

  void settle(PositionComponent c) {
    for (var i = 0; i < 20; i++) {
      c.update(1 / 60);
    }
  }

  group('Match It', () {
    late MatchableShape shape;
    Vector2? dropped;
    var selected = 0;

    setUp(() async {
      dropped = null;
      selected = 0;
      shape = MatchableShape(
        shapeType: ShapeType.star,
        shapeColor: const Color(0xFFFFAA00),
        index: 0,
        onSelected: (_) => selected++,
        onDragDropped: (_, at) => dropped = at,
        position: Vector2(100, 100),
        size: Vector2.all(120),
      );
      await game.add(shape);
      await game.ready();
    });

    test('a wobbly tap leaves the card in its slot', () {
      final home = shape.position.clone();
      shape.onDragStart(start(Vector2(160, 160)));
      shape.onDragUpdate(move(Vector2(166, 164))); // ~7px, under the slop
      settle(shape);

      expect(shape.position, home,
          reason: 'a shaky tap must not drag the card off its slot');

      shape.onDragEnd(DragEndEvent(1, DragEndDetails()));
      expect(selected, 1, reason: 'and it should still register as a tap');
      expect(dropped, isNull);
    });

    test('a real drag centres the card and drops at the fingertip', () {
      shape.onDragStart(start(Vector2(160, 160)));
      shape.onDragUpdate(move(Vector2(260, 260))); // well past the slop
      settle(shape);
      shape.onDragUpdate(move(Vector2(500, 400)));
      shape.update(1 / 60);

      expect(shape.visualCenter.x, closeTo(500, 0.5));
      expect(shape.visualCenter.y, closeTo(400, 0.5));

      shape.onDragEnd(DragEndEvent(1, DragEndDetails()));
      expect(dropped, isNotNull);
      expect(dropped!.x, closeTo(500, 0.5));
      expect(dropped!.y, closeTo(400, 0.5));
      expect(selected, 0, reason: 'a drag is not a selection');
    });
  });

  group('My Turn Your Turn', () {
    late GamePiece piece;
    Vector2? dropped;

    setUp(() async {
      dropped = null;
      piece = GamePiece(
        emoji: '🐢',
        color: const Color(0xFF42B4E8),
        isChild: true,
        onDragEnded: (_, at) => dropped = at,
        position: Vector2(200, 200),
        size: Vector2.all(100),
      )..interactive = true;
      await game.add(piece);
      await game.ready();
    });

    test('a wobbly tap leaves the piece in the tray', () {
      final home = piece.position.clone();
      piece.onDragStart(start(Vector2(200, 200)));
      piece.onDragUpdate(move(Vector2(205, 203)));
      settle(piece);

      expect(piece.position, home);
    });

    test('a centre-anchored piece still lands exactly on the fingertip', () {
      // This piece uses Anchor.center, so its position IS its centre — the
      // half-size offset the other games need would put it out by half a
      // piece here.
      piece.onDragStart(start(Vector2(200, 200)));
      piece.onDragUpdate(move(Vector2(300, 300)));
      settle(piece);
      piece.onDragUpdate(move(Vector2(430, 360)));
      piece.update(1 / 60);

      expect(piece.visualCenter.x, closeTo(430, 0.5));
      expect(piece.visualCenter.y, closeTo(360, 0.5));

      piece.onDragEnd(DragEndEvent(1, DragEndDetails()));
      expect(dropped!.x, closeTo(430, 0.5));
      expect(dropped!.y, closeTo(360, 0.5));
    });
  });
}
