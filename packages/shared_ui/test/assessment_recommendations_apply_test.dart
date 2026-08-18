import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// Two rows with a setting behind them, one without — the real shape of a
/// recommendation set, and the case the note has to be honest about.
const _mixed = [
  ResultRecommendation(
    icon: Icons.speed_rounded,
    label: AssessmentLabels.difficulty,
    value: 'Intermediate',
  ),
  ResultRecommendation(
    icon: Icons.timer_rounded,
    label: AssessmentLabels.sessionLength,
    value: '5 min',
  ),
  ResultRecommendation(
    icon: Icons.repeat_rounded,
    label: AssessmentLabels.promptRepetition,
    value: '2x',
    appliesToSetting: false,
  ),
];

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('applying recommended settings', () {
    testWidgets('no button at all without a handler', (tester) async {
      await tester.pumpWidget(_wrap(
        const AssessmentRecommendationsCard(recommendations: _mixed),
      ));

      expect(find.text('Use these settings'), findsNothing);
      // The recommendations themselves are still shown — read-only is the
      // old behaviour, not a degraded one.
      expect(find.text('Intermediate'), findsOneWidget);
    });

    testWidgets('the button writes the settings and then says so',
        (tester) async {
      var applied = 0;
      await tester.pumpWidget(_wrap(
        AssessmentRecommendationsCard(
          recommendations: _mixed,
          onApply: () async {
            applied++;
            return true;
          },
        ),
      ));

      await tester.tap(find.text('Use these settings'));
      await tester.pumpAndSettle();

      expect(applied, 1);
      expect(find.text('Settings updated'), findsOneWidget);

      // Disabled afterwards, so a parent is never left wondering whether the
      // first press took.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('rows with no setting behind them are named, not implied',
        (tester) async {
      await tester.pumpWidget(_wrap(
        AssessmentRecommendationsCard(
          recommendations: _mixed,
          onApply: () async => true,
        ),
      ));

      await tester.tap(find.text('Use these settings'));
      await tester.pumpAndSettle();

      final note = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((s) => s.contains('Saved'));
      expect(note, contains('difficulty'));
      expect(note, contains('session length'));
      // The one that was not written must be called out by name.
      expect(note, contains('prompt repetition'));
      expect(note, contains('no matching setting yet'));
    });

    testWidgets('a failed apply never claims the settings changed',
        (tester) async {
      await tester.pumpWidget(_wrap(
        AssessmentRecommendationsCard(
          recommendations: _mixed,
          onApply: () async => false,
        ),
      ));

      await tester.tap(find.text('Use these settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings updated'), findsNothing);
      expect(find.text('Nothing was changed. Please try again.'),
          findsOneWidget);
      // Still pressable, because trying again is the advice given.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('nothing to apply hides the button', (tester) async {
      await tester.pumpWidget(_wrap(
        AssessmentRecommendationsCard(
          recommendations: const [
            ResultRecommendation(
              icon: Icons.repeat_rounded,
              label: AssessmentLabels.promptRepetition,
              value: '2x',
              appliesToSetting: false,
            ),
          ],
          onApply: () async => true,
        ),
      ));

      expect(find.text('Use these settings'), findsNothing);
      expect(find.text('2x'), findsOneWidget);
    });
  });
}
