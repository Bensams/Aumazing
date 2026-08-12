import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/src/config/difficulty_profile.dart';
import 'package:game_core/src/games/kumusta/buddy_art_cache.dart';
import 'package:game_core/src/games/kumusta/components/greeting_button.dart';
import 'package:game_core/src/games/kumusta/greetings.dart';
import 'package:game_core/src/games/kumusta/kumusta_game.dart';

/// Kumusta! — the greeting the buddy offers must be the one the child can
/// answer, and a wrong answer must cost the child nothing but a second look.
///
/// Both are failures a passing score hides. If the offered gesture were ever
/// missing from the card row the round would be unanswerable, and the child
/// would sit through the whole prompt ladder for a card that is not there. And
/// if a wrong tap ended the round, the game would be scoring recognition speed
/// rather than the social exchange it claims to teach.
///
/// Driven through a real [GameWidget] rather than by calling handlers: a bare
/// `FlameGame` is never mounted, so its timers and effects never run and
/// `localPosition` has no component path to resolve against.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Warmed here so the game's own await inside onLoad resolves on a
    // microtask; decoding sprite sheets mid-pump does not.
    await KumustaBuddyArt.load('bps');
  });

  /// Boots a game and returns it plus a sink that records each greeting the
  /// buddy offers — the only public view of the round's target.
  Future<(KumustaGame, List<Greeting>, List<Map<String, dynamic>>)> boot(
    WidgetTester tester, {
    DifficultyProfile profile = DifficultyProfile.easy,
    int totalRounds = 4,
    VoidCallback? onWrong,
  }) async {
    final offered = <Greeting>[];
    final completions = <Map<String, dynamic>>[];
    final game = KumustaGame(
      totalRounds: totalRounds,
      childId: 'test-child',
      profile: profile,
      onStepChanged: (_) {},
      onBuddyGreets: offered.add,
      onWrongAnswer: onWrong,
      onGameComplete: ({
        required score,
        required totalItems,
        required errorCount,
        required totalResponseTimeMs,
        required extras,
        analytics,
      }) {
        completions.add({
          'score': score,
          'totalItems': totalItems,
          'errorCount': errorCount,
          'extras': extras,
        });
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GameWidget(game: game))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    return (game, offered, completions);
  }

  List<GreetingButton> cardsOf(KumustaGame g) =>
      g.children.whereType<GreetingButton>().toList();

  Offset centreOf(GreetingButton b) => Offset(b.centre.x, b.centre.y);

  /// Waits out the buddy's walk-in so the offer has played, without reaching
  /// the first prompt (which would count the round as prompted).
  Future<void> untilOffered(WidgetTester tester, List<Greeting> offered) async {
    for (var i = 0; i < 40 && offered.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the offered greeting is always on the card row', (tester) async {
    final (game, offered, _) = await boot(tester);
    await untilOffered(tester, offered);

    expect(offered, isNotEmpty, reason: 'the buddy must open with a greeting');
    expect(
      cardsOf(game).map((c) => c.greeting),
      contains(offered.last),
      reason: 'an offer with no matching card is an unanswerable round — the '
          'child would sit through every prompt for a card that is not there',
    );
  });

  testWidgets('a wrong tap keeps the round open and re-offers', (tester) async {
    var wrongs = 0;
    final (game, offered, completions) =
        await boot(tester, onWrong: () => wrongs++);
    await untilOffered(tester, offered);

    final target = offered.last;
    final wrongCard =
        cardsOf(game).where((c) => c.greeting != target).firstOrNull;
    // The Easy tier shows two cards, so a wrong one always exists.
    expect(wrongCard, isNotNull);

    await tester.tapAt(centreOf(wrongCard!));
    await tester.pump(const Duration(milliseconds: 300));

    expect(wrongs, 1);
    expect(completions, isEmpty, reason: 'a wrong greeting must not end play');

    // The same greeting is still answerable: tapping the right card now works.
    final rightCard = cardsOf(game).firstWhere((c) => c.greeting == target);
    await tester.tapAt(centreOf(rightCard));
    await tester.pump(const Duration(milliseconds: 300));

    // Round advances (buddy leaves, next round starts) rather than stalling.
    for (var i = 0; i < 40 && offered.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(offered.length, greaterThanOrEqualTo(2),
        reason: 'the round must resolve after a corrected answer');
  });

  testWidgets('answering every round finishes the session unprompted',
      (tester) async {
    final (game, offered, completions) = await boot(tester, totalRounds: 2);

    for (var round = 0; round < 2; round++) {
      final seen = offered.length;
      for (var i = 0; i < 40 && offered.length == seen; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final target = offered.last;
      final card = cardsOf(game).firstWhere((c) => c.greeting == target);
      await tester.tapAt(centreOf(card));
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (var i = 0; i < 60 && completions.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(completions, hasLength(1));
    final result = completions.single;
    expect(result['score'], 2);
    expect(result['totalItems'], 2,
        reason: 'one scored answer per round, so tiers stay comparable');
    expect(result['errorCount'], 0);
    expect((result['extras'] as Map)['unprompted_greetings'], 2,
        reason: 'greeting back without a prompt is the target skill and the '
            'number a clinician reads first');
  });
}
