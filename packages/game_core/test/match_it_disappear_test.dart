import 'dart:ui' as ui;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

/// A matched pair leaves the board.
///
/// The failures these guard against are a child tapping a card that is
/// visually spent but still live, and — subtler — a round that never completes
/// because the "all three matched" check was reading components that had
/// already removed themselves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// One full exit, plus a little slack for the removal to be processed.
  final exitSeconds =
      MatchableShape.matchExitDuration.inMilliseconds / 1000 + 0.1;

  /// Runs [seconds] of game time in engine-sized steps.
  void advance(FlameGame game, double seconds) {
    const step = 1 / 60;
    for (var elapsed = 0.0; elapsed < seconds; elapsed += step) {
      game.update(step);
    }
  }

  Future<MatchItGame> loadGame({
    void Function(int)? onStepChanged,
    void Function()? onCorrectMatch,
  }) async {
    final game = MatchItGame(
      childId: 'test-child',
      onStepChanged: onStepChanged ?? (_) {},
      onCorrectMatch: onCorrectMatch,
      onGameComplete: ({
        required int score,
        required int totalItems,
        required int errorCount,
        required int totalResponseTimeMs,
        GameSessionMetrics? analytics,
      }) {},
    );
    game.onGameResize(Vector2(1280, 800));
    // Without mount() the root is never live, and effects added to components
    // are updated before they are mounted — Flame then trips over a null
    // effect target. This is harness plumbing, not game behaviour; mount() is
    // Flame's own hook for exactly this and there is no public equivalent.
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.onLoad();
    await game.ready();
    return game;
  }

  List<MatchableShape> shapesOnBoard(FlameGame game) =>
      game.children.whereType<MatchableShape>().toList();

  /// The left and right card that match each other for pair [index].
  ({MatchableShape left, MatchableShape right}) pairOnBoard(
    FlameGame game,
    int index,
  ) {
    final matching =
        shapesOnBoard(game).where((s) => s.index == index).toList();
    expect(matching, hasLength(2),
        reason: 'expected a left and a right card for pair $index');
    matching.sort((a, b) => a.position.x.compareTo(b.position.x));
    return (left: matching.first, right: matching.last);
  }

  /// Taps both halves of pair [index] and lets the exit animation finish.
  void matchPair(MatchItGame game, int index) {
    final pair = pairOnBoard(game, index);
    pair.left.onSelected(pair.left.index);
    pair.right.onSelected(pair.right.index);
    advance(game, exitSeconds);
  }

  group('a matched pair disappears', () {
    test('both cards leave the board after a tap match', () async {
      final game = await loadGame();
      expect(shapesOnBoard(game), hasLength(6));

      final pair = pairOnBoard(game, 0);
      pair.left.onSelected(pair.left.index);
      pair.right.onSelected(pair.right.index);

      // The feedback beat: both cards are still there, and still lit.
      advance(game, 0.2);
      expect(shapesOnBoard(game), hasLength(6),
          reason: 'the cards vanished before the correct feedback was shown');

      advance(game, exitSeconds);

      final remaining = shapesOnBoard(game);
      expect(remaining, hasLength(4));
      expect(remaining.any((s) => identical(s, pair.left)), isFalse);
      expect(remaining.any((s) => identical(s, pair.right)), isFalse);
      expect(pair.left.hasDisappeared, isTrue);
      expect(pair.right.hasDisappeared, isTrue);
    });

    test('both cards leave the board after a drag match', () async {
      final game = await loadGame();
      final pair = pairOnBoard(game, 1);

      // Drop the left card onto its match in the right column.
      pair.left.onDragDropped!(
        pair.left,
        pair.right.position + pair.right.size / 2,
      );
      advance(game, exitSeconds);

      expect(shapesOnBoard(game), hasLength(4));
      expect(pair.left.hasDisappeared, isTrue);
      expect(pair.right.hasDisappeared, isTrue);
    });

    test('the cards fade and shrink on the way out', () async {
      final game = await loadGame();
      final pair = pairOnBoard(game, 0);

      pair.left.onSelected(pair.left.index);
      pair.right.onSelected(pair.right.index);

      // Part-way through the exit: still on the board, already shrinking.
      advance(game, 0.45 + 0.15);
      expect(pair.left.isMounted, isTrue,
          reason: 'the card jumped off the board instead of animating out');
      expect(pair.left.hasDisappeared, isFalse);
      expect(pair.left.matchScale, lessThan(0.9),
          reason: 'the card is not scaling down as it leaves');
    });

    test('the match animation never writes to position or scale', () async {
      final game = await loadGame();
      final pair = pairOnBoard(game, 0);
      final home = pair.left.position.clone();
      final componentScales = <double>{};

      pair.left.onSelected(pair.left.index);
      pair.right.onSelected(pair.right.index);

      for (var i = 0; i < 40; i++) {
        advance(game, 1 / 60);
        if (!pair.left.isMounted) break;
        expect(pair.left.position.x, closeTo(home.x, 0.001));
        expect(pair.left.position.y, closeTo(home.y, 0.001));
        componentScales.add(pair.left.scale.x);
      }
      // The whole animation lives in the render transform, so the component's
      // own scale never moves — anything else would drag the card off-centre.
      expect(componentScales, hasLength(1),
          reason: 'the match animation moved the component scale instead of '
              'drawing the card smaller');
      expect(pair.left.matchScale, lessThan(1.0),
          reason: 'the card never shrank, so the check proved nothing');
    });
  });

  group('the card recedes in place', () {
    /// The centre of everything the card actually paints, in canvas pixels.
    ///
    /// Rendered through [Component.renderTree] rather than `render`, so the
    /// component's own transform is included — that is precisely where a
    /// top-left-anchored scale would show up.
    Future<Offset> paintedCentre(MatchableShape shape, double side) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      shape.renderTree(canvas);
      final image = await recorder
          .endRecording()
          .toImage(side.round(), side.round());
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      var minX = image.width, minY = image.height, maxX = -1, maxY = -1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final alpha = data!.getUint8((y * image.width + x) * 4 + 3);
          if (alpha == 0) continue;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
      expect(maxX, greaterThanOrEqualTo(0), reason: 'the card painted nothing');
      return Offset((minX + maxX) / 2, (minY + maxY) / 2);
    }

    test('it shrinks toward its own centre, not its top-left corner',
        () async {
      const side = 128.0;
      final host = FlameGame()..onGameResize(Vector2(side, side));
      // ignore: invalid_use_of_internal_member
      host.mount();
      final shape = MatchableShape(
        shapeType: ShapeType.circle,
        shapeColor: const Color(0xFF1E88E5),
        index: 0,
        onSelected: (_) {},
        position: Vector2.zero(),
        size: Vector2.all(side),
      );
      await host.add(shape);
      await host.ready();

      final before = await paintedCentre(shape, side);

      shape.markMatched();
      // Run to roughly the middle of the exit, where the card is visibly
      // smaller but still on the board.
      while (shape.isMounted && shape.matchScale > 0.75) {
        host.update(1 / 60);
      }
      expect(shape.isMounted, isTrue);
      expect(shape.matchScale, lessThan(1.0));

      final during = await paintedCentre(shape, side);

      // Anchored at top-left, a scaled-down card's centre would march toward
      // (0, 0) by several pixels. Receding in place holds it still.
      expect(during.dx, closeTo(before.dx, 2.0),
          reason: 'the card slid horizontally as it shrank');
      expect(during.dy, closeTo(before.dy, 2.0),
          reason: 'the card slid vertically as it shrank');
    });
  });

  group('matched cards refuse further input', () {
    late FlameGame host;
    late MatchableShape shape;
    var selected = 0;

    setUp(() async {
      selected = 0;
      host = FlameGame();
      host.onGameResize(Vector2(800, 600));
      // ignore: invalid_use_of_internal_member
      host.mount();
      shape = MatchableShape(
        shapeType: ShapeType.star,
        shapeColor: const Color(0xFFFFAA00),
        index: 0,
        onSelected: (_) => selected++,
        position: Vector2(100, 100),
        size: Vector2.all(120),
      );
      await host.add(shape);
      await host.ready();
    });

    test('a tap lands before the match and is refused after it', () {
      // A still tap resolves through onDragEnd (see MatchableShape).
      shape.onDragStart(
        DragStartEvent(1, host, DragStartDetails(globalPosition: Offset.zero)),
      );
      shape.onDragEnd(DragEndEvent(1, DragEndDetails()));
      expect(selected, 1, reason: 'a live card should accept a tap');

      shape.markMatched();

      // Mid-exit the card is still mounted — tap it again.
      host.update(1 / 60);
      expect(shape.isMounted, isTrue);
      shape.onDragStart(
        DragStartEvent(1, host, DragStartDetails(globalPosition: Offset.zero)),
      );
      shape.onDragEnd(DragEndEvent(1, DragEndDetails()));
      shape.onTapUp(TapUpEvent(1, host, TapUpDetails(kind: PointerDeviceKind.touch)));

      expect(selected, 1,
          reason: 'a card on its way out registered another selection');
    });

    test('markMatched is idempotent', () {
      shape.markMatched();
      for (var i = 0; i < 12; i++) {
        host.update(1 / 60);
      }
      shape.markMatched(); // a duplicate call must not restart the exit

      for (var i = 0; i < 60; i++) {
        host.update(1 / 60);
      }
      expect(shape.hasDisappeared, isTrue);
    });
  });

  group('a vanishing card is not a drop target', () {
    test('a drag onto a matched card is not a match attempt', () async {
      final game = await loadGame();
      final matched = pairOnBoard(game, 0);
      matched.left.onSelected(matched.left.index);
      matched.right.onSelected(matched.right.index);
      advance(game, 0.2); // mid-exit, still mounted

      final other = pairOnBoard(game, 1);
      other.left.onDragDropped!(
        other.left,
        matched.right.position + matched.right.size / 2,
      );

      expect(other.left.isMatched, isFalse,
          reason: 'a card on its way out acted as a drop target');
      expect(other.left.isMounted, isTrue);
    });
  });

  group('the board and the round survive the disappearance', () {
    test('the remaining cards do not move', () async {
      final game = await loadGame();
      final survivors = <MatchableShape, Vector2>{
        for (final s in shapesOnBoard(game))
          if (s.index != 0) s: s.position.clone(),
      };

      matchPair(game, 0);

      survivors.forEach((shape, original) {
        expect(shape.position.x, closeTo(original.x, 0.001),
            reason: 'the board re-centred after a pair disappeared');
        expect(shape.position.y, closeTo(original.y, 0.001));
      });
    });

    test('all three pairs matched still completes the round', () async {
      final steps = <int>[];
      final game = await loadGame(onStepChanged: steps.add);

      matchPair(game, 0);
      matchPair(game, 1);
      expect(steps, isEmpty, reason: 'the round completed early');

      matchPair(game, 2);

      expect(steps, [1],
          reason: 'the round did not complete once every pair had gone');
      expect(shapesOnBoard(game), isEmpty,
          reason: 'the last pair was still on the board');
    });

    test('the next round is dealt after the last pair has gone', () async {
      final game = await loadGame();
      matchPair(game, 0);
      matchPair(game, 1);
      matchPair(game, 2);
      expect(shapesOnBoard(game), isEmpty);

      await Future<void>.delayed(
        MatchItGame.roundTransitionDelay + const Duration(milliseconds: 200),
      );
      advance(game, 0.1); // let the new components mount

      expect(shapesOnBoard(game), hasLength(6),
          reason: 'the next round was never dealt');
    });

    test('the round transition never cuts off a disappearing card', () {
      expect(
        MatchItGame.roundTransitionDelay.inMilliseconds,
        greaterThanOrEqualTo(MatchableShape.matchExitDuration.inMilliseconds),
        reason: 'the board would re-deal over a half-faded card',
      );
    });
  });
}
