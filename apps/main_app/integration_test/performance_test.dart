import 'dart:ui';

import 'package:aumazing/features/questionnaire/parent_questionnaire.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_ui/shared_ui.dart';

const _e2eEnabled = bool.fromEnvironment('E2E_TEST_MODE');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'questionnaire interaction stays within the profile frame budget',
    (tester) async {
      expect(_e2eEnabled, isTrue);
      expect(
        kProfileMode,
        isTrue,
        reason: 'Performance evidence requires --profile.',
      );
      final timings = <FrameTiming>[];
      void timingsCallback(List<FrameTiming> values) => timings.addAll(values);
      binding.addTimingsCallback(timingsCallback);
      addTearDown(() => binding.removeTimingsCallback(timingsCallback));

      final startup = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ParentQuestionnaireScreen(
            assessmentType: 'pre',
            childId: 'performance-child',
            assessmentRunId: 'performance-run',
            saver:
                ({
                  required id,
                  required childId,
                  required assessmentRunId,
                  required questionnaireType,
                  required responses,
                }) async {},
            onDone: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      startup.stop();
      expect(startup.elapsedMilliseconds, lessThanOrEqualTo(500));

      for (final item in kParentQuestionnaireDraft.items) {
        final answer = find.byKey(
          Key('questionnaire.answer.${item.id}.sometimes'),
        );
        await tester.ensureVisible(answer);
        await tester.tap(answer);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(timings, isNotEmpty);
      final buildMs =
          timings
              .map((timing) => timing.buildDuration.inMicroseconds / 1000)
              .toList()
            ..sort();
      final rasterMs =
          timings
              .map((timing) => timing.rasterDuration.inMicroseconds / 1000)
              .toList()
            ..sort();
      final overBudget =
          timings
              .where((timing) => timing.totalSpan.inMicroseconds > 16667)
              .length;
      final overBudgetRatio = overBudget / timings.length;
      final buildP90 = _percentile(buildMs, 0.90);
      final rasterP90 = _percentile(rasterMs, 0.90);

      binding.reportData = {
        'device_requirement': 'physical Android device',
        'build_mode': 'profile',
        'startup_ms': startup.elapsedMilliseconds,
        'frame_count': timings.length,
        'build_p90_ms': buildP90,
        'raster_p90_ms': rasterP90,
        'over_budget_ratio': overBudgetRatio,
      };

      expect(buildP90, lessThanOrEqualTo(16.7));
      expect(rasterP90, lessThanOrEqualTo(16.7));
      expect(overBudgetRatio, lessThanOrEqualTo(0.01));
      expect(
        timings
            .map((timing) => timing.totalSpan.inMilliseconds)
            .reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(100),
      );
    },
  );
}

double _percentile(List<double> sorted, double percentile) {
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index];
}
