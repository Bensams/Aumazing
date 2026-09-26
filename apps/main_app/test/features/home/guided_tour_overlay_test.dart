import 'package:aumazing/features/home/widgets/guided_tour_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  final firstKey = GlobalKey();
  final hiddenKey = GlobalKey();
  final lastKey = GlobalKey();

  List<TourStep> steps() => [
    const TourStep(title: 'Welcome', body: 'A quick tour.'),
    TourStep(targetKey: firstKey, title: 'First', body: 'The first control.'),
    TourStep(
      targetKey: hiddenKey,
      title: 'Hidden',
      body: 'Never on screen in this layout.',
    ),
    TourStep(targetKey: lastKey, title: 'Last', body: 'The last control.'),
  ];

  Widget buildHarness({required VoidCallback onFinish}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                SizedBox(key: firstKey, height: 80, child: const Text('One')),
                const Spacer(),
                SizedBox(key: lastKey, height: 80, child: const Text('Two')),
              ],
            ),
            GuidedTourOverlay(steps: steps(), onFinish: onFinish),
          ],
        ),
      ),
    );
  }

  testWidgets('walks the steps and skips targets that are not on screen', (
    tester,
  ) async {
    var finished = 0;
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildHarness(onFinish: () => finished++));
    await tester.pumpAndSettle();

    // Welcome has no target, so it is centred with no cutout.
    expect(find.text('A quick tour.'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('The first control.'), findsOneWidget);

    // The unmounted target is jumped over rather than spotlighting nothing.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Never on screen in this layout.'), findsNothing);
    expect(find.text('The last control.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('Back returns to the previous step', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildHarness(onFinish: () {}));
    await tester.pumpAndSettle();

    // The first step has nothing to go back to.
    expect(find.text('Back'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('The first control.'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('A quick tour.'), findsOneWidget);
  });

  testWidgets('Skip ends the tour immediately', (tester) async {
    var finished = 0;
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildHarness(onFinish: () => finished++));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('the scrim swallows taps meant for the dashboard beneath it', (
    tester,
  ) async {
    var taps = 0;
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: ElevatedButton(
                  onPressed: () => taps++,
                  child: const Text('Danger'),
                ),
              ),
              GuidedTourOverlay(
                steps: const [TourStep(title: 'Welcome', body: 'Hello.')],
                onFinish: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(40, 40));
    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  group('an action step', () {
    final targetKey = GlobalKey();

    Widget buildPrompt({
      required VoidCallback onAction,
      required VoidCallback onFinish,
    }) {
      return MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  key: targetKey,
                  width: 200,
                  height: 60,
                  child: const Text('Start'),
                ),
              ),
              GuidedTourOverlay(
                steps: [
                  TourStep(
                    targetKey: targetKey,
                    title: 'Start the pre-assessment',
                    body: 'Find your child’s strengths.',
                    tags: const ['Communication', 'Play Skills'],
                    actionLabel: 'Start now',
                    dismissLabel: 'Later',
                    onAction: onAction,
                  ),
                ],
                onFinish: onFinish,
              ),
            ],
          ),
        ),
      );
    }

    // The ring pulses for as long as the prompt is up, so these pump fixed
    // frames rather than waiting for the animation to settle.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('reads as a prompt: its own labels, tags, and no counter', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildPrompt(onAction: () {}, onFinish: () {}));
      await settle(tester);

      expect(find.text('Start now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Communication'), findsOneWidget);
      expect(find.text('Play Skills'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('1 of 1'), findsNothing);
    });

    testWidgets('the action button closes the overlay, then runs the action', (
      tester,
    ) async {
      final events = <String>[];
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildPrompt(
          onAction: () => events.add('action'),
          onFinish: () => events.add('finish'),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Start now'));
      await settle(tester);
      expect(events, ['finish', 'action']);
    });

    testWidgets('tapping the spotlighted control runs the action', (
      tester,
    ) async {
      var actions = 0;
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildPrompt(onAction: () => actions++, onFinish: () {}),
      );
      await settle(tester);

      await tester.tapAt(tester.getCenter(find.byKey(targetKey)));
      await settle(tester);
      expect(actions, 1);
    });

    testWidgets('Later, or a tap elsewhere, dismisses without the action', (
      tester,
    ) async {
      var actions = 0;
      var finished = 0;
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildPrompt(onAction: () => actions++, onFinish: () => finished++),
      );
      await settle(tester);

      await tester.tap(find.text('Later'));
      await settle(tester);
      expect(finished, 1);
      expect(actions, 0);

      // A fresh overlay, not the dismissed one.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        buildPrompt(onAction: () => actions++, onFinish: () => finished++),
      );
      await settle(tester);
      await tester.tapAt(const Offset(20, 580));
      await settle(tester);
      expect(actions, 0);
    });
  });
}
