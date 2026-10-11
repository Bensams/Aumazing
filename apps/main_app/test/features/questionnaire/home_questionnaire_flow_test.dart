import 'package:aumazing/features/questionnaire/home_questionnaire_flow.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire_screen.dart';
import 'package:aumazing/features/questionnaire/questionnaire_template_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'home reports are due only at post-assessments, not the pre-assessment or ordinary play',
    () {
      expect(
        HomeQuestionnaireFlow.shouldCollect(
          assessmentType: 'post',
          assessmentRunId: 'new',
          rows: const [],
        ),
        isTrue,
      );
      // The "before" is asked at child setup instead (AUM-364).
      expect(
        HomeQuestionnaireFlow.shouldCollect(
          assessmentType: 'pre',
          assessmentRunId: 'new',
          rows: const [],
        ),
        isFalse,
      );
      expect(
        HomeQuestionnaireFlow.shouldCollect(
          assessmentType: 'follow_up',
          assessmentRunId: 'game',
          rows: const [],
        ),
        isFalse,
      );
      expect(
        HomeQuestionnaireFlow.shouldCollect(
          assessmentType: 'post',
          assessmentRunId: null,
          rows: const [],
        ),
        isFalse,
      );
    },
  );
  test(
    'old versions stay attached to their run; only a new assessment asks again',
    () {
      final rows = [
        {
          'questionnaire_type': 'post',
          'assessment_run_id': 'old',
          'responses': {'template_version': 1},
        },
      ];
      expect(
        HomeQuestionnaireFlow.shouldCollect(
          assessmentType: 'post',
          assessmentRunId: 'old',
          rows: rows,
        ),
        isFalse,
      );
      expect(
        HomeQuestionnaireFlow.shouldCollect(
          assessmentType: 'post',
          assessmentRunId: 'new',
          rows: rows,
        ),
        isTrue,
      );
    },
  );
  testWidgets(
    'an existing home report bypasses the form even after a template change',
    (tester) async {
      var templateFetches = 0;
      var finished = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => TextButton(
                  child: const Text('Finish'),
                  onPressed:
                      () => HomeQuestionnaireFlow.show(
                        context,
                        assessmentType: 'post',
                        childId: 'child',
                        assessmentRunId: 'run',
                        loader:
                            (_) async => [
                              {
                                'questionnaire_type': 'post',
                                'assessment_run_id': 'run',
                                'responses': {'template_version': 1},
                              },
                            ],
                        repository: QuestionnaireTemplateRepository(
                          fetcher: (_) async {
                            templateFetches++;
                            return [];
                          },
                        ),
                        onDone: (_) {
                          finished = true;
                        },
                      ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(templateFetches, 0);
      expect(find.byType(ParentQuestionnaireScreen), findsNothing);
    },
  );
  testWidgets(
    'skipping the home report still opens the results and summary route',
    (tester) async {
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => TextButton(
                  child: const Text('Finish assessment'),
                  onPressed:
                      () => HomeQuestionnaireFlow.show(
                        context,
                        assessmentType: 'post',
                        childId: 'child',
                        assessmentRunId: 'run',
                        loader: (_) async => [],
                        repository: QuestionnaireTemplateRepository(
                          fetcher: (_) async => [],
                        ),
                        saver: ({
                          required id,
                          required childId,
                          required assessmentRunId,
                          required questionnaireType,
                          required responses,
                        }) async {
                          saved = true;
                        },
                        onDone:
                            (next) => Navigator.of(next).pushReplacement(
                              MaterialPageRoute(
                                builder:
                                    (_) => const Scaffold(
                                      body: Text('Game results and summary'),
                                    ),
                              ),
                            ),
                      ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Finish assessment'));
      await tester.pumpAndSettle();
      expect(find.byType(ParentQuestionnaireScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('questionnaire.skip')));
      await tester.pumpAndSettle();
      expect(find.text('Game results and summary'), findsOneWidget);
      expect(saved, isFalse);
    },
  );
}
