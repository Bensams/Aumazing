import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

/// How long the finished Copy Me demo pattern stays on screen before it is
/// cleared and the child's turn begins.
///
/// The SPED teacher's audit found the pattern vanished before a child on the
/// Easy tier had finished encoding it, so Easy/practice now holds the completed
/// pattern for a full three seconds. Medium, Hard and assessment keep the
/// original brief hold - the shorter look is part of what those tiers measure,
/// and assessment timing must stay comparable across children.
///
/// The demo runs on wall-clock `Future.delayed`, so these tests observe the real
/// timeline rather than a simulated one. Nothing is measured from load: the game
/// waits out its instruction voice-over first, so every probe is anchored on the
/// pattern actually appearing and timed from there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CopyMeGame> loadGame({
    required DifficultyProfile profile,
    void Function()? onCorrectMatch,
    void Function()? onPlayYourTurnVo,
  }) async {
    final game = CopyMeGame(
      totalRounds: 3,
      childId: 'test-child',
      profile: profile,
      // A cue that reports completion at once: the demo awaits it instead of
      // falling back to its 2s allowance for the longest recording.
      onPlayMyTurnVo: () => Future<void>.value(),
      onPlayYourTurnVo: onPlayYourTurnVo,
      onCorrectMatch: onCorrectMatch,
      onStepChanged: (_) {},
      onGameComplete:
          ({
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

  /// True while the demo pattern is on screen (round 1 shows a single shape).
  bool patternShowing(FlameGame g) => slots(g).any((s) => s.isFilled);
  bool inputOpen(FlameGame g) => palette(g).every((s) => s.inputEnabled);

  const poll = Duration(milliseconds: 20);
  const patience = Duration(seconds: 12);

  /// Polls until [condition] holds, returning the stopwatch reading at that
  /// point. Fails the test rather than hanging if it never does.
  Future<Duration> waitFor(
    Stopwatch clock,
    bool Function() condition,
    String describe,
  ) async {
    while (clock.elapsed < patience) {
      if (condition()) return clock.elapsed;
      await Future<void>.delayed(poll);
    }
    fail('timed out waiting for $describe');
  }

  /// Loads a game and measures how long the demo pattern stayed visible: from
  /// the moment it appears to the moment the slots are cleared.
  Future<Duration> measureVisibleFor(DifficultyProfile profile) async {
    final game = await loadGame(profile: profile);
    final clock = Stopwatch()..start();
    final shownAt = await waitFor(
      clock,
      () => patternShowing(game),
      'the demo to show the pattern (${profile.label})',
    );
    final clearedAt = await waitFor(
      clock,
      () => !patternShowing(game),
      'the pattern to be cleared (${profile.label})',
    );
    return clearedAt - shownAt;
  }

  group('Easy/practice holds the completed pattern for three seconds', () {
    test('the pattern stays visible for at least three seconds', () async {
      final visible = await measureVisibleFor(DifficultyProfile.easy);

      // The requirement is "3 seconds or longer", so this is a floor, not a
      // window. Polling can only ever report the span as slightly short, so the
      // tolerance is subtracted rather than added.
      expect(
        visible.inMilliseconds,
        greaterThanOrEqualTo(2950),
        reason: 'Easy cleared the pattern before three seconds had passed',
      );
    });

    test('the pattern is still up midway through the hold', () async {
      final game = await loadGame(profile: DifficultyProfile.easy);
      final clock = Stopwatch()..start();
      await waitFor(clock, () => patternShowing(game), 'the pattern to show');

      // 1.5s after it appeared, an Easy child is still looking at it.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(
        patternShowing(game),
        isTrue,
        reason: 'the pattern vanished midway through the Easy hold',
      );
    });
  });

  group('input stays closed for the whole hold', () {
    test('taps and drags are refused while the pattern is held', () async {
      var correctMatches = 0;
      final game = await loadGame(
        profile: DifficultyProfile.easy,
        onCorrectMatch: () => correctMatches++,
      );
      final clock = Stopwatch()..start();
      await waitFor(clock, () => patternShowing(game), 'the pattern to show');

      // Midway through the hold, with the pattern still up.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(patternShowing(game), isTrue);
      expect(
        inputOpen(game),
        isFalse,
        reason: 'the palette accepted input during the hold',
      );

      // The game-level guard refuses even a direct tap or drop, so a stray
      // pointer during the hold can neither score nor fill a slot.
      final cards = palette(game);
      for (final card in cards) {
        card.onTapped(card.index);
      }
      cards.first.onDragDropped?.call(
        cards.first.index,
        slots(game).first.absoluteCenter,
      );

      expect(
        correctMatches,
        0,
        reason: 'a tap during the hold was scored as a correct answer',
      );
    });
  });

  group('the pattern is gone before the child is asked to copy it', () {
    test('the your-turn cue only plays once every slot is empty', () async {
      var yourTurnCalls = 0;
      var patternUpAtCue = true;
      late CopyMeGame game;
      game = await loadGame(
        profile: DifficultyProfile.easy,
        onPlayYourTurnVo: () {
          yourTurnCalls++;
          patternUpAtCue = patternShowing(game);
        },
      );

      final clock = Stopwatch()..start();
      await waitFor(clock, () => yourTurnCalls > 0, 'the child turn to open');

      expect(yourTurnCalls, 1);
      expect(
        patternUpAtCue,
        isFalse,
        reason: 'the demo pattern was still on screen at the your-turn cue',
      );
      await waitFor(clock, () => inputOpen(game), 'input to be enabled');
    });
  });

  group('Medium, Hard and assessment keep the original brief hold', () {
    /// Each non-Easy tier must show the pattern and clear it again well inside
    /// the three seconds Easy now holds for. Measuring the visible span (rather
    /// than probing a fixed offset) means an unshown pattern cannot pass this.
    Future<void> expectsBriefHold(DifficultyProfile profile) async {
      final visible = await measureVisibleFor(profile);
      expect(
        visible.inMilliseconds,
        lessThan(2000),
        reason: '${profile.label} held the pattern longer than it used to',
      );
    }

    test('Medium is unchanged', () async {
      await expectsBriefHold(DifficultyProfile.medium);
    });

    test('Hard is unchanged', () async {
      await expectsBriefHold(DifficultyProfile.hard);
    });

    test('assessment is unchanged', () async {
      // Assessment reports level 2 but must never pick up a practice-tier
      // change, so it is pinned separately from Medium.
      await expectsBriefHold(DifficultyProfile.assessment);
    });

    test('Easy holds strictly longer than Medium', () async {
      final easy = await measureVisibleFor(DifficultyProfile.easy);
      final medium = await measureVisibleFor(DifficultyProfile.medium);
      expect(easy.inMilliseconds, greaterThan(medium.inMilliseconds + 1500));
    });
  });
}
