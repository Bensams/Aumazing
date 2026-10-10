import 'package:aumazing/features/questionnaire/observer_intake_screen.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('assessment forms remain reachable across supported layouts', (
    tester,
  ) async {
    for (final configuration in const [
      (Size(360, 800), 1.0),
      (Size(800, 360), 1.0),
      (Size(800, 1280), 1.3),
      (Size(1280, 800), 2.0),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = configuration.$1;
      tester.platformDispatcher.textScaleFactorTestValue = configuration.$2;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ParentQuestionnaireScreen(
            assessmentType: 'pre',
            childId: 'quality-child',
            assessmentRunId: 'quality-run',
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
      expect(
        tester.takeException(),
        isNull,
        reason: '${configuration.$1} at ${configuration.$2}x text',
      );
      expect(find.byKey(const Key('questionnaire.skip')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('questionnaire.save')));
      expect(find.byKey(const Key('questionnaire.save')), findsOneWidget);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('intake controls satisfy automated accessibility guidelines', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1280);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ObserverIntakeScreen(
            assessmentType: 'pre',
            childId: 'quality-child',
            assessmentRunId: 'quality-run',
            loader: (_) async => const [],
            saver:
                ({
                  required id,
                  required childId,
                  required assessmentRunId,
                  required questionnaireType,
                  required responses,
                }) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      semantics.dispose();
    }
  });
}
