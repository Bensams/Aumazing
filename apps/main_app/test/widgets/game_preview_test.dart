import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

import 'package:aumazing/features/settings/widgets/game_preview.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ChildBackground background,
  required GameObjectStyle style,
}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              child: GamePreview(background: background, objectStyle: style),
            ),
          ),
        ),
      ),
    );

void main() {
  const light = ChildBackground.solid(Color(0xFFFAF9F6));
  const blend =
      ChildBackground.gradient(Color(0xFFA9E3CC), Color(0xFF1E2438));

  testWidgets('renders for every outline style without overflowing',
      (tester) async {
    for (final outline in ObjectOutline.values) {
      await _pump(
        tester,
        background: light,
        style: GameObjectStyle(outline: outline, outlineWidth: 8),
      );
      expect(tester.takeException(), isNull, reason: outline.label);
      expect(find.byType(GamePreview), findsOneWidget);
    }
  });

  testWidgets('renders a gradient background and a fixed card colour',
      (tester) async {
    await _pump(
      tester,
      background: blend,
      style: const GameObjectStyle(cardColour: Color(0xFF2E2E33)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a very narrow card without a negative-size paint',
      (tester) async {
    // Five cards plus padding in a small box is the layout most likely to
    // produce a zero or negative width.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: GamePreview(
                background: light,
                objectStyle: const GameObjectStyle(),
                height: 80,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('is announced as a preview, not as loose shapes',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, background: light, style: const GameObjectStyle());

    expect(
      find.bySemanticsLabel(
          'Preview: how a game round will look with these settings'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
