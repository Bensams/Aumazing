import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_ui/shared_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Wraps a bare [StarReward] in a full-screen media context and (optionally)
  /// a [RewardSfxProvider] capturing pop calls. [appearDelay] is zero so the
  /// stars are ready immediately in tests.
  Widget host({
    required bool reducedMotion,
    double effectScale = 1.0,
    VoidCallback? onStarPop,
    VoidCallback? onAllPopped,
    bool withProvider = true,
  }) {
    final star = StarReward(
      reducedMotion: reducedMotion,
      effectScale: effectScale,
      appearDelay: Duration.zero,
      onAllPopped: onAllPopped,
    );
    final body = SizedBox.expand(
      child: Stack(fit: StackFit.expand, children: [star]),
    );
    return MaterialApp(
      home: Scaffold(
        body: withProvider
            ? RewardSfxProvider(onStarPop: onStarPop, child: body)
            : body,
      ),
    );
  }

  /// Every rendered star draws exactly one [CustomPaint]; a popped star's
  /// burst/fade also draws one, so this counts live stars (and, after a pop,
  /// the replacement effect).
  Finder starPaints() => find.descendant(
    of: find.byType(StarReward),
    matching: find.byType(CustomPaint),
  );

  /// Stars still on the stage: under full motion a popped star swaps its
  /// [_StarPainter] for the burst's own painter, so this counts only the ones
  /// left to collect.
  Finder liveStars() => find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString() == '_StarPainter',
  );

  Finder effectNamed(String name) =>
      find.byWidgetPredicate((widget) => widget.runtimeType.toString() == name);

  /// Pumps until every star has spawned *and* finished rising into view.
  ///
  /// [appearDelay] is zero and stars spawn at `i * 60ms`, so the last of 20
  /// fires at 1140ms; each then rises for [kStarRiseDuration]. A star still
  /// below the bottom edge is off screen and cannot be tapped, so tests wait
  /// out the whole entrance.
  Future<void> settleSpawns(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(kStarRiseDuration);
  }

  group('rendering', () {
    testWidgets('renders one hand-drawn star per slot at full quality', (
      tester,
    ) async {
      await tester.pumpWidget(host(reducedMotion: false));
      await settleSpawns(tester);

      expect(find.byType(StarReward), findsOneWidget);
      expect(
        starPaints(),
        findsNWidgets(20),
        reason: 'base 20 stars at effectScale 1.0',
      );
    });

    testWidgets('scales the count to low quality (0.4 -> 8)', (tester) async {
      await tester.pumpWidget(host(reducedMotion: false, effectScale: 0.4));
      await settleSpawns(tester);
      expect(
        starPaints(),
        findsNWidgets(8),
        reason: '20 * 0.4 = 8 stars on the low tier',
      );
    });

    testWidgets('scales the count to medium quality (0.7 -> 14)', (
      tester,
    ) async {
      await tester.pumpWidget(host(reducedMotion: false, effectScale: 0.7));
      await settleSpawns(tester);
      expect(
        starPaints(),
        findsNWidgets(14),
        reason: '20 * 0.7 = 14 stars on the medium tier',
      );
    });
  });

  group('entrance', () {
    testWidgets('stars rise in from below the bottom edge, never appear in place',
        (tester) async {
      await tester.pumpWidget(host(reducedMotion: false, effectScale: 0.4));
      // The first star has spawned but has barely begun its climb.
      await tester.pump(const Duration(milliseconds: 16));

      final screen = tester.getSize(find.byType(StarReward));
      final entering = tester.getCenter(starPaints().first);
      expect(
        entering.dy,
        greaterThan(screen.height),
        reason: 'a star starts its life below the bottom edge, off screen',
      );

      // Part-way up: on screen, still travelling.
      await tester.pump(kStarRiseDuration ~/ 2);
      final midway = tester.getCenter(starPaints().first);
      expect(midway.dy, lessThan(entering.dy), reason: 'it is climbing');

      // Arrived: at rest in the upper half of the stage, well clear of where
      // it started.
      await tester.pump(kStarRiseDuration);
      final rested = tester.getCenter(starPaints().first);
      expect(rested.dy, lessThan(midway.dy));
      expect(rested.dy, lessThan(screen.height * 0.75));
    });

    testWidgets('reduced motion places stars at rest and fades them in',
        (tester) async {
      await tester.pumpWidget(host(reducedMotion: true, effectScale: 0.4));
      await tester.pump(const Duration(milliseconds: 16));

      final screen = tester.getSize(find.byType(StarReward));
      final atSpawn = tester.getCenter(starPaints().first);
      expect(
        atSpawn.dy,
        lessThan(screen.height),
        reason: 'no travel at all under reduced motion — already at rest',
      );

      await tester.pump(kStarRiseDuration);
      expect(tester.getCenter(starPaints().first), atSpawn,
          reason: 'only the opacity moved');
    });
  });

  group('interaction', () {
    testWidgets('tapping a star pops it: one SFX and a radial burst', (
      tester,
    ) async {
      var pops = 0;
      await tester.pumpWidget(
        host(reducedMotion: false, onStarPop: () => pops++),
      );
      await settleSpawns(tester);
      expect(pops, 0);

      // Stars land at random spots, so one tap can catch a couple of
      // overlapping ones. What must hold is that the SFX count matches the
      // stars that actually left the stage — no silent pops, no double plays.
      final before = liveStars().evaluate().length;
      await tester.tap(liveStars().first, warnIfMissed: false);
      await tester.pump();
      final cleared = before - liveStars().evaluate().length;

      expect(cleared, greaterThanOrEqualTo(1), reason: 'the tap popped a star');
      expect(pops, cleared, reason: 'each popped star plays the star-pop once');
      expect(
        effectNamed('RewardPopBurst'),
        findsNWidgets(cleared),
        reason: 'a radial sparkle burst each, not a fade, under full motion',
      );

      // Tapping the emptied spot again must not re-fire a pop.
      final emptiedSpot = tester.getCenter(starPaints().first);
      await tester.tapAt(emptiedSpot);
      await tester.pump();
      expect(pops, cleared, reason: 'a popped star cannot be popped again');
    });

    testWidgets('onAllPopped fires once, and only after the last star goes', (
      tester,
    ) async {
      var pops = 0;
      var allPopped = 0;
      // 20 * 0.4 = 8 stars — enough to prove "not until the last one".
      await tester.pumpWidget(
        host(
          reducedMotion: false,
          effectScale: 0.4,
          onStarPop: () => pops++,
          onAllPopped: () => allPopped++,
        ),
      );
      await settleSpawns(tester);
      expect(liveStars(), findsNWidgets(8));

      // Pop them one at a time, checking the signal stays silent until the
      // field is actually empty.
      var guard = 0;
      while (liveStars().evaluate().isNotEmpty && guard++ < 20) {
        final remaining = liveStars().evaluate().length;
        expect(
          allPopped,
          0,
          reason: 'still $remaining star(s) on screen — nothing to announce',
        );
        await tester.tap(liveStars().first, warnIfMissed: false);
        await tester.pump();
      }

      expect(liveStars(), findsNothing, reason: 'every star was popped');
      expect(pops, 8, reason: 'one pop SFX per star');
      expect(allPopped, 1, reason: 'the cleared field is announced exactly once');

      // A stray tap on the emptied stage must not announce a second time.
      await tester.tapAt(const Offset(200, 200));
      await tester.pump();
      expect(allPopped, 1);
    });

    testWidgets('onAllPopped does not fire while stars remain unpopped', (
      tester,
    ) async {
      var allPopped = 0;
      await tester.pumpWidget(
        host(
          reducedMotion: false,
          effectScale: 0.4,
          onAllPopped: () => allPopped++,
        ),
      );
      await settleSpawns(tester);

      await tester.tap(liveStars().first, warnIfMissed: false);
      await tester.pump(const Duration(seconds: 2));

      expect(allPopped, 0, reason: 'a partly cleared field is not cleared');
    });
  });

  group('reduced motion', () {
    testWidgets('stars sit statically (no drift) and pop with a fade', (
      tester,
    ) async {
      var pops = 0;
      await tester.pumpWidget(
        host(reducedMotion: true, onStarPop: () => pops++),
      );
      await settleSpawns(tester);

      final before = tester.getCenter(starPaints().first);
      await tester.pump(const Duration(milliseconds: 500));
      final after = tester.getCenter(starPaints().first);
      expect(after, before, reason: 'no drift under reduced motion');

      // A fading star still paints itself with the star painter, so count the
      // fades rather than the survivors. One tap can catch a couple of
      // overlapping stars; what must hold is one SFX per star that popped.
      await tester.tap(starPaints().first, warnIfMissed: false);
      await tester.pump();
      final faded = effectNamed('_StarFadeOut').evaluate().length;

      expect(faded, greaterThanOrEqualTo(1),
          reason: 'a simple fade, not a burst, under reduced motion');
      expect(effectNamed('RewardPopBurst'), findsNothing);
      expect(pops, faded, reason: 'the SFX still plays under reduced motion');
    });
  });

  group('provider guard', () {
    testWidgets('with no provider a pop neither crashes nor fires SFX', (
      tester,
    ) async {
      await tester.pumpWidget(host(reducedMotion: false, withProvider: false));
      await settleSpawns(tester);

      await tester.tap(starPaints().first, warnIfMissed: false);
      await tester.pump();

      expect(
        find.byType(StarReward),
        findsOneWidget,
        reason: 'absent provider must not crash the tap path',
      );
    });
  });
}
