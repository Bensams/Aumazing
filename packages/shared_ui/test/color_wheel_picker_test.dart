import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_ui/shared_ui.dart';

/// The wheel is a drag surface, so its semantics are the only way a screen
/// reader or switch user can reach it at all. It shipped declaring an
/// `increase` action with a `value` but no `increasedValue`, which Flutter
/// asserts on — so the control threw the moment semantics were switched on,
/// i.e. exactly for the users it was annotated for.
void main() {
  Future<Color> pumpWheel(
    WidgetTester tester, {
    Color initial = const Color(0xFF9B82C4),
  }) async {
    var current = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ColorWheelPicker(
              colour: current,
              label: 'Background colour',
              onChanged: (c) => setState(() => current = c),
            ),
          ),
        ),
      ),
    );
    return current;
  }

  testWidgets('builds with semantics enabled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWheel(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('the hue is adjustable without dragging', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWheel(tester, initial: const Color(0xFFFF0000)); // hue 0
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.bySemanticsLabel(
        RegExp('Background colour hue')));

    // Both annotations must be present together, or the framework asserts.
    expect(node.value, isNotEmpty);
    expect(node.increasedValue, isNotEmpty);
    expect(node.decreasedValue, isNotEmpty);
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);

    handle.dispose();
  });

  testWidgets('stepping down from red wraps instead of going negative',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWheel(tester, initial: const Color(0xFFFF0000)); // hue 0
    await tester.pumpAndSettle();

    final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Background colour hue')));
    expect(node.value, '0 degrees');
    expect(node.increasedValue, '15 degrees');
    // The wrap is the case a plain `hue - 15` gets wrong.
    expect(node.decreasedValue, '345 degrees');

    handle.dispose();
  });

  testWidgets('the brightness slider is named', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWheel(tester);
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
