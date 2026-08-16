import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// The parent-facing surfaces added for AUM-161: the before/after progress
/// card, and the reason attached to each recommended activity.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: child)),
    );
    await tester.pumpAndSettle();
  }

  ResultProgressArea area(
    String label,
    int before,
    int after, {
    String beforeName = 'Needs Support',
    String afterName = 'Emerging',
  }) => ResultProgressArea(
    label: label,
    beforeLevelName: beforeName,
    afterLevelName: afterName,
    beforeLevelInt: before,
    afterLevelInt: after,
  );

  group('AssessmentProgressCard', () {
    testWidgets('shows each area as before → after', (tester) async {
      await pump(
        tester,
        SingleChildScrollView(
          child: AssessmentProgressCard(
            progress: ResultProgress(
              areas: [area('Communication', 0, 1)],
              beforeCompletedAt: DateTime(2026, 1, 1),
              afterCompletedAt: DateTime(2026, 2, 1),
            ),
          ),
        ),
      );

      expect(find.text('Communication'), findsOneWidget);
      expect(find.text('Needs Support → Emerging'), findsOneWidget);
      expect(find.text('Moved up'), findsOneWidget);
    });

    testWidgets('states a flat result neutrally, never as a failure', (
      tester,
    ) async {
      await pump(
        tester,
        SingleChildScrollView(
          child: AssessmentProgressCard(
            progress: ResultProgress(
              areas: [
                area(
                  'Attention',
                  1,
                  1,
                  beforeName: 'Emerging',
                  afterName: 'Emerging',
                ),
              ],
              beforeCompletedAt: DateTime(2026, 1, 1),
              afterCompletedAt: DateTime(2026, 2, 1),
            ),
          ),
        ),
      );

      expect(find.text('Held steady'), findsOneWidget);
      expect(find.textContaining('held steady'), findsWidgets);
      expect(find.textContaining('failed'), findsNothing);
      expect(find.textContaining('no progress'), findsNothing);
    });

    testWidgets('a drop reads as more practice, not regression', (
      tester,
    ) async {
      await pump(
        tester,
        SingleChildScrollView(
          child: AssessmentProgressCard(
            progress: ResultProgress(
              areas: [
                area(
                  'Play Skills',
                  2,
                  0,
                  beforeName: 'Strength',
                  afterName: 'Needs Support',
                ),
              ],
              beforeCompletedAt: DateTime(2026, 1, 1),
              afterCompletedAt: DateTime(2026, 2, 1),
            ),
          ),
        ),
      );

      expect(find.text('More practice here'), findsOneWidget);
      expect(find.textContaining('regress'), findsNothing);
      expect(find.textContaining('lost'), findsNothing);
    });

    testWidgets('always carries the not-a-diagnosis note', (tester) async {
      await pump(
        tester,
        SingleChildScrollView(
          child: AssessmentProgressCard(
            progress: ResultProgress(
              areas: [area('Communication', 0, 2, afterName: 'Strength')],
              beforeCompletedAt: DateTime(2026, 1, 1),
              afterCompletedAt: DateTime(2026, 2, 1),
            ),
          ),
        ),
      );

      expect(find.textContaining('not a diagnosis'), findsOneWidget);
    });
  });

  group('AssessmentLearningPathCard reasons', () {
    testWidgets('renders the reason under each activity', (tester) async {
      await pump(
        tester,
        SingleChildScrollView(
          child: const AssessmentLearningPathCard(
            modules: [
              ResultModule(
                name: 'Copy Me',
                startingLevel: 1,
                reason:
                    'Practises Communication, the area with the most '
                    'room to grow right now.',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Copy Me'), findsOneWidget);
      expect(
        find.textContaining('the area with the most room to grow'),
        findsOneWidget,
      );
    });

    testWidgets('an activity without a reason still renders', (tester) async {
      await pump(
        tester,
        SingleChildScrollView(
          child: const AssessmentLearningPathCard(
            modules: [ResultModule(name: 'Match It', startingLevel: 2)],
          ),
        ),
      );

      expect(find.text('Match It'), findsOneWidget);
      expect(find.text('Level 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
