import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// Representative viewports the result screens must survive.
const _phonePortrait = Size(360, 800);
const _phoneLandscape = Size(800, 360);
const _tabletPortrait = Size(800, 1280);
const _tabletLandscape = Size(1280, 800);

/// A wide window whose content area is narrowed by a parent-dashboard
/// sidebar.
const _sidebarReduced = Size(1400, 900);
const _sidebarWidth = 320.0;

AssessmentResultViewModel _model({
  AssessmentAnalysisSource source = AssessmentAnalysisSource.onDeviceAi,
  double? confidence = 0.82,
}) {
  return AssessmentResultViewModel(
    assessmentType: 'pre',
    assessmentRunId: 'run-1',
    completedAt: DateTime(2026, 5, 12),
    games: const [
      ResultGameScore(
        gameId: 'copy_me',
        name: 'Copy Me',
        emoji: '🪞',
        accuracy: 0.5,
        correctCount: 5,
        errorCount: 5,
        totalItems: 10,
      ),
      ResultGameScore(
        gameId: 'match_it',
        name: 'Match It',
        emoji: '🧩',
        accuracy: 0.8,
        correctCount: 8,
        errorCount: 2,
        totalItems: 10,
      ),
    ],
    areas: const [
      ResultAreaLevel(
          label: 'Communication', levelName: 'Emerging', levelInt: 1),
      ResultAreaLevel(
          label: 'Social Interaction', levelName: 'Needs Support', levelInt: 0),
      ResultAreaLevel(label: 'Play Skills', levelName: 'Emerging', levelInt: 1),
      ResultAreaLevel(label: 'Attention', levelName: 'Strength', levelInt: 2),
    ],
    recommendations: const [
      ResultRecommendation(
          icon: Icons.speed_rounded,
          label: AssessmentLabels.difficulty,
          value: 'Intermediate'),
      ResultRecommendation(
          icon: Icons.record_voice_over_rounded,
          label: AssessmentLabels.promptStyle,
          value: 'Combined'),
      ResultRecommendation(
          icon: Icons.timer_rounded,
          label: AssessmentLabels.sessionLength,
          value: '5 min'),
      ResultRecommendation(
          icon: Icons.repeat_rounded,
          label: AssessmentLabels.promptRepetition,
          value: '2x'),
    ],
    source: source,
    confidence: confidence,
    summary: 'Play skills are emerging and attention is a strength.',
    learningPath: const [
      ResultModule(name: 'Copy Me', startingLevel: 1),
      ResultModule(name: 'Match It', startingLevel: 2),
    ],
    sensoryObservations: const ['Prefers Quiet Play'],
  );
}

Widget _wrap(
  Widget child, {
  double textScale = 1.0,
  double sidebarWidth = 0,
}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      theme: AppTheme.light,
      home: sidebarWidth == 0
          ? child
          : Row(
              children: [
                SizedBox(width: sidebarWidth, child: const ColoredBox(
                  color: Color(0xFFEEEEEE),
                  child: SizedBox.expand(),
                )),
                Expanded(child: child),
              ],
            ),
    ),
  );
}

Widget _layout(
  AssessmentResultPresentation presentation, {
  AssessmentResultViewModel? model,
}) {
  return AssessmentResultLayout(
    model: model ?? _model(),
    presentation: presentation,
    showCelebration: false,
    onContinue: () {},
    onRetake: () {},
    onBack: () {},
  );
}

/// Section labels in canonical order, as rendered (uppercase).
List<String> _sectionOrder(WidgetTester tester) => tester
    .widgetList<AssessmentSectionCard>(find.byType(AssessmentSectionCard))
    .map((card) => card.label)
    .toList();

const _canonicalOrder = [
  AssessmentLabels.overallPerformance,
  AssessmentLabels.developmentalProfile,
  AssessmentLabels.gameResults,
  AssessmentLabels.recommendedSettings,
  AssessmentLabels.recommendedActivities,
];

void main() {
  group('shared sections', () {
    for (final presentation in AssessmentResultPresentation.values) {
      testWidgets('$presentation shows every section in canonical order',
          (tester) async {
        await tester.binding.setSurfaceSize(_phonePortrait);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_wrap(_layout(presentation)));
        await tester.pumpAndSettle();

        expect(_sectionOrder(tester), _canonicalOrder);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$presentation shows the disclaimer', (tester) async {
        await tester.binding.setSurfaceSize(_phonePortrait);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_wrap(_layout(presentation)));
        await tester.pumpAndSettle();

        expect(find.byType(AssessmentDisclaimer), findsOneWidget);
        expect(find.text(AssessmentLabels.disclaimer), findsOneWidget);
      });

      testWidgets('$presentation shows the same source and confidence',
          (tester) async {
        await tester.binding.setSurfaceSize(_phonePortrait);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_wrap(_layout(presentation)));
        await tester.pumpAndSettle();

        expect(find.text(AssessmentLabels.onDeviceAi), findsOneWidget);
        // Confidence 0.82 → 82%; overall weighted accuracy → 65%.
        expect(find.text('82%'), findsOneWidget);
        expect(find.text('65%'), findsOneWidget);
      });
    }

    testWidgets('rule-based results still name their source', (tester) async {
      await tester.binding.setSurfaceSize(_phonePortrait);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(_layout(
        AssessmentResultPresentation.review,
        model: _model(source: AssessmentAnalysisSource.ruleBased),
      )));
      await tester.pumpAndSettle();

      expect(find.text(AssessmentLabels.ruleBased), findsOneWidget);
    });

    testWidgets('raw counts are shown as counts, not percentages',
        (tester) async {
      await tester.binding.setSurfaceSize(_phonePortrait);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(_layout(
        AssessmentResultPresentation.completion,
      )));
      await tester.pumpAndSettle();

      expect(find.text(AssessmentLabels.correct), findsOneWidget);
      expect(find.text(AssessmentLabels.errors), findsOneWidget);
      expect(find.text(AssessmentLabels.totalItems), findsOneWidget);
      expect(find.text('13'), findsOneWidget); // correct
      expect(find.text('7'), findsOneWidget); // errors
      expect(find.text('20'), findsOneWidget); // total items
    });
  });

  group('mode-specific framing', () {
    testWidgets('completion mode celebrates and offers Continue',
        (tester) async {
      await tester.binding.setSurfaceSize(_phonePortrait);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(AssessmentResultLayout(
        model: _model(),
        presentation: AssessmentResultPresentation.completion,
        onContinue: () {},
      )));
      await tester.pump();

      expect(find.byType(GameCelebrationOverlay), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text(AssessmentLabels.continueToHome), findsOneWidget);
      expect(find.text(AssessmentLabels.retakeAssessment), findsNothing);
    });

    testWidgets('review mode skips the celebration and offers Retake + Home',
        (tester) async {
      await tester.binding.setSurfaceSize(_phonePortrait);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(AssessmentResultLayout(
        model: _model(),
        presentation: AssessmentResultPresentation.review,
        backLabel: AssessmentLabels.home,
        onRetake: () {},
        onBack: () {},
      )));
      await tester.pump();

      expect(find.byType(GameCelebrationOverlay), findsNothing);

      await tester.pumpAndSettle();

      expect(find.text(AssessmentLabels.retakeAssessment), findsOneWidget);
      expect(find.text(AssessmentLabels.home), findsOneWidget);
      expect(find.text(AssessmentLabels.continueToHome), findsNothing);
    });

    testWidgets('review mode shows the completion date', (tester) async {
      await tester.binding.setSurfaceSize(_phonePortrait);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(_layout(
        AssessmentResultPresentation.review,
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('May 12, 2026'), findsOneWidget);
    });

    testWidgets('actions meet the minimum touch target', (tester) async {
      await tester.binding.setSurfaceSize(_phonePortrait);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(_layout(
        AssessmentResultPresentation.review,
      )));
      await tester.pumpAndSettle();

      for (final finder in [
        find.byType(AppSecondaryButton),
        find.byType(AppPrimaryButton),
      ]) {
        expect(
          tester.getSize(finder).height,
          greaterThanOrEqualTo(48.0),
          reason: 'result actions must be at least 48 logical pixels tall',
        );
      }
    });
  });

  group('responsive layouts', () {
    final viewports = <String, Size>{
      'portrait phone': _phonePortrait,
      'landscape phone': _phoneLandscape,
      'portrait tablet': _tabletPortrait,
      'landscape tablet': _tabletLandscape,
    };

    for (final entry in viewports.entries) {
      for (final presentation in AssessmentResultPresentation.values) {
        testWidgets('${entry.key} · $presentation lays out without overflow',
            (tester) async {
          await tester.binding.setSurfaceSize(entry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(_wrap(_layout(presentation)));
          await tester.pumpAndSettle();

          expect(_sectionOrder(tester), _canonicalOrder);
          expect(find.byType(AssessmentDisclaimer), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a sidebar-reduced content area still fits', (tester) async {
      await tester.binding.setSurfaceSize(_sidebarReduced);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(
        _layout(AssessmentResultPresentation.review),
        sidebarWidth: _sidebarWidth,
      ));
      await tester.pumpAndSettle();

      expect(_sectionOrder(tester), _canonicalOrder);
      expect(tester.takeException(), isNull);
    });

    for (final entry in viewports.entries) {
      testWidgets('${entry.key} survives 1.3x text scaling', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_wrap(
          _layout(AssessmentResultPresentation.review),
          textScale: 1.3,
        ));
        await tester.pumpAndSettle();

        expect(_sectionOrder(tester), _canonicalOrder);
        expect(find.text(AssessmentLabels.retakeAssessment), findsOneWidget);
        expect(find.text(AssessmentLabels.backToDashboard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('essential text is never ellipsized', (tester) async {
      await tester.binding.setSurfaceSize(_phonePortrait);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(
        _layout(AssessmentResultPresentation.review),
        textScale: 1.3,
      ));
      await tester.pumpAndSettle();

      // Text may declare an ellipsis as a safety net; what matters is that
      // nothing actually gets clipped at this scale.
      final clipped = <String?>[];
      for (final element in find.byType(Text).evaluate()) {
        final paragraph = element.renderObject;
        if (paragraph is RenderParagraph && paragraph.didExceedMaxLines) {
          clipped.add((element.widget as Text).data);
        }
      }
      expect(clipped, isEmpty);
    });
  });

  group('scoring policy', () {
    test('overall accuracy is the item-weighted adjusted accuracy', () {
      const games = [
        ResultGameScore(
          gameId: 'a',
          name: 'A',
          emoji: '',
          accuracy: 0.5,
          totalItems: 10,
        ),
        ResultGameScore(
          gameId: 'b',
          name: 'B',
          emoji: '',
          accuracy: 1.0,
          totalItems: 30,
        ),
      ];
      // (0.5 * 10 + 1.0 * 30) / 40 = 0.875 — not the unweighted 0.75.
      expect(AssessmentScoring.overallAdjustedAccuracy(games), 0.875);
    });

    test('empty results and zero total items are safe', () {
      expect(AssessmentScoring.overallAdjustedAccuracy(const []), 0.0);
      expect(
        AssessmentScoring.overallAdjustedAccuracy(const [
          ResultGameScore(
            gameId: 'a',
            name: 'A',
            emoji: '',
            accuracy: 0.9,
            totalItems: 0,
          ),
        ]),
        0.0,
      );
    });

    test('raw counts sum across games', () {
      final model = _model();
      expect(model.correctCount, 13);
      expect(model.errorCount, 7);
      expect(model.totalItems, 20);
      // Weighted: (0.5 * 10 + 0.8 * 10) / 20 = 0.65 — note this is NOT the
      // raw 13/20 = 0.65 by coincidence of the fixture; the formula differs.
      expect(model.overallPercent, 65);
    });

    test('an empty run renders zeroes rather than dividing by zero', () {
      final model = AssessmentResultViewModel(
        assessmentType: 'pre',
        games: const [],
        areas: const [],
        recommendations: const [],
        source: AssessmentAnalysisSource.ruleBased,
      );
      expect(model.overallPercent, 0);
      expect(model.totalItems, 0);
      expect(model.confidencePercent, isNull);
    });
  });
}
