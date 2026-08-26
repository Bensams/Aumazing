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
    en: 'Milk',
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

  group('a card configured to shrink while held', () {
    late FlameGame shrinkGame;
    late DraggableItem shrinkSubject;

    setUp(() async {
      droppedAt = null;
      shrinkGame = FlameGame();
      shrinkGame.onGameResize(Vector2(800, 600));
      // Without mount() the root is never live, and effects added to
      // components are updated before they are mounted — Flame then trips
      // over a null effect target. Same harness plumbing as the match_it
      // tests; mount() is Flame's own hook for exactly this.
      // ignore: invalid_use_of_internal_member
      shrinkGame.mount();
      await shrinkGame.onLoad();
      await shrinkGame.ready();
      shrinkSubject = DraggableItem(
        data: item,
        color: item.color,
        onPickedUp: (_) {},
        onDropped: (_, center) => droppedAt = center,
        dragScale: 0.5,
        position: Vector2(100, 100),
        size: Vector2.all(120),
      );
      await shrinkGame.add(shrinkSubject);
      await shrinkGame.ready();
    });

    /// Frame-advances the whole game so effects (the scale animations) run —
    /// [DraggableItem.update] alone does not tick them.
    void held(double seconds) {
      final frames = (seconds * 60).round();
      for (var i = 0; i < frames; i++) {
        shrinkGame.update(1 / 60);
      }
    }

    test('shrinks under the fingertip it keeps centred', () {
      shrinkSubject.onDragStart(start(Vector2(160, 160)));
      held(1); // covers the 0.12s scale effect and the 0.12s grab glide

      expect(shrinkSubject.scale.x, closeTo(0.5, 0.01));
      expect(shrinkSubject.scale.y, closeTo(0.5, 0.01));
      expect(shrinkSubject.visualCenter.x, closeTo(160, 0.5));
      expect(shrinkSubject.visualCenter.y, closeTo(160, 0.5));
    });

    test('the drop point is the fingertip even while shrunk', () {
      shrinkSubject.onDragStart(start(Vector2(160, 160)));
      held(1);
      shrinkSubject.onDragUpdate(move(Vector2(520, 430)));
      held(0.1);

      shrinkSubject.onDragEnd(DragEndEvent(1, DragEndDetails()));

      expect(droppedAt, isNotNull);
      expect(droppedAt!.x, closeTo(520, 0.5));
      expect(droppedAt!.y, closeTo(430, 0.5));
    });

    test('grows back to full size when released', () {
      shrinkSubject.onDragStart(start(Vector2(160, 160)));
      held(1);
      shrinkSubject.onDragEnd(DragEndEvent(1, DragEndDetails()));
      held(1);

      expect(shrinkSubject.scale.x, closeTo(1.0, 0.01));
      expect(shrinkSubject.scale.y, closeTo(1.0, 0.01));
    });

    test('cancelling mid-pickup restores full size, home, and never drops', () {
      shrinkSubject.onDragStart(start(Vector2(160, 160)));
      held(0.05); // the 0.12s pickup scale effect is still in flight

      shrinkSubject.onDragCancel(DragCancelEvent(1));
      // Let the restore effect and the return-home move run to completion.
      held(1);

      expect(shrinkSubject.scale.x, closeTo(1.0, 0.01),
          reason:
              'the in-flight pickup effect must not keep writing scale after '
              'a cancel');
      expect(shrinkSubject.scale.y, closeTo(1.0, 0.01));
      expect(shrinkSubject.position.x, closeTo(100, 0.5));
      expect(shrinkSubject.position.y, closeTo(100, 0.5));
      expect(droppedAt, isNull,
          reason:
              'a cancel must not be scored as a drop — Flame dispatches '
              'onDragEnd from DragCallbacks.onDragCancel, which must not run '
              'the component drop path');

      // The drag state is cleared, so a later onDragEnd cannot score the
      // cancelled drag either.
      shrinkSubject.onDragEnd(DragEndEvent(1, DragEndDetails()));
      held(0.5);
      expect(droppedAt, isNull);
    });

    test('releasing mid-pickup restores full size, so the release wins', () {
      shrinkSubject.onDragStart(start(Vector2(160, 160)));
      held(0.05); // the 0.12s pickup scale effect is still in flight

      shrinkSubject.onDragEnd(DragEndEvent(1, DragEndDetails()));
      held(1);

      // The invariant under test: the release restore must win over the
      // still-running pickup effect. (The item is deliberately not settled on
      // the fingertip here — the glide was interrupted mid-pickup — so the
      // drop-point precision is asserted by the settled test above instead.)
      expect(shrinkSubject.scale.x, closeTo(1.0, 0.01),
          reason: 'a quick grab-and-release must not leave the card shrunk');
      expect(shrinkSubject.scale.y, closeTo(1.0, 0.01));
      expect(droppedAt, isNotNull);
    });
  });
}
