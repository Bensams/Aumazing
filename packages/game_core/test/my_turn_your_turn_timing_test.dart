import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/src/analytics/models/game_session_metrics.dart';
import 'package:game_core/src/config/difficulty_profile.dart';
import 'package:game_core/src/games/my_turn_your_turn/my_turn_your_turn_game.dart';
import 'package:game_core/src/games/my_turn_your_turn/components/turn_slot.dart';

/// Buddy-turn wait timing for My Turn, Your Turn.
///
/// The waiting interval is the whole point of the game — it is where the child
/// practises patience — so these tests pin the behaviour the audit asked for:
/// every difficulty gives a predictable, slower wait (Easy 6s > Medium 5s >
/// Hard 4s), assessment uses a single fixed 5s wait that never adapts, an early
/// tap in practice buys a little extra settling time (bounded, and never in
/// assessment), the wait pauses when the engine stops ticking, the buddy never
/// moves in the middle of its "please wait" cue, and a child who answers late
/// is still accepted rather than auto-failed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Runs [seconds] of game time in engine-sized steps.
  void advance(FlameGame game, double seconds) {
    const step = 1 / 60;
    for (var elapsed = 0.0; elapsed < seconds; elapsed += step) {
      game.update(step);
    }
  }

  /// Slots the buddy has filled so far (its move has landed).
  int buddyFilled(FlameGame game) =>
      game.children
          .whereType<TurnSlot>()
          .where((s) => s.isFilled && s.isBuddy)
          .length;

  /// Slots the child has filled so far.
  int childFilled(FlameGame game) =>
      game.children
          .whereType<TurnSlot>()
          .where((s) => s.isFilled && !s.isBuddy)
          .length;

  Future<MyTurnYourTurnGame> loadGame({
    required DifficultyProfile profile,
    FutureOr<void> Function()? onPlayWaitVo,
    void Function(bool isBuddyTurn)? onTurnChanged,
    void Function()? onCorrectMatch,
    void Function()? onGameCompleteFlag,
  }) async {
    final game = MyTurnYourTurnGame(
      totalRounds: 3,
      childId: 'test-child',
      profile: profile,
      onStepChanged: (_) {},
      onTurnChanged: onTurnChanged ?? (_) {},
      onCorrectMatch: onCorrectMatch,
      onPlayWaitVo: onPlayWaitVo,
      onGameComplete: ({
        required int score,
        required int totalItems,
        required int errorCount,
        required int totalResponseTimeMs,
        required Map<String, dynamic> extras,
        GameSessionMetrics? analytics,
      }) {
        onGameCompleteFlag?.call();
      },
    );
    game.onGameResize(Vector2(1280, 800));
    // mount() makes the root live so effects (the buddy's glide) update; this
    // is Flame's own hook for the harness, mirrored from match_it's tests.
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.onLoad();
    await game.ready();
    return game;
  }

  group('predictable difficulty-based buddy wait', () {
    /// (before-wait seconds, after-wait seconds) probe points around a tier's
    /// wait: nothing is placed just before it elapses, exactly one buddy piece
    /// just after (the wait plus the ~0.35s glide, with slack).
    Future<void> expectsWait(
      DifficultyProfile profile, {
      required double before,
      required double after,
    }) async {
      final game = await loadGame(profile: profile);
      advance(game, before);
      expect(
        buddyFilled(game),
        0,
        reason: 'the buddy moved before its wait elapsed',
      );
      advance(game, after - before);
      expect(
        buddyFilled(game),
        1,
        reason: 'the buddy never moved after its wait elapsed',
      );
    }

    test('Easy waits ~6s', () async {
      await expectsWait(DifficultyProfile.easy, before: 5.5, after: 6.6);
    });

    test('Medium waits ~5s', () async {
      await expectsWait(DifficultyProfile.medium, before: 4.5, after: 5.6);
    });

    test('Hard waits ~4s', () async {
      await expectsWait(DifficultyProfile.hard, before: 3.5, after: 4.6);
    });

    test('easier tiers wait strictly longer than harder ones', () async {
      // At 4.6s the buddy has moved on Hard (4s) but not yet on Medium (5s)
      // or Easy (6s) — the ordering the audit asked for.
      final hard = await loadGame(profile: DifficultyProfile.hard);
      final medium = await loadGame(profile: DifficultyProfile.medium);
      final easy = await loadGame(profile: DifficultyProfile.easy);
      advance(hard, 4.6);
      advance(medium, 4.6);
      advance(easy, 4.6);
      expect(buddyFilled(hard), 1);
      expect(buddyFilled(medium), 0);
      expect(buddyFilled(easy), 0);
    });
  });

  group('assessment uses a fixed, non-adaptive wait', () {
    test('assessment waits ~5s regardless of difficulty knobs', () async {
      final game = await loadGame(profile: DifficultyProfile.assessment);
      advance(game, 4.5);
      expect(buddyFilled(game), 0);
      advance(game, 1.1);
      expect(buddyFilled(game), 1);
    });

    test('an early tap does NOT lengthen the assessment wait', () async {
      final game = await loadGame(profile: DifficultyProfile.assessment);
      advance(game, 1.0);
      // Tap a slot while it is the buddy's turn (input disabled) — an early tap.
      final slot = game.children.whereType<TurnSlot>().first;
      slot.onTappedWhileDisabled!(slot.slotIndex);
      // Still the fixed 5s: placed by ~5.6s, unchanged by the early tap.
      advance(game, 4.6); // total ~5.6s
      expect(
        buddyFilled(game),
        1,
        reason: 'assessment timing must stay comparable across children',
      );
    });
  });

  group('early-tap grace (practice only, bounded)', () {
    test('an early tap adds ~2s to the in-flight practice wait', () async {
      final game = await loadGame(profile: DifficultyProfile.medium);
      advance(game, 1.0);
      final slot = game.children.whereType<TurnSlot>().first;
      slot.onTappedWhileDisabled!(slot.slotIndex); // +2s for this round

      // Without the grace, Medium would place by ~5.6s. With +2s it must not
      // have moved yet at 5.6s...
      advance(game, 4.6); // total ~5.6s
      expect(
        buddyFilled(game),
        0,
        reason: 'the early-tap grace did not extend the current wait',
      );
      // ...and must place by ~7.6s (5s + 2s + glide).
      advance(game, 2.0); // total ~7.6s
      expect(buddyFilled(game), 1);
    });

    test('the grace is bounded — a second early tap adds nothing', () async {
      final game = await loadGame(profile: DifficultyProfile.medium);
      advance(game, 0.5);
      final slots = game.children.whereType<TurnSlot>().toList();
      slots[0].onTappedWhileDisabled!(slots[0].slotIndex);
      slots[1].onTappedWhileDisabled!(slots[1].slotIndex);
      // Two taps still means a single +2s grace: placed by ~7.6s, not later.
      advance(game, 7.6);
      expect(
        buddyFilled(game),
        1,
        reason: 'the grace stacked past its single bounded extension',
      );
    });
  });

  group('the wait pauses when the engine stops ticking', () {
    test('no game-time passes while the game is not updated', () async {
      final game = await loadGame(profile: DifficultyProfile.medium);
      advance(game, 3.0);
      expect(buddyFilled(game), 0);

      // A pause is simply the absence of update ticks: no matter how much wall
      // time passes here, the buddy must not move.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        buddyFilled(game),
        0,
        reason: 'the wait advanced while the engine was not ticking',
      );

      // Resume: the remaining ~2s of the 5s wait (plus glide) elapses.
      advance(game, 2.6);
      expect(buddyFilled(game), 1);
    });
  });

  group('the buddy never moves in the middle of its cue', () {
    test('the wait only starts once the wait cue reports completion', () async {
      final cue = Completer<void>();
      final game = await loadGame(
        profile: DifficultyProfile.hard, // shortest wait: 4s
        onPlayWaitVo: () => cue.future,
      );

      // Cue still playing: no countdown, so even well past 4s nothing moves.
      advance(game, 6.0);
      expect(
        buddyFilled(game),
        0,
        reason: 'the buddy moved while its wait cue was still playing',
      );

      // Cue finishes — the async resume that starts the countdown runs on the
      // microtask queue, so flush it before ticking the engine.
      cue.complete();
      await Future<void>.delayed(Duration.zero);

      advance(game, 4.6);
      expect(
        buddyFilled(game),
        1,
        reason: 'the wait did not start after the cue completed',
      );
    });
  });

  group('a late child answer is still accepted', () {
    test('no auto-failure on idle, and a late tap still scores', () async {
      var turnIsBuddy = true;
      var correctMatches = 0;
      var completed = false;
      final game = await loadGame(
        profile: DifficultyProfile.medium,
        onTurnChanged: (isBuddy) => turnIsBuddy = isBuddy,
        onCorrectMatch: () => correctMatches++,
        onGameCompleteFlag: () => completed = true,
      );

      // Play out the buddy's turn and land on the child's turn. The game
      // advances Flame time synchronously, while the existing inter-turn
      // handoff uses a short wall-clock delay.
      advance(game, 6.0);
      expect(buddyFilled(game), 1);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(turnIsBuddy, isFalse, reason: 'it should be the child\'s turn');

      // The child dawdles well past any old short interval...
      advance(game, 8.0);
      expect(completed, isFalse, reason: 'idling must not fail the game');
      expect(childFilled(game), 0, reason: 'nothing was placed for the child');

      // ...then finally answers. The late tap is accepted and scores.
      final target = game.children.whereType<TurnSlot>().firstWhere(
        (s) => !s.isFilled && s.inputEnabled,
      );
      target.onTapped(target.slotIndex);
      advance(game, 0.6); // let the piece glide in and fill

      expect(childFilled(game), 1, reason: 'the late valid tap was refused');
      expect(correctMatches, 1);
      expect(completed, isFalse);
    });
  });
}
