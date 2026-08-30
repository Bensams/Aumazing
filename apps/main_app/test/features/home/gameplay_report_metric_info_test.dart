import 'package:aumazing/features/home/gameplay_report_screen.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

GameplaySession _session({
  int offTaskActionCount = 2,
  int randomTouchCount = 5,
}) => GameplaySession(
  id: 's-1',
  childId: 'child-1',
  gameId: 'copy_me',
  context: 'practice',
  score: 8,
  totalItems: 10,
  errorCount: 2,
  totalResponseTimeMs: 15000,
  retryCount: 1,
  hintCount: 0,
  promptCount: 0,
  idleTimeSeconds: 4,
  randomTouchCount: randomTouchCount,
  avgResponseTime: 1.5,
  avgValidResponseTime: 1.2,
  offTaskActionCount: offTaskActionCount,
  improvementScore: 0.1,
  consistencyScore: 0.9,
  bgMusicEnabled: true,
  hapticFeedbackEnabled: true,
  startedAt: DateTime(2026, 8, 29, 10),
  endedAt: DateTime(2026, 8, 29, 10, 2),
);

void main() {
  testWidgets('gameplay report explains off-task actions and random touches', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameplayReportScreen(
          session: _session(),
          palette: GamePalettes.neutral,
        ),
      ),
    );
    // AUM-319: each conflatable metric gets its own info affordance.
    // Icon order follows the metric rows: Errors, Off-task actions,
    // Random touches.
    expect(find.byType(MetricInfoIcon), findsNWidgets(3));

    final offTaskIcon = find.byType(MetricInfoIcon).at(1);
    await tester.ensureVisible(offTaskIcon);
    await tester.pumpAndSettle();
    await tester.tap(offTaskIcon);
    await tester.pumpAndSettle();
    expect(find.text(AssessmentLabels.offTaskActionsInfo), findsOneWidget);
    expect(find.text(AssessmentLabels.randomTouchesInfo), findsNothing);

    // Close the sheet, then check the random-touches explanation.
    final sheetContext = tester.element(
      find.text(AssessmentLabels.offTaskActionsInfo),
    );
    Navigator.of(sheetContext).pop();
    await tester.pumpAndSettle();

    final randomIcon = find.byType(MetricInfoIcon).at(2);
    await tester.ensureVisible(randomIcon);
    await tester.pumpAndSettle();
    await tester.tap(randomIcon);
    await tester.pumpAndSettle();
    expect(find.text(AssessmentLabels.randomTouchesInfo), findsOneWidget);
    expect(find.text(AssessmentLabels.offTaskActionsInfo), findsNothing);
  });
}
