import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

const _modules = [
  ResultModule(name: 'Copy Me', startingLevel: 1),
  ResultModule(name: 'Match It', startingLevel: 2),
];

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

void main() {
  testWidgets('the card offers the way into My Path and says who takes the '
      'device', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _wrap(
        AssessmentLearningPathCard(
          modules: _modules,
          onOpenPath: () => opened++,
        ),
      ),
    );

    expect(find.text(AssessmentLabels.goToMyPath), findsOneWidget);
    expect(find.text(AssessmentLabels.handDeviceToChild), findsOneWidget);

    await tester.tap(find.text(AssessmentLabels.goToMyPath));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('no callback leaves the card read-only', (tester) async {
    await tester.pumpWidget(
      _wrap(const AssessmentLearningPathCard(modules: _modules)),
    );

    expect(find.text('Copy Me'), findsOneWidget);
    expect(find.text(AssessmentLabels.goToMyPath), findsNothing);
    expect(find.text(AssessmentLabels.handDeviceToChild), findsNothing);
  });

  testWidgets('a premium-locked path offers no way in', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AssessmentLearningPathCard(
          modules: const [],
          premiumRequired: true,
          onOpenPath: () {},
        ),
      ),
    );

    expect(find.text(AssessmentLabels.goToMyPath), findsNothing);
  });

  testWidgets('an empty path offers no way in', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AssessmentLearningPathCard(
          modules: const [],
          unavailable: true,
          onOpenPath: () {},
        ),
      ),
    );

    expect(find.text(AssessmentLabels.goToMyPath), findsNothing);
  });
}
