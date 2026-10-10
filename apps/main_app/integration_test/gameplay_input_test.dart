import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:integration_test/integration_test.dart';

const _e2eEnabled = bool.fromEnvironment('E2E_TEST_MODE');
const _screenshotsEnabled = bool.fromEnvironment(
  'E2E_SCREENSHOTS',
  defaultValue: true,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(RoutineArtCache.ensureLoaded);

  testWidgets('real drag rejects a distractor then places the correct card', (
    tester,
  ) async {
    expect(_e2eEnabled, isTrue);
    await tester.binding.setSurfaceSize(const Size(960, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    if (!kIsWeb) await binding.convertFlutterSurfaceToImage();
    final completions = <Map<String, dynamic>>[];
    final game = AnongSusunodGame(
      childId: 'e2e-child',
      profile: DifficultyProfile.medium,
      onStepChanged: (_) {},
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
          'total_items': totalItems,
          'errors': errorCount,
        });
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Semantics(
            container: true,
            label: 'Anong Susunod play area',
            child: GameWidget(
              key: const Key('game.canvas.anong_susunod'),
              game: game,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.bySemanticsLabel('Anong Susunod play area'), findsOneWidget);
    final cards = game.children.whereType<RoutineCard>().toList();
    final openSlot = game.children.whereType<SequenceSlot>().firstWhere(
      (slot) => slot.filled == null,
    );
    final expected = kRoutines.first.steps[openSlot.index].id;
    final wrong = cards.firstWhere((card) => card.step.id != expected);
    final correct = cards.firstWhere((card) => card.step.id == expected);

    await _drag(tester, _center(wrong), _center(openSlot));
    await tester.pump(const Duration(milliseconds: 400));
    expect(openSlot.filled, isNull);
    expect(wrong.placed, isFalse);

    await _drag(tester, _center(correct), _center(openSlot));
    await tester.pump(const Duration(milliseconds: 100));
    expect(openSlot.filled?.id, expected);
    expect(correct.placed, isTrue);
    expect(completions, isEmpty);

    if (_screenshotsEnabled) {
      final screenshot = await binding.takeScreenshot(
        'anong-susunod-real-drag-960x600',
      );
      expect(screenshot, isNotEmpty);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Offset _center(dynamic component) =>
    Offset(component.position.x as double, component.position.y as double);

Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(from);
  for (var step = 1; step <= 16; step++) {
    await gesture.moveTo(Offset.lerp(from, to, step / 16)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 32));
}
