import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/src/games/sari_sari_sort/components/draggable_item.dart';
import 'package:game_core/src/games/sari_sari_sort/sari_sari_sort_game.dart';

/// A dragged item must end up centred on the child's fingertip, so the point
/// they aim at is the point that gets hit-tested against the baskets.
void main() {
  const item = StoreItemData(
    name: 'Gatas',
    emoji: '🥛',
    category: StoreCategory.food,
    color: Color(0xFFF1EEE2),
  );

  late FlameGame game;
  late DraggableItem subject;
  Vector2? droppedAt;

  /// Runs enough frames to cover the pickup glide.
  void settle() {
    for (var i = 0; i < 20; i++) {
      subject.update(1 / 60);
    }
  }

  setUp(() async {
    droppedAt = null;
    game = FlameGame();
    game.onGameResize(Vector2(800, 600));
    subject = DraggableItem(
      data: item,
      color: item.color,
      onPickedUp: (_) {},
      onDropped: (_, center) => droppedAt = center,
      position: Vector2(100, 100),
      size: Vector2.all(120),
    );
    await game.add(subject);
    await game.ready();
  });

  DragStartEvent start(Vector2 at) => DragStartEvent(
        1,
        game,
        DragStartDetails(globalPosition: at.toOffset()),
      );

  DragUpdateEvent move(Vector2 to) => DragUpdateEvent(
        1,
        game,
        DragUpdateDetails(globalPosition: to.toOffset()),
      );

  test('grabbing a corner glides the item under the fingertip', () {
    // Touch the item's top-left corner, well off its centre.
    subject.onDragStart(start(Vector2(105, 105)));

    // The item must not teleport on the very first frame — a jump under a
    // child's finger reads as the item escaping them.
    subject.update(1 / 60);
    expect((subject.visualCenter - Vector2(105, 105)).length, greaterThan(10));

    settle();
    expect(subject.visualCenter.x, closeTo(105, 0.5));
    expect(subject.visualCenter.y, closeTo(105, 0.5));
  });

  test('the item tracks the fingertip absolutely, not by accumulated delta',
      () {
    subject.onDragStart(start(Vector2(160, 160)));
    settle();

    subject.onDragUpdate(move(Vector2(400, 300)));
    subject.update(1 / 60);

    expect(subject.visualCenter.x, closeTo(400, 0.5));
    expect(subject.visualCenter.y, closeTo(300, 0.5));
  });

  test('the drop point is the fingertip, so bin hit-testing is exact', () {
    subject.onDragStart(start(Vector2(130, 130)));
    settle();
    subject.onDragUpdate(move(Vector2(520, 430)));
    subject.update(1 / 60);

    subject.onDragEnd(DragEndEvent(1, DragEndDetails()));

    expect(droppedAt, isNotNull);
    expect(droppedAt!.x, closeTo(520, 0.5));
    expect(droppedAt!.y, closeTo(430, 0.5));
  });

  test('a locked item ignores the fingertip', () {
    subject.isLocked = true;
    final before = subject.position.clone();

    subject.onDragStart(start(Vector2(400, 400)));
    settle();

    expect(subject.position, before);
  });
}
