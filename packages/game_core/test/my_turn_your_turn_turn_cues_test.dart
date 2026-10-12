import 'dart:async';
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/src/analytics/models/game_session_metrics.dart';
import 'package:game_core/src/config/difficulty_profile.dart';
import 'package:game_core/src/games/my_turn_your_turn/my_turn_your_turn_game.dart';
import 'package:game_core/src/games/my_turn_your_turn/components/turn_slot.dart';
import 'package:game_core/src/games/my_turn_your_turn/components/turn_tray.dart';

/// Practice-mode turn cues for My Turn, Your Turn (AUM-365).
///
/// Testers found the buddy's wait had "no objective". The wait itself is the
/// skill — the assessment counts early taps during it — so the cues that make
/// it readable (whose turn it is, a visual timer, a goal card before the first
/// round) must appear in practice only, and assessment must look and time
/// exactly as it did before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void advance(FlameGame game, double seconds) {
    const step = 1 / 60;
    for (var elapsed = 0.0; elapsed < seconds; elapsed += step) {
      game.update(step);
    }
  }

  int buddyFilled(FlameGame game) =>
      game.children
          .whereType<TurnSlot>()
          .where((s) => s.isFilled && s.isBuddy)
          .length;

  List<TurnTray> trays(FlameGame game) =>
      game.children.whereType<TurnTray>().toList()
        ..sort((a, b) => a.position.x.compareTo(b.position.x));

  /// The buddy's tray sits on the left, the child's on the right.
  TurnTray buddyTray(FlameGame game) => trays(game).first;
  TurnTray childTray(FlameGame game) => trays(game).last;

  Future<MyTurnYourTurnGame> loadGame({
    required DifficultyProfile profile,
    Future<void> Function(String buddyEmoji)? onShowGoal,
    void Function(bool isBuddyTurn)? onTurnChanged,
  }) async {
    final game = MyTurnYourTurnGame(
      totalRounds: 3,
      childId: 'test-child',
      avatar: '🐼',
      profile: profile,
      onStepChanged: (_) {},
      onTurnChanged: onTurnChanged ?? (_) {},
      onShowGoal: onShowGoal,
      onGameComplete: ({
        required int score,
        required int totalItems,
        required int errorCount,
        required int totalResponseTimeMs,
        required Map<String, dynamic> extras,
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

  group('assessment stays exactly as it was', () {
    test('no trays, no timer and no goal card', () async {
      var goalShown = false;
      final game = await loadGame(
        profile: DifficultyProfile.assessment,
        onShowGoal: (_) async => goalShown = true,
      );
      advance(game, 2.0);
      expect(trays(game), isEmpty, reason: 'assessment must draw no cues');
      expect(goalShown, isFalse, reason: 'assessment never shows the goal');
    });

    test('the buddy still moves on the fixed ~5s wait', () async {
      final game = await loadGame(
        profile: DifficultyProfile.assessment,
        // Even if a screen passes one, assessment must not wait on it.
        onShowGoal: (_) => Completer<void>().future,
      );
      advance(game, 4.5);
      expect(buddyFilled(game), 0);
      advance(game, 1.1);
      expect(buddyFilled(game), 1);
    });
  });

  group('whose turn it is', () {
    test('the buddy side lights up on its turn, the child side on theirs',
        () async {
      var turnIsBuddy = true;
      final game = await loadGame(
        profile: DifficultyProfile.medium,
        onTurnChanged: (isBuddy) => turnIsBuddy = isBuddy,
      );
      expect(trays(game), hasLength(2));
      expect(buddyTray(game).active, isTrue);
      expect(childTray(game).active, isFalse);

      advance(game, 5.6); // Medium wait + glide
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(turnIsBuddy, isFalse);
      expect(buddyTray(game).active, isFalse);
      expect(childTray(game).active, isTrue);
      expect(childTray(game).progress, isNull,
          reason: 'the child\'s own turn is never timed');
    });

    test('Hard still shows whose turn it is', () async {
      final game = await loadGame(profile: DifficultyProfile.hard);
      expect(buddyTray(game).active, isTrue);
    });
  });

  group('visual wait timer', () {
    test('fills with the buddy\'s wait on Medium', () async {
      final game = await loadGame(profile: DifficultyProfile.medium);
      expect(childTray(game).progress, closeTo(0, 0.02));
      advance(game, 2.5); // half of the 5s wait
      expect(childTray(game).progress, closeTo(0.5, 0.03));
      advance(game, 2.6); // wait over, buddy gliding
      expect(childTray(game).progress, 1.0,
          reason: 'the timer stays full until the child\'s turn begins');
    });

    test('fills on Easy too', () async {
      final game = await loadGame(profile: DifficultyProfile.easy);
      advance(game, 3.0); // half of the 6s wait
      expect(childTray(game).progress, closeTo(0.5, 0.03));
    });

    test('Hard fades the timer out', () async {
      final game = await loadGame(profile: DifficultyProfile.hard);
      advance(game, 2.0);
      expect(childTray(game).progress, isNull);
    });

    test('a round stepped down from Hard gets the timer back', () async {
      final game = await loadGame(profile: DifficultyProfile.hard);
      advance(game, 0.5);
      expect(childTray(game).progress, isNull);
      // Two early taps in a row step Hard down to Medium for this round.
      final slots = game.children.whereType<TurnSlot>().toList();
      slots[0].onTappedWhileDisabled!(slots[0].slotIndex);
      slots[1].onTappedWhileDisabled!(slots[1].slotIndex);
      advance(game, 0.1);
      expect(childTray(game).progress, isNotNull);
    });

    test('an early tap stretches the timer with the wait', () async {
      final game = await loadGame(profile: DifficultyProfile.medium);
      advance(game, 2.5);
      final before = childTray(game).progress!;
      final slot = game.children.whereType<TurnSlot>().first;
      slot.onTappedWhileDisabled!(slot.slotIndex); // +2s grace
      advance(game, 1 / 60);
      // 2.5s of a now-7s wait: the timer steps back to match.
      expect(childTray(game).progress!, lessThan(before));
      expect(childTray(game).progress!, closeTo(2.5 / 7.0, 0.03));
    });
  });

  group('tray drawing', () {
    test('draws idle, active, empty, partial and full timer states', () {
      final tray = TurnTray(
        color: const Color(0xFF43A047),
        position: Vector2.zero(),
        size: Vector2(100, 320),
      );
      for (final state in <(bool, double?)>[
        (false, null),
        (true, null),
        (false, 0.0),
        (false, 0.4),
        (false, 1.0),
      ]) {
        tray
          ..active = state.$1
          ..progress = state.$2;
        tray.update(1); // finish any highlight fade
        final recorder = PictureRecorder();
        tray.render(Canvas(recorder));
        expect(recorder.endRecording(), isNotNull);
      }
    });
  });

  group('goal card before the first round', () {
    test('the buddy waits for the goal card, then plays as usual', () async {
      final goal = Completer<void>();
      String? shownBuddy;
      final game = await loadGame(
        profile: DifficultyProfile.medium,
        onShowGoal: (buddyEmoji) {
          shownBuddy = buddyEmoji;
          return goal.future;
        },
      );

      expect(shownBuddy, game.buddyEmoji,
          reason: 'the card shows the buddy the child will play with');
      expect(shownBuddy, isNot('🐼'),
          reason: 'the buddy never looks like the child\'s avatar');
      expect(game.children.whereType<TurnSlot>(), hasLength(6),
          reason: 'the board is laid out under the card');

      advance(game, 8.0);
      expect(buddyFilled(game), 0, reason: 'the buddy moved under the card');

      goal.complete();
      await Future<void>.delayed(Duration.zero);
      advance(game, 4.5);
      expect(buddyFilled(game), 0);
      advance(game, 1.1);
      expect(buddyFilled(game), 1,
          reason: 'the first turn keeps its normal wait after the card');
    });

    test('a goal card that fails still lets the game start', () async {
      final game = await loadGame(
        profile: DifficultyProfile.medium,
        onShowGoal: (_) => Future<void>.error(StateError('no card')),
      );
      await Future<void>.delayed(Duration.zero);
      advance(game, 5.6);
      expect(buddyFilled(game), 1);
    });
  });
}
