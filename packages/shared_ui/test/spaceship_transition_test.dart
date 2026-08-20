import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// Pushes [SpaceshipTransitionRoute] onto a navigator and returns the tester
/// sitting on the first frame of the transition.
Future<NavigatorState> _launchInto(
  WidgetTester tester, {
  required bool reducedMotion,
}) async {
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navKey,
    home: const Scaffold(body: Text('lobby')),
  ));

  navKey.currentState!.push(
    SpaceshipTransitionRoute<void>(
      style: WorldStyles.nightSky,
      reducedMotion: reducedMotion,
      builder: (_) => const Scaffold(body: Text('next game')),
    ),
  );
  await tester.pump(); // start the transition
  return navKey.currentState!;
}

void main() {
  testWidgets('lands on the destination once the flight finishes',
      (tester) async {
    await _launchInto(tester, reducedMotion: false);
    // Past the full 1.4s duration, the ship is gone and the game is up.
    await tester.pumpAndSettle();
    expect(find.text('next game'), findsOneWidget);
  });

  testWidgets('holds the destination back while the ship is still crossing',
      (tester) async {
    await _launchInto(tester, reducedMotion: false);
    // Early in the flight the destination is not yet revealed — the child sees
    // the space scene travelling, not the next game popping in immediately.
    await tester.pump(const Duration(milliseconds: 200));
    final reveal = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('next game'),
        matching: find.byType(Opacity),
      ).first,
    );
    expect(reveal.opacity, lessThan(0.2));
  });

  testWidgets('reduced motion is a plain cross-fade, no space scene',
      (tester) async {
    await _launchInto(tester, reducedMotion: true);
    await tester.pump(const Duration(milliseconds: 150));
    // The flight overlay (WorldBackdrop) never appears under reduced motion.
    expect(find.byType(WorldBackdrop), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('next game'), findsOneWidget);
  });

  testWidgets('the space scene is shown mid-flight in full motion',
      (tester) async {
    await _launchInto(tester, reducedMotion: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorldBackdrop), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
