import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/src/config/difficulty_profile.dart';
import 'package:game_core/src/games/shared/answer_label.dart';
import 'package:game_core/src/games/trace_it/trace_it_game.dart';
import 'package:game_core/src/games/trace_it/trace_glyphs.dart';

/// Trace It measures how much of the guide path the finger covered. Two things
/// decide whether that measurement matches what the child actually drew: where
/// the pointer is believed to be, and what happens between two pointer samples.
/// Both used to be wrong, and both fail silently — a correct trace simply never
/// completes, which reads to a child as the game ignoring them.
void main() {
  late TraceItGame game;
  var completedRounds = 0;
  AnswerLabel? spokenLabel;

  Future<void> startGame() async {
    completedRounds = 0;
    spokenLabel = null;
    game = TraceItGame(
      childId: 'test-child',
      totalRounds: 4,
      // Level 1 is the single-stroke pre-writing pool, so one swipe is a whole
      // glyph and the assertions stay about coverage rather than stroke order.
      profile: DifficultyProfile.forLevel(1),
      onStepChanged: (step) => completedRounds = step,
      onPlayCorrectVo: (label) => spokenLabel = label,
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

  /// Drags along [path], reporting a pointer event only every [stride] points
  /// and releasing the finger — strokes complete at the lift.
  ///
  /// This is what a fast swipe looks like: the finger really does follow the
  /// guide — corners included — but the pointer is polled far less often than
  /// the path was sampled, so consecutive events sit well over a tolerance
  /// apart. Straight chords between distant samples would model something
  /// else entirely (a child cutting the corner), which is a wrong trace and
  /// ought to fail.
  void swipe(List<Vector2> path, {required int stride}) {
    game.onDragStart(start(path.first));
    for (var i = stride; i < path.length; i += stride) {
      game.onDragUpdate(move(path[i]));
    }
    game.onDragUpdate(move(path.last));
    game.onDragEnd(DragEndEvent(1, DragEndDetails()));
  }

  test('a fast swipe along the guide still completes the stroke', () async {
    await startGame();

    // The whole glyph traced accurately, but polled every twelfth point —
    // gaps four to five times the tolerance. Marking coverage only at the
    // sampled points leaves the path dotted, well under the threshold, and
    // the stroke never completes.
    swipe(game.debugCurrentPath, stride: 12);

    expect(
      completedRounds,
      1,
      reason: 'an accurate trace must complete however fast it was drawn',
    );
  });

  test('the same swipe reported point-by-point also completes', () async {
    await startGame();

    swipe(game.debugCurrentPath, stride: 1);

    expect(completedRounds, 1);
    expect(game.debugHasInk, isFalse);
  });

  test('a completed shape is named through the existing feedback callback',
      () async {
    await startGame();
    game.debugForceGlyph('square');

    swipe(game.debugCurrentPath, stride: 1);

    expect(completedRounds, 1);
    expect(spokenLabel?.shape, 'square');
    expect(spokenLabel?.letter, isNull);
  });

  test('a swipe nowhere near the guide does not complete it', () async {
    await startGame();

    final path = game.debugCurrentPath;
    // Same shape, displaced far off the guide: coverage must stay at zero
    // rather than the interpolation sweeping points in by accident.
    swipe(
      [for (final p in path) p + Vector2(0, 200)],
      stride: 12,
    );

    expect(completedRounds, 0);
  });

  test("the 4's stem starts at the apex, not in mid-air", () {
    // The stem used to begin at y=0.30, a seventh of the box below where the
    // diagonal starts, so the guide drew as a tick floating beside the
    // diagonal instead of the spine of a 4. Points are normalised 0..1.
    final four = TraceGlyphs.level3.firstWhere((g) => g.label == '4');
    final diagonal = four.strokes[0];
    final stem = four.strokes[1];

    expect(
      _distanceToPolyline(stem.first, diagonal),
      lessThan(0.05),
      reason: "the stem's top must meet the diagonal it descends from",
    );
  });
}

/// Shortest distance from [point] to any part of [polyline].
double _distanceToPolyline(Offset point, List<Offset> polyline) {
  var best = double.infinity;
  for (var i = 0; i < polyline.length - 1; i++) {
    final d = _distanceToSegment(point, polyline[i], polyline[i + 1]);
    if (d < best) best = d;
  }
  return best;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (p - a).distance;
  final t =
      (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}
