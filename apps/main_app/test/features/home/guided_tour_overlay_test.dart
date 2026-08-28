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
}
