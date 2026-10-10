import 'dart:async';
import 'dart:convert';

import 'package:aumazing/features/questionnaire/observed_session.dart';
import 'package:aumazing/features/questionnaire/observer_intake_screen.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire_screen.dart';
import 'package:aumazing/features/questionnaire/session_observation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:questionnaire_core/questionnaire_core.dart';
import 'package:shared_ui/shared_ui.dart';

const _e2eEnabled = bool.fromEnvironment('E2E_TEST_MODE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'assessment intake, optional observation, and home questionnaire complete in order',
    (tester) async {
      expect(
        _e2eEnabled,
        isTrue,
        reason: 'Run with --dart-define=E2E_TEST_MODE=true.',
      );
      final saved = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: _JourneyHarness(saved: saved)),
      );

      await tester.tap(find.byKey(const Key('journey.begin')));
      await tester.pumpAndSettle();
      expect(find.text('Use previous answers'), findsOneWidget);
      expect(find.text('Update answers'), findsOneWidget);

      await _tapKey(tester, 'intake.reuse');
      await _tapKey(tester, 'intake.role.parent');
      expect(find.text('Rested'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('intake.sleep_today')),
        'Tired',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('intake.start')))
            .onPressed,
        isNotNull,
      );
      await _tapKey(tester, 'intake.start');
      await tester.pumpAndSettle();

      expect(find.text('Assessment games completed'), findsOneWidget);
      await tester.tap(find.byKey(const Key('journey.returnToParent')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('observation.optionalNote')), findsOneWidget);
      await tester.tap(find.byKey(const Key('observation.skip')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('questionnaire.optionalNote')),
        findsOneWidget,
      );
      for (final item in kParentQuestionnaireDraft.items) {
        await _tapKey(tester, 'questionnaire.answer.${item.id}.often');
      }
      await tester.tap(find.byKey(const Key('questionnaire.save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('journey.result')), findsOneWidget);
      expect(saved.map((row) => row['questionnaire_type']), [
        'pre_intake',
        'pre',
      ]);
      final intake = saved.first['responses'] as Map<String, dynamic>;
      expect(intake['background_mode'], 'reuse');
      expect(intake['answers'], {'school': 'SPED', 'sleep_today': 'Tired'});
      expect(intake['reused_question_ids'], ['school']);
      expect(
        (intake['answer_sources'] as Map)['school'],
        containsPair('completed_at', '2026-09-01T08:00:00.000Z'),
      );
      final home = saved.last['responses'] as Map<String, dynamic>;
      expect(home['answers'], hasLength(16));
      expect(home['domain_scores'], {
        'communication': 75.0,
        'play': 75.0,
        'social': 75.0,
        'attention': 75.0,
      });
    },
  );

  testWidgets('failed save stays retryable and optional form can be skipped', (
    tester,
  ) async {
    expect(_e2eEnabled, isTrue);
    var attempts = 0;
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ParentQuestionnaireScreen(
          assessmentType: 'post',
          childId: 'child-1',
          assessmentRunId: 'post-run-1',
          saver: ({
            required id,
            required childId,
            required assessmentRunId,
            required questionnaireType,
            required responses,
          }) async {
            attempts++;
            throw StateError('simulated isolated save failure');
          },
          onDone: (_) => finished = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final item in kParentQuestionnaireDraft.items) {
      await _tapKey(tester, 'questionnaire.answer.${item.id}.sometimes');
    }
    await tester.tap(find.byKey(const Key('questionnaire.save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(attempts, 1);
    expect(finished, isFalse);
    expect(
      find.text('Could not save your answers. Please try again.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('questionnaire.skip')));
    await tester.pump();
    expect(finished, isTrue);
  });

  testWidgets('repeated save input writes a completed questionnaire once', (
    tester,
  ) async {
    expect(_e2eEnabled, isTrue);
    final pendingSave = Completer<void>();
    var attempts = 0;
    var completions = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ParentQuestionnaireScreen(
          assessmentType: 'pre',
          childId: 'child-1',
          assessmentRunId: 'pre-run-1',
          saver: ({
            required id,
            required childId,
            required assessmentRunId,
            required questionnaireType,
            required responses,
          }) async {
            attempts++;
            await pendingSave.future;
          },
          onDone: (_) => completions++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final item in kParentQuestionnaireDraft.items) {
      await _tapKey(tester, 'questionnaire.answer.${item.id}.always');
    }
    final save = find.byKey(const Key('questionnaire.save'));
    await tester.tap(save);
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(attempts, 1);

    pendingSave.complete();
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(completions, 1);
  });
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

class _JourneyHarness extends StatefulWidget {
  const _JourneyHarness({required this.saved});

  final List<Map<String, dynamic>> saved;

  @override
  State<_JourneyHarness> createState() => _JourneyHarnessState();
}

class _JourneyHarnessState extends State<_JourneyHarness> {
  int _stage = 0;

  static const _intakeTemplate = ChoiceTemplate(
    key: 'e2e_intake',
    version: 3,
    status: 'validated',
    kind: TemplateKind.intake,
    title: 'Before your child starts',
    intro: 'Answer the current-session question anew.',
    questions: [
      TemplateQuestion(
        id: 'school',
        text: 'Current school setting',
        type: QuestionType.text,
      ),
      TemplateQuestion(
        id: 'sleep_today',
        text: 'How did your child sleep today?',
        type: QuestionType.text,
        timing: AnswerTiming.currentSession,
        required: true,
      ),
    ],
  );

  List<Map<String, dynamic>> get _previous => [
    {
      'questionnaire_type': 'pre_intake',
      'assessment_run_id': 'older-run',
      'completed_at': '2026-09-01T08:00:00.000Z',
      'responses': jsonEncode(
        IntakeRecord.answer(_intakeTemplate, ObserverRole.guardian, const {
          'school': 'SPED',
          'sleep_today': 'Rested',
        }).toResponses(_intakeTemplate),
      ),
    },
  ];

  Future<void> _save({
    required String id,
    required String childId,
    required String? assessmentRunId,
    required String questionnaireType,
    required Map<String, dynamic> responses,
  }) async {
    widget.saved.add({
      'id': id,
      'child_id': childId,
      'assessment_run_id': assessmentRunId,
      'questionnaire_type': questionnaireType,
      'responses': responses,
    });
  }

  Future<void> _begin() async {
    await Navigator.of(context).push<IntakeRecord>(
      MaterialPageRoute(
        builder:
            (_) => ObserverIntakeScreen(
              assessmentType: 'pre',
              childId: 'child-1',
              assessmentRunId: 'pre-run-1',
              template: _intakeTemplate,
              loader: (_) async => _previous,
              saver: _save,
            ),
      ),
    );
    if (mounted) setState(() => _stage = 1);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      0 => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('journey.begin'),
            onPressed: _begin,
            child: const Text('Begin assessment'),
          ),
        ),
      ),
      1 => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Assessment games completed'),
              FilledButton(
                key: const Key('journey.returnToParent'),
                onPressed: () => setState(() => _stage = 2),
                child: const Text('Return to parent'),
              ),
            ],
          ),
        ),
      ),
      2 => SessionObservationScreen(
        assessmentType: 'pre',
        childId: 'child-1',
        assessmentRunId: 'pre-run-1',
        gameIds: const ['copy_me', 'match_it'],
        loader: (_) async => const [],
        saver: _save,
        onDone: (_) => setState(() => _stage = 3),
      ),
      3 => ParentQuestionnaireScreen(
        assessmentType: 'pre',
        childId: 'child-1',
        assessmentRunId: 'pre-run-1',
        saver: _save,
        onDone: (_) => setState(() => _stage = 4),
      ),
      _ => const Scaffold(
        body: Center(child: Text('Results ready', key: Key('journey.result'))),
      ),
    };
  }
}
