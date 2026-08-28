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
    bool withProvider = true,
  }) {
    final star = StarReward(
      reducedMotion: reducedMotion,
      effectScale: effectScale,
      appearDelay: Duration.zero,
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

  Finder effectNamed(String name) =>
      find.byWidgetPredicate((widget) => widget.runtimeType.toString() == name);

  /// Pumps until every spawn timer has fired. [appearDelay] is zero and stars
  /// spawn at `i * 60ms`; the last of 20 fires at 1140ms, so 1500ms covers all.
  Future<void> settleSpawns(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1500));
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

      await tester.tap(starPaints().first, warnIfMissed: false);
      await tester.pump();

      expect(pops, 1, reason: 'each popped star plays the star-pop once');
      expect(
        effectNamed('_StarPopBurst'),
        findsOneWidget,
        reason: 'a radial sparkle burst, not a fade, under full motion',
      );

      // Tapping the emptied spot again must not re-fire a pop.
      final emptiedSpot = tester.getCenter(starPaints().first);
      await tester.tapAt(emptiedSpot);
      await tester.pump();
      expect(pops, 1, reason: 'a popped star cannot be popped again');
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

      await tester.tap(starPaints().first, warnIfMissed: false);
      await tester.pump();

      expect(pops, 1, reason: 'the SFX still plays under reduced motion');
      expect(
        effectNamed('_StarFadeOut'),
        findsOneWidget,
        reason: 'a simple fade, not a burst, under reduced motion',
      );
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
