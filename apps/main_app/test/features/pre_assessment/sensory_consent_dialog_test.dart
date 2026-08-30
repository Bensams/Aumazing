import 'package:aumazing/features/pre_assessment/sensory/sensory_consent_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// Sizes the dialog has to survive: narrow phone portrait, phone landscape,
/// and a tablet in both orientations.
const _sizes = <String, Size>{
  'phone portrait': Size(360, 640),
  'phone landscape': Size(640, 360),
  'tablet portrait': Size(800, 1280),
  'tablet landscape': Size(1280, 800),
};

void main() {
  for (final entry in _sizes.entries) {
    testWidgets('button labels stay on one line — ${entry.key}',
        (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: SensoryConsentDialog()),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in ['Allow Testing', 'Use My Settings']) {
        final finder = find.text(label);
        expect(finder, findsOneWidget);

        // Laid out at its full unwrapped width means it is on one line.
        final renderText = tester.renderObject<RenderParagraph>(finder);
        expect(
          renderText.size.width,
          closeTo(renderText.getMaxIntrinsicWidth(double.infinity), 0.5),
          reason: '"$label" wrapped onto multiple lines at ${entry.key}',
        );

        // ...and the scaled-down label has to fit inside its button.
        final labelRect = tester.getRect(finder);
        final buttonRect = tester.getRect(
          find.ancestor(of: finder, matching: find.byType(Row)).first,
        );
        expect(
          buttonRect.contains(labelRect.topLeft) &&
              buttonRect.contains(labelRect.bottomRight),
          isTrue,
          reason: '"$label" is clipped at ${entry.key}',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
