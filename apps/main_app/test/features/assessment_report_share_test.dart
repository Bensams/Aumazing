import 'dart:async';

import 'package:aumazing/features/history/history_models.dart';
import 'package:aumazing/features/pre_assessment/assessment_result_view.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/services/active_games_service.dart';
import 'package:aumazing/services/report_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  setUp(() async => ActiveGamesService.instance.activeGameIds);
  tearDown(() => ActiveGamesService.instance.invalidateCache());

  for (final presentation in AssessmentResultPresentation.values) {
    testWidgets('PDF action is available in ${presentation.name} mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          presentation: presentation,
          reportPdfSharer: _FakeAssessmentReportSharer(),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('share-assessment-pdf')),
        findsOneWidget,
      );
      expect(find.byTooltip('Share as PDF'), findsOneWidget);
    });
  }

  testWidgets('assessment share blocks repeats and restores after completion', (
    tester,
  ) async {
    final gate = Completer<void>();
    final reports = _FakeAssessmentReportSharer(gate: gate);
    await tester.pumpWidget(
      _app(
        presentation: AssessmentResultPresentation.completion,
        reportPdfSharer: reports,
      ),
    );
    await tester.pump();

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('share-assessment-pdf')),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pump();

    expect(reports.calls, 1);
    expect(reports.childName, 'Mika');
    expect(reports.model!.assessmentRunId, 'run-frozen');
    expect(reports.model!.games.single.offTargetCount, 4);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pump();
    expect(find.byKey(const ValueKey('share-assessment-pdf')), findsOneWidget);
  });

  testWidgets('assessment share failure is friendly and restores the action', (
    tester,
  ) async {
    final reports = _FakeAssessmentReportSharer(fail: true);
    await tester.pumpWidget(
      _app(
        presentation: AssessmentResultPresentation.review,
        reportPdfSharer: reports,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('share-assessment-pdf')));
    await tester.pump();

    expect(
      find.text('We couldn\u2019t create or share the PDF. Please try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('share-assessment-pdf')), findsOneWidget);
  });
}

Widget _app({
  required AssessmentResultPresentation presentation,
  required ReportPdfSharer reportPdfSharer,
}) => MaterialApp(
  theme: AppTheme.light,
  home: AssessmentResultView(
    results: [_result],
    profile: _profile,
    presentation: presentation,
    childDisplayName: 'Mika',
    reportPdfSharer: reportPdfSharer,
    showCelebration: false,
  ),
);

final _result = AssessmentResult(
  id: 'result-private',
  childId: 'child-private',
  assessmentRunId: 'run-frozen',
  type: 'pre',
  gameId: 'copy_me',
  score: 6,
  totalItems: 8,
  errorCount: 2,
  randomTouchCount: 4,
  avgResponseTimeMs: 1200,
  completedAt: DateTime(2026, 8, 20),
  modelSource: 'rubric_based',
);

const _profile = SupportProfile(
  communication: 'good',
  socialInteraction: 'emerging',
  playSkills: 'strong',
  attention: 'moderate',
  sensoryNotes: ['Prefers quiet play'],
  recommendedDifficulty: 'intermediate',
  recommendedPromptStyle: 'combined',
  recommendedSessionMinutes: 5,
  lowStimulationMode: true,
  turnTakingPractice: true,
  promptRepetition: 2,
);

class _FakeAssessmentReportSharer implements ReportPdfSharer {
  _FakeAssessmentReportSharer({this.gate, this.fail = false});

  final Completer<void>? gate;
  final bool fail;
  int calls = 0;
  AssessmentResultViewModel? model;
  String? childName;

  @override
  Future<void> shareAssessmentReport({
    required AssessmentResultViewModel model,
    required String childDisplayName,
  }) async {
    calls += 1;
    this.model = model;
    childName = childDisplayName;
    if (fail) throw StateError('simulated share failure');
    await gate?.future;
  }

  @override
  Future<void> shareHistoryReport({
    required HistorySummary summary,
    required String childDisplayName,
  }) => throw UnimplementedError();
}
