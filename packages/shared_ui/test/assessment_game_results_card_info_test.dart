import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('AssessmentGameResultsCard explains the tap-count terms', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssessmentGameResultsCard(
              games: const [
                ResultGameScore(
                  gameId: 'copy_me',
                  name: 'Copy Me',
                  emoji: '🧠',
                  accuracy: 0.8,
                  correctCount: 8,
                  errorCount: 2,
                  offTargetCount: 1,
                  totalItems: 10,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Card renders with its section label and one info affordance.
    expect(
      find.text(AssessmentLabels.gameResults.toUpperCase()),
      findsOneWidget,
    );
    expect(find.byType(MetricInfoIcon), findsOneWidget);

    // Tapping it explains all three count terms — this pins the card's
    // wiring, not just the widget's own defaults.
    await tester.tap(find.byType(MetricInfoIcon));
    await tester.pumpAndSettle();
    expect(find.text(AssessmentLabels.correctTapsInfo), findsOneWidget);
    expect(find.text(AssessmentLabels.errorTapsInfo), findsOneWidget);
    expect(find.text(AssessmentLabels.offTargetTapsInfo), findsOneWidget);
  });
}
