import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('MetricInfoIcon opens a sheet with the explanation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MetricInfoIcon(
              title: 'Correct Taps',
              explanations: [
                ('Correct Taps', AssessmentLabels.correctTapsInfo),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // Sheet shows the term heading and the parent-friendly explanation.
    expect(find.text('Correct Taps'), findsNWidgets(2));
    expect(find.text(AssessmentLabels.correctTapsInfo), findsOneWidget);
  });

  testWidgets('MetricInfoIcon lists multiple metric explanations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MetricInfoIcon(
              title: AssessmentLabels.gameResults,
              explanations: [
                (AssessmentLabels.correct, AssessmentLabels.correctTapsInfo),
                (AssessmentLabels.errors, AssessmentLabels.errorTapsInfo),
                (
                  AssessmentLabels.offTarget,
                  AssessmentLabels.offTargetTapsInfo,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text(AssessmentLabels.correctTapsInfo), findsOneWidget);
    expect(find.text(AssessmentLabels.errorTapsInfo), findsOneWidget);
    expect(find.text(AssessmentLabels.offTargetTapsInfo), findsOneWidget);
  });
}
