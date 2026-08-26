import 'dart:math' as math;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/src/config/difficulty_profile.dart';
import 'package:game_core/src/games/trace_it/trace_it_game.dart';

/// Trace It's recognition policy — see the policy block in
/// `trace_it_game.dart`. Two directions are measured within the per-tier
/// tolerance: the ink must cover the guide (path → ink) and stay near it
/// (ink → path), the ink must reach both ends within the end allowance,
/// and an attempt that fails the policy at a lift is given retry feedback
/// instead of being silently kept or silently accepted.
void main() {
  late TraceItGame game;
  var completedRounds = 0;
  var wrongCount = 0;

  Future<void> startGame({int level = 1}) async {
    completedRounds = 0;
    wrongCount = 0;
    game = TraceItGame(
      childId: 'test-child',
      totalRounds: 4,
      profile: DifficultyProfile.forLevel(level),
      onStepChanged: (step) => completedRounds = step,
      onWrongAnswer: () => wrongCount++,
      onGameComplete: ({
        required score,
        required totalItems,
        required errorCount,
        required totalResponseTimeMs,
        analytics,
      }) {},
    );
    game.onGameResize(Vector2(800, 480));
    await game.onLoad();
    await game.ready();
  }

  DragStartEvent start(Vector2 at) =>
      DragStartEvent(1, game, DragStartDetails(globalPosition: at.toOffset()));

  DragUpdateEvent move(Vector2 to) =>
      DragUpdateEvent(1, game, DragUpdateDetails(globalPosition: to.toOffset()));

  DragEndEvent finish() => DragEndEvent(1, DragEndDetails());

  /// Drags along [path], reporting a pointer event every [stride] points
  /// and, when [release] is set, lifting the finger so the lift rules run.
  void drag(List<Vector2> path, {int stride = 1, bool release = false}) {
    game.onDragStart(start(path.first));
    for (var i = stride; i < path.length; i += stride) {
      game.onDragUpdate(move(path[i]));
    }
    game.onDragUpdate(move(path.last));
    if (release) game.onDragEnd(finish());
  }

  /// The prefix of [path] up to [fraction] of its arc length — what a trace
  /// that stops early looks like, irrespective of the resampling density.
  List<Vector2> upTo(List<Vector2> path, double fraction) {
    final cumulative = <double>[0];
    for (var i = 1; i < path.length; i++) {
      cumulative.add(cumulative.last + path[i].distanceTo(path[i - 1]));
    }
    final target = cumulative.last * fraction;
    var i = 1;
    while (i < cumulative.length && cumulative[i] < target) {
      i++;
    }
    if (i >= cumulative.length) return List.of(path);
    final seg = (target - cumulative[i - 1]) / (cumulative[i] - cumulative[i - 1]);
    final cut = path[i - 1] + (path[i] - path[i - 1]) * seg;
    return [...path.sublist(0, i), cut];
  }

  /// [path] shifted by [by] in canvas units.
  List<Vector2> shifted(List<Vector2> path, Vector2 by) =>
      [for (final p in path) p + by];

  /// A full circle of [radius] (normalised units) around [center], sampled
  /// densely — a wrong shape that happens to ride the guide.
  List<Vector2> circle(double cx, double cy, double radius) {
    final origin = game.debugGlyphOrigin;
    final side = game.debugGlyphSide;
    final points = <Vector2>[];
    const steps = 72;
    for (var i = 0; i <= steps; i++) {
      final a = i * 2 * math.pi / steps;
      points.add(origin +
          Vector2((cx + radius * math.cos(a)) * side,
              (cy + radius * math.sin(a)) * side));
    }
    return points;
  }

  group('valid traces are recognised within the documented tolerance', () {
    test('letter A, three strokes, completes at Hard', () async {
      await startGame(level: 3);
      game.debugForceGlyph('A');

      for (var stroke = 0; stroke < 3; stroke++) {
        drag(game.debugCurrentPath, release: true);
      }

      expect(
        completedRounds,
        1,
        reason: 'a correctly traced A must complete at level 3',
      );
      expect(wrongCount, 0);
    });

    test('letter T, two strokes, completes at Hard', () async {
      await startGame(level: 3);
      game.debugForceGlyph('T');

      for (var stroke = 0; stroke < 2; stroke++) {
        drag(game.debugCurrentPath, release: true);
      }

      expect(
        completedRounds,
        1,
        reason: 'a correctly traced T must complete at level 3',
      );
      expect(wrongCount, 0);
    });

    test('number 7 completes at Medium', () async {
      await startGame(level: 2);
      game.debugForceGlyph('7');

      drag(game.debugCurrentPath, release: true);

      expect(completedRounds, 1);
      expect(wrongCount, 0);
    });

    test('number 4, two strokes, completes at Hard', () async {
      await startGame(level: 3);
      game.debugForceGlyph('4');

      for (var stroke = 0; stroke < 2; stroke++) {
        drag(game.debugCurrentPath, release: true);
      }

      expect(completedRounds, 1);
      expect(wrongCount, 0);
    });

    test('a trace drawn in several breaths still completes', () async {
      await startGame(level: 1);
      game.debugForceGlyph('line across');
      final path = game.debugCurrentPath;

      // First breath: only 60% — incomplete but on-tolerance, so it must be
      // kept silently rather than counted as a mistake.
      drag(upTo(path, 0.6), release: true);
      expect(completedRounds, 0);
      expect(wrongCount, 0, reason: 'a pause on a correct trace is not a mistake');

      // Second breath: finishing the stroke completes the glyph.
      drag(path, release: true);
      expect(completedRounds, 1);
      expect(wrongCount, 0);
    });

    test('stopping 5% short of the end dot still completes', () async {
      await startGame(level: 1);
      game.debugForceGlyph('line across');

      drag(upTo(game.debugCurrentPath, 0.95), release: true);

      expect(
        completedRounds,
        1,
        reason: '5% shortfall is inside the 10% end allowance',
      );
      expect(wrongCount, 0);
    });
  });

  group('materially inaccurate traces are rejected', () {
    test('a zigzag scribble over the guide is not auto-corrected', () async {
      await startGame(level: 1);
      game.debugForceGlyph('line across');
      final origin = game.debugGlyphOrigin;
      final side = game.debugGlyphSide;

      // A square wave crossing the horizontal guide repeatedly: it passes
      // near the whole guide (full coverage), but most of its ink sits two
      // tolerance radii away from it — the old rule accepted it.
      final zigzag = <Vector2>[];
      const wave = 0.25;
      for (var i = 0; i <= 8; i++) {
        final x = origin.x + (0.1 + i * 0.1) * side;
        final up = i.isEven;
        zigzag
          ..add(Vector2(x, origin.y + (0.5 + (up ? -wave : wave)) * side))
          ..add(Vector2(x + 0.05 * side, origin.y + 0.5 * side));
      }
      drag(zigzag, release: true);

      expect(completedRounds, 0, reason: 'a scribble is not a trace');
      expect(wrongCount, 1, reason: 'it must be given retry feedback');
      expect(
        game.debugHasInk,
        isFalse,
        reason: 'the attempt is cleared so the retry starts clean',
      );
    });

    test('a circle drawn for the letter C is rejected', () async {
      await startGame(level: 2);
      game.debugForceGlyph('C');

      // The C is a 260° arc; a full circle covers it but a visible chunk of
      // its ink lies far outside the tolerance of the guide.
      drag(circle(0.5, 0.5, 0.35), release: true);

      expect(
        completedRounds,
        0,
        reason: 'a closed circle must not pass as the intended C',
      );
      expect(
        wrongCount,
        1,
        reason: 'riding the guide without following it gets retry feedback',
      );
    });

    test('a circle drawn for the letter U is rejected', () async {
      await startGame(level: 2);
      game.debugForceGlyph('U');

      drag(circle(0.5, 0.55, 0.25), release: true);

      expect(
        completedRounds,
        0,
        reason: 'a circle never reaches the tops of the U arms',
      );
      expect(wrongCount, 1);
    });

    test('an 8 drawn over the number 3 is rejected', () async {
      await startGame(level: 2);
      game.debugForceGlyph('3');

      final eight = [...circle(0.48, 0.33, 0.17), ...circle(0.48, 0.67, 0.17)];
      drag(eight, release: true);

      expect(
        completedRounds,
        0,
        reason: 'an 8 is not the intended 3, even though it covers it',
      );
      expect(wrongCount, 1);
    });

    test('a square around the number 3 is rejected', () async {
      await startGame(level: 2);
      game.debugForceGlyph('3');
      final origin = game.debugGlyphOrigin;
      final side = game.debugGlyphSide;

      final square = <Vector2>[
        origin + Vector2(0.28 * side, 0.14 * side),
        origin + Vector2(0.68 * side, 0.14 * side),
        origin + Vector2(0.68 * side, 0.86 * side),
        origin + Vector2(0.28 * side, 0.86 * side),
        origin + Vector2(0.28 * side, 0.14 * side),
      ];
      drag(square, release: true);

      expect(
        completedRounds,
        0,
        reason: 'a square is not the intended 3',
      );
      expect(wrongCount, 1);
    });
  });

  group('boundary cases give consistent feedback', () {
    test('a trace offset by exactly the tolerance completes', () async {
      await startGame(level: 1);
      game.debugForceGlyph('line across');

      drag(shifted(game.debugCurrentPath, Vector2(0, game.debugTolerance)),
          release: true);

      expect(
        completedRounds,
        1,
        reason: 'the tolerance boundary is inclusive by design',
      );
      expect(wrongCount, 0);
    });

    test('a trace offset beyond twice the tolerance is rejected', () async {
      await startGame(level: 1);
      game.debugForceGlyph('line across');

      drag(shifted(game.debugCurrentPath, Vector2(0, 2 * game.debugTolerance)),
          release: true);

      expect(completedRounds, 0);
      expect(wrongCount, 1);
    });

    test('stopping short of the end keeps progress and finishing completes',
        () async {
      await startGame(level: 1);
      game.debugForceGlyph('line across');
      final path = game.debugCurrentPath;

      // 15% short of the end dot (beyond the 10% end allowance): the ink is
      // still on tolerance, so the stroke stays pending and keeps its
      // progress — an early stop is not punished.
      drag(upTo(path, 0.85), release: true);
      expect(completedRounds, 0);
      expect(wrongCount, 0, reason: 'on-tolerance ink is never a mistake');
      expect(game.debugHasInk, isTrue);

      // Finishing the stroke completes the glyph.
      drag(path, release: true);
      expect(completedRounds, 1);
      expect(wrongCount, 0);
    });
  });
}
