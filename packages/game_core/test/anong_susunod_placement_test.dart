import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/src/config/difficulty_profile.dart';
import 'package:game_core/src/games/anong_susunod/anong_susunod_game.dart';
import 'package:game_core/src/games/anong_susunod/components/routine_card.dart';
import 'package:game_core/src/games/anong_susunod/components/sequence_slot.dart';
import 'package:game_core/src/games/anong_susunod/routine_art_cache.dart';
import 'package:game_core/src/games/anong_susunod/routine_steps.dart';

/// Ano'ng Susunod? after distractor cards and drag-to-place.
///
/// Both cover failures a *passing* session hides. A tray holding exactly as
/// many cards as there are gaps reports a flawless score from a child who
/// understood nothing — on the Easy tier, one gap and one card, there was no
/// wrong move available to make. And a drag that resolves differently from a
/// tap would mean the numbers a clinician reads depend on which gesture the
/// child happened to reach for.
///
/// Driven through a real [GameWidget] rather than by calling the handlers
/// directly: a bare `FlameGame` in a test is never mounted, so its effects
/// never start and constructed events carry no component path for
/// `localPosition` to resolve against. Pumping real pointers exercises the
/// gesture arena the child actually meets.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Warmed here so the game's own await inside onLoad resolves on a
    // microtask; decoding fourteen PNGs mid-pump does not.
    await RoutineArtCache.ensureLoaded();
  });

  Future<AnongSusunodGame> boot(
    WidgetTester tester,
    DifficultyProfile profile,
  ) async {
    final game = AnongSusunodGame(
      onStepChanged: (_) {},
      onGameComplete: ({
        required score,
        required totalItems,
        required errorCount,
        required totalResponseTimeMs,
        required extras,
        analytics,
      }) {},
      childId: 'test-child',
      profile: profile,
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GameWidget(game: game))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    return game;
  }

  /// Cards still available to the child.
  List<RoutineCard> trayOf(AnongSusunodGame g) =>
      g.children.whereType<RoutineCard>().where((c) => !c.placed).toList();

  List<SequenceSlot> slotsOf(AnongSusunodGame g) =>
      g.children.whereType<SequenceSlot>().toList();

  Offset centreOf(dynamic component) =>
      Offset(component.position.x as double, component.position.y as double);

  /// A complete drag: down, across in small steps, release.
  ///
  /// Stepped like a real finger rather than teleported, because Flame reports a
  /// drag's end as `globalPosition + delta` — one delta ahead of where the
  /// pointer actually is. At 60 Hz that overshoot is a couple of pixels and
  /// invisible; a single giant `moveTo` turns it into half the screen and the
  /// card sails past the slot it was aimed at.
  Future<void> dragCard(
    WidgetTester tester, {
    required Offset from,
    required Offset to,
  }) async {
    const steps = 16;
    final gesture = await tester.startGesture(from);
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Let the fingertip glide settle so the card is under the pointer before
    // release — the drop is hit-tested from the card's centre.
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 32));
  }

  group('distractor cards', () {
    for (final profile in [
      DifficultyProfile.easy,
      DifficultyProfile.medium,
      DifficultyProfile.hard,
    ]) {
      testWidgets('${profile.label}: the tray offers more cards than gaps',
          (tester) async {
        final game = await boot(tester, profile);
        final gaps = slotsOf(game).where((s) => s.filled == null).length;

        expect(gaps, greaterThan(0));
        expect(trayOf(game).length, greaterThan(gaps),
            reason: 'with one card per gap the last placement is forced, and '
                'on Easy — one gap, one card — the child cannot be wrong at '
                'all, so the session reports a perfect score no matter what '
                'they understood');
      });

      testWidgets('${profile.label}: a distractor belongs to no slot this round',
          (tester) async {
        final game = await boot(tester, profile);
        // Round one always draws the first routine.
        final belongs = kRoutines.first.steps.map((s) => s.id).toSet();
        final offered = trayOf(game).map((c) => c.step.id).toSet();

        expect(offered.difference(belongs), isNotEmpty,
            reason: 'no distractor was dealt at all');
        // `brush` is in both Umaga and Gabi, `wash` in both Kainan and Laro.
        // A foil chosen by identity rather than by step id would hand back a
        // card that IS part of this routine, leaving a step unplaceable.
        expect(offered.intersection(belongs).length,
            lessThanOrEqualTo(belongs.length));
      });
    }

    testWidgets('a distractor is rejected rather than seated', (tester) async {
      final game = await boot(tester, DifficultyProfile.medium);
      final belongs = kRoutines.first.steps.map((s) => s.id).toSet();
      final foil = trayOf(game).firstWhere((c) => !belongs.contains(c.step.id));
      final gap = slotsOf(game).firstWhere((s) => s.filled == null);

      await dragCard(tester, from: centreOf(foil), to: centreOf(gap));

      expect(gap.filled, isNull, reason: 'a foil must never seat on Medium');
      expect(foil.placed, isFalse);
    });
  });

  group('drag places a card, exactly as a tap does', () {
    testWidgets('dragging the right card onto its slot seats it',
        (tester) async {
      final game = await boot(tester, DifficultyProfile.medium);
      final gap = slotsOf(game).firstWhere((s) => s.filled == null);
      final wanted = kRoutines.first.steps[gap.index].id;
      final card = trayOf(game).firstWhere((c) => c.step.id == wanted);

      await dragCard(tester, from: centreOf(card), to: centreOf(gap));

      expect(gap.filled?.id, wanted);
      expect(card.placed, isTrue);
      expect(trayOf(game).any((c) => c.step.id == wanted), isFalse,
          reason: 'the same step showing in the tray and in its slot at once '
              'is the ambiguity a visual schedule exists to remove');
    });

    testWidgets('tapping the right card then its slot seats it too',
        (tester) async {
      final game = await boot(tester, DifficultyProfile.medium);
      final gap = slotsOf(game).firstWhere((s) => s.filled == null);
      final wanted = kRoutines.first.steps[gap.index].id;
      final card = trayOf(game).firstWhere((c) => c.step.id == wanted);

      // Pumped past the tap recognizer's own countdown so no timer outlives
      // the widget tree.
      await tester.tapAt(centreOf(card));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tapAt(centreOf(gap));
      await tester.pump(const Duration(milliseconds: 200));

      expect(gap.filled?.id, wanted,
          reason: 'the tap path must still place a card — it is what a child '
              'with motor-planning differences can complete');
    });

    testWidgets('a wrong card dragged onto a slot comes back to the tray',
        (tester) async {
      final game = await boot(tester, DifficultyProfile.medium);
      final gap = slotsOf(game).firstWhere((s) => s.filled == null);
      final wanted = kRoutines.first.steps[gap.index].id;
      final card = trayOf(game).firstWhere((c) => c.step.id != wanted);
      final home = card.homePosition.clone();

      await dragCard(tester, from: centreOf(card), to: centreOf(gap));
      await tester.pump(const Duration(milliseconds: 400));

      expect(gap.filled, isNull);
      expect(card.placed, isFalse);
      expect((card.position - home).length, lessThan(1.0),
          reason: 'a rejected card must return to the tray, not sit on top of '
              'the slot it bounced off');
    });

    testWidgets('a card released over open canvas returns home unscored',
        (tester) async {
      final game = await boot(tester, DifficultyProfile.medium);
      final card = trayOf(game).first;
      final home = card.homePosition.clone();

      await dragCard(tester, from: centreOf(card), to: const Offset(24, 560));
      await tester.pump(const Duration(milliseconds: 400));

      expect(card.placed, isFalse);
      expect((card.position - home).length, lessThan(1.0));
    });

    testWidgets('a tap that wobbles leaves the card exactly where it was',
        (tester) async {
      final game = await boot(tester, DifficultyProfile.medium);
      final card = trayOf(game).first;
      final home = card.homePosition.clone();

      // Under the drag threshold the whole way — a tremor, not a drag.
      final gesture = await tester.startGesture(centreOf(card));
      await gesture.moveBy(const Offset(5, 4));
      await tester.pump(const Duration(milliseconds: 32));
      await gesture.moveBy(const Offset(-4, 3));
      await tester.pump(const Duration(milliseconds: 32));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(card.placed, isFalse);
      expect((card.position - home).length, lessThan(1.0));
    });
  });
}
