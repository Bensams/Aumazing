import 'dart:io';

import 'package:aumazing/features/history/history_models.dart';
import 'package:aumazing/model/assessment_run_record.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/services/report_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  group('assessment parent report', () {
    test('contains canonical sections and values in displayed order', () async {
      final service = ReportPdfService(now: () => DateTime(2026, 8, 28, 9, 30));
      final report = await service.buildAssessmentReport(
        model: _assessmentModel(),
        childDisplayName: 'Mika Santos',
      );

      expect(report.bytes.take(4), [0x25, 0x50, 0x44, 0x46]);
      expect(
        report.filename,
        'aumazing_pre-assessment_mika-santos_2026-08-20.pdf',
      );
      expect(report.sectionTitles, [
        AssessmentLabels.overallPerformance,
        AssessmentLabels.overallProgress,
        AssessmentLabels.progressSinceFirst,
        AssessmentLabels.developmentalProfile,
        AssessmentLabels.gameResults,
        AssessmentLabels.recommendedSettings,
        AssessmentLabels.recommendedActivities,
        'Important information',
      ]);
      expect(report.plainText, contains('Pre-Assessment Report'));
      expect(report.plainText, contains('Child: Mika Santos'));
      expect(report.plainText, contains('Completion date: Aug 20, 2026'));
      expect(report.plainText, contains('Analysis source: On-Device AI'));
      expect(report.plainText, contains('Adjusted accuracy: 75%'));
      expect(report.plainText, contains('Copy Me | 75% | 6 | 2 | 3 | 8'));
      expect(report.plainText, contains('Low-Stimulation Mode | On'));
      expect(
        report.plainText,
        contains('Copy Me | Level 2 | Builds communication.'),
      );
      expect(report.plainText, contains(ReportPdfService.disclaimer));
    });

    test('post report exports the full current canonical model', () async {
      final service = ReportPdfService(now: () => DateTime(2026, 8, 28));
      final report = await service.buildAssessmentReport(
        model: _assessmentModel(assessmentType: 'post', premiumRequired: true),
        childDisplayName: 'Mika',
      );

      expect(report.plainText, contains('Post-Assessment Report'));
      expect(report.plainText, contains('Game Results'));
      expect(report.plainText, contains('Off-target'));
      expect(report.plainText, contains('Recommended Settings'));
      expect(report.plainText, contains('Overall Progress'));
      expect(report.plainText, contains('Progress Since the First Assessment'));
      expect(
        report.plainText,
        contains(
          'Premium is required to generate the next personalized module.',
        ),
      );
      expect(report.plainText, isNot(contains('Builds communication.')));
    });
  });

  group('history parent report', () {
    test(
      'uses the loaded snapshot, safe filename, and omits internal IDs',
      () async {
        const childId = 'db-child-7f4b8b89';
        const runId = 'run-private-8877';
        const sessionId = 'session-private-9900';
        final summary = _historySummary(
          childId: childId,
          runId: runId,
          sessionId: sessionId,
        );
        final service = ReportPdfService(
          now: () => DateTime(2026, 8, 28, 14, 5),
        );
        final report = await service.buildHistoryReport(
          summary: summary,
          childDisplayName: r'Mika / ..\Santos:*?',
        );

        expect(
          report.filename,
          'aumazing_history-progress_mika-santos_2026-08-28.pdf',
        );
        expect(report.filename, isNot(contains('/')));
        expect(report.filename, isNot(contains(r'\')));
        expect(report.plainText, isNot(contains(childId)));
        expect(report.plainText, isNot(contains(runId)));
        expect(report.plainText, isNot(contains(sessionId)));
        expect(report.plainText, contains('Match It | 8 | 10 | 80% | 2'));
        expect(report.plainText, contains('+20 points overall'));
        expect(report.plainText, contains('My Path | Completed'));
        expect(report.plainText, contains('Match It | 7 | Aug 27, 2026'));
        expect(
          report.sectionTitles.indexOf('Assessment History'),
          lessThan(report.sectionTitles.indexOf('Progress Comparison')),
        );
        expect(
          report.sectionTitles.indexOf('Progress Comparison'),
          lessThan(report.sectionTitles.indexOf('Completed My Path & Modules')),
        );
        expect(
          report.sectionTitles.indexOf('Completed My Path & Modules'),
          lessThan(report.sectionTitles.indexOf('Practice History')),
        );
      },
    );

    test(
      'sharing writes one temporary PDF and invokes the platform callback',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'aum311-report-',
        );
        addTearDown(() => temporary.delete(recursive: true));
        List<XFile>? shared;
        final service = ReportPdfService(
          now: () => DateTime(2026, 8, 28),
          temporaryDirectoryProvider: () async => temporary,
          shareCallback: (files, {subject, text}) async {
            shared = files;
            return const ShareResult('completed', ShareResultStatus.success);
          },
        );
        final summary = _historySummary(
          childId: 'child-private',
          runId: 'run-private',
          sessionId: 'session-private',
        );

        await service.shareHistoryReport(
          summary: summary,
          childDisplayName: 'Mika',
        );

        expect(shared, hasLength(1));
        expect(shared!.single.mimeType, 'application/pdf');
        expect(await File(shared!.single.path).exists(), isTrue);
      },
    );

    test(
      'renders the complete latest-20 practice snapshot across pages',
      () async {
        final sessions = List.generate(
          20,
          (index) => GameplaySession(
            id: 'private-session-$index',
            childId: 'private-child',
            gameId: 'match_it',
            context: 'practice',
            score: index + 1,
            totalItems: 20,
            errorCount: 20 - index,
            totalResponseTimeMs: 1000,
            startedAt: DateTime(2026, 8, 28 - index),
            endedAt: DateTime(2026, 8, 28 - index, 0, 5),
          ),
        );
        final report = await ReportPdfService(
          now: () => DateTime(2026, 8, 28),
        ).buildHistoryReport(
          summary: HistorySummary(
            runs: const [],
            completedModules: const [],
            practiceSessions: sessions,
            comparison: null,
          ),
          childDisplayName: 'Mika',
        );

        expect(report.plainText, contains('Showing the latest 20 sessions.'));
        expect(report.plainText, contains('Match It | 1 | Aug 28, 2026'));
        expect(report.plainText, contains('Match It | 20 | Aug 9, 2026'));
        expect(report.bytes, isNotEmpty);
      },
    );
  });
}

AssessmentResultViewModel _assessmentModel({
  String assessmentType = 'pre',
  bool premiumRequired = false,
}) => AssessmentResultViewModel(
  assessmentType: assessmentType,
  completedAt: DateTime(2026, 8, 20, 11),
  source: AssessmentAnalysisSource.onDeviceAi,
  confidence: 0.82,
  summary: 'Mika completed the activities with steady attention.',
  games: const [
    ResultGameScore(
      gameId: 'copy_me',
      name: 'Copy Me',
      emoji: '',
      accuracy: 0.75,
      correctCount: 6,
      errorCount: 2,
      offTargetCount: 3,
      totalItems: 8,
    ),
  ],
  areas: const [
    ResultAreaLevel(label: 'Communication', levelName: 'Emerging', levelInt: 1),
  ],
  sensoryObservations: const ['Prefers quieter sounds'],
  recommendations: const [
    ResultRecommendation(
      icon: Icons.visibility_off_rounded,
      label: AssessmentLabels.lowStimulationMode,
      value: 'On',
    ),
  ],
  learningPath: const [
    ResultModule(
      name: 'Copy Me',
      startingLevel: 2,
      reason: 'Builds communication.',
    ),
  ],
  premiumRequired: premiumRequired,
  overallProgress: const ResultOverallProgress(
    accuracyDelta: 0.15,
    responseTimeDeltaMs: 250,
  ),
  progress: ResultProgress(
    beforeCompletedAt: DateTime(2026, 7, 1),
    afterCompletedAt: DateTime(2026, 8, 20),
    areas: const [
      ResultProgressArea(
        label: 'Communication',
        beforeLevelName: 'Needs Support',
        afterLevelName: 'Emerging',
        beforeLevelInt: 0,
        afterLevelInt: 1,
      ),
    ],
  ),
);

HistorySummary _historySummary({
  required String childId,
  required String runId,
  required String sessionId,
}) {
  final pre = AssessmentRunHistory(
    run: AssessmentRunRecord(
      id: runId,
      childId: childId,
      type: 'pre',
      status: 'completed',
      startedAt: DateTime(2026, 7, 1),
      completedAt: DateTime(2026, 7, 1, 10),
    ),
    games: [
      RunGameRecord(
        gameId: 'match_it',
        gameName: 'Match It',
        score: 8,
        totalItems: 10,
        errorCount: 2,
        accuracy: 0.8,
        configLabel: 'private-config',
        endedAt: DateTime(2026, 7, 1, 10),
      ),
    ],
    overallAccuracy: 0.6,
    skills: const [
      SkillBreakdownEntry(area: 'Communication', label: 'Emerging'),
    ],
    recommendedModule: 'Copy Me',
    overallSummary: 'A parent-friendly summary.',
  );
  final post = AssessmentRunHistory(
    run: AssessmentRunRecord(
      id: '$runId-post',
      childId: childId,
      type: 'post',
      status: 'completed',
      startedAt: DateTime(2026, 8, 20),
      completedAt: DateTime(2026, 8, 20, 10),
    ),
    games: const [],
    overallAccuracy: 0.8,
    skills: const [],
    recommendedModule: null,
    overallSummary: null,
  );
  return HistorySummary(
    runs: [pre, post],
    comparison: ProgressComparison(
      pre: pre,
      post: post,
      areas: const [
        AreaComparisonRow(
          area: 'Communication',
          before: 'Emerging',
          after: 'Strength',
        ),
      ],
    ),
    completedModules: [
      CompletedModuleRecord(
        moduleId: 'private-module-id',
        moduleName: 'My Path',
        completedAt: DateTime(2026, 8, 25),
        status: 'completed',
        level: 0,
        maxLevel: 0,
        source: 'my_path',
        gameCount: 3,
      ),
    ],
    practiceSessions: [
      GameplaySession(
        id: sessionId,
        childId: childId,
        gameId: 'match_it',
        context: 'practice',
        score: 7,
        totalItems: 10,
        errorCount: 3,
        totalResponseTimeMs: 1000,
        startedAt: DateTime(2026, 8, 27),
        endedAt: DateTime(2026, 8, 27, 0, 5),
      ),
    ],
  );
}
