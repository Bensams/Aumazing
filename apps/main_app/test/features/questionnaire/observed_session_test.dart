import 'dart:convert';

import 'package:aumazing/core/services/sync_service.dart';
import 'package:aumazing/features/questionnaire/observed_session.dart';
import 'package:aumazing/features/questionnaire/observer_intake_screen.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire.dart';
import 'package:aumazing/features/questionnaire/questionnaire_template_repository.dart';
import 'package:aumazing/features/questionnaire/session_observation_card.dart';
import 'package:aumazing/features/questionnaire/session_observation_screen.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questionnaire_core/questionnaire_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

typedef Saved = Map<String, dynamic>;

/// AUM-351 / AUM-352 — the observed assessment: the child plays while an
/// adult watches; the adult answers only before the child starts and after
/// they finish, with questions a practitioner can author in the portal.
void main() {
  Future<void> saverInto(
    List<Saved> into, {
    required String id,
    required String childId,
    required String? assessmentRunId,
    required String questionnaireType,
    required Map<String, dynamic> responses,
  }) async => into.add({
    'child_id': childId,
    'assessment_run_id': assessmentRunId,
    'questionnaire_type': questionnaireType,
    'responses': responses,
  });

  Map<String, dynamic> row(
    String type,
    String? runId,
    Map<String, dynamic> responses, {
    String completedAt = '2026-09-28T10:00:00',
  }) => {
    'questionnaire_type': type,
    'assessment_run_id': runId,
    'responses': jsonEncode(responses),
    'completed_at': completedAt,
  };

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
  }

  test('the app and the portal share one bundled home questionnaire', () {
    const app = kParentQuestionnaireDraft;
    expect(app.id, kDefaultHomeTemplate['template_key']);
    expect(app.title, kDefaultHomeTemplate['title']);
    expect(app.intro, kDefaultHomeTemplate['intro']);
    expect([
      for (final i in app.items)
        {'id': i.id, 'domain': i.domain.key, 'text': i.text},
    ], kDefaultHomeTemplate['items']);
  });

  group('records', () {
    test('an intake keeps who watched and a readable summary', () {
      final record = IntakeRecord.answer(
        kDefaultIntakeTemplate,
        ObserverRole.teacher,
        {
          'diagnosis': 'diagnosed',
          'school': 'sped',
          'therapies': ['speech'],
        },
      );
      final back =
          IntakeRecord.fromResponses(
            record.toResponses(kDefaultIntakeTemplate),
          )!;
      expect(back.role, ObserverRole.teacher);
      expect(back.answers['school'], 'sped');
      expect(
        back.headline,
        'Watched by: SPED teacher · Diagnosed with autism · '
        'SPED class or school · Therapy: Speech',
      );
    });

    test('an observation keeps what it said when it was saved', () {
      final record = ObservationRecord.answer(
        kDefaultObservationTemplate,
        role: ObserverRole.guardian,
        games: {
          'copy_me': {
            'understood': 'no',
            'help': 'hand',
            'mood': 'calm',
            'as_usual': 'usual',
          },
        },
        session: {'day': 'tired_or_sick', 'note': 'Sleepy after lunch'},
      );
      final responses = record.toResponses(kDefaultObservationTemplate);
      expect(responses['template_id'], 'aumazing_session_observation');
      final back = ObservationRecord.fromResponses(
        jsonDecode(jsonEncode(responses)) as Map<String, dynamic>,
      );
      expect(back.role, ObserverRole.guardian);
      expect(back.games['copy_me']!.flags, [
        'Did not understand the task',
        'Played with help (helped their hand)',
      ]);
      expect(back.sessionFlags, ['Not a typical day (tired or sick)']);
      expect(back.notes, ['Sleepy after lunch']);
    });
  });

  group('before your child starts', () {
    Future<(List<Saved>, List<Object?>)> open(
      WidgetTester tester, {
      List<Map<String, dynamic>> previous = const [],
      ChoiceTemplate? template,
    }) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final saved = <Saved>[];
      final popped = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () async {
                    popped.add(
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => ObserverIntakeScreen(
                                assessmentType: 'pre',
                                childId: 'child-1',
                                assessmentRunId: 'run-1',
                                template: template,
                                loader: (_) async => previous,
                                saver:
                                    ({
                                      required id,
                                      required childId,
                                      required assessmentRunId,
                                      required questionnaireType,
                                      required responses,
                                    }) => saverInto(
                                      saved,
                                      id: id,
                                      childId: childId,
                                      assessmentRunId: assessmentRunId,
                                      questionnaireType: questionnaireType,
                                      responses: responses,
                                    ),
                              ),
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (saved, popped);
    }

    bool startEnabled(WidgetTester tester) =>
        tester
            .widget<FilledButton>(find.byKey(const Key('intake.start')))
            .onPressed !=
        null;

    /// Start is never greyed out: tapped too early, it saves nothing and
    /// outlines what is still missing.
    Future<void> expectStartHeld(
      WidgetTester tester,
      List<Object?> saved,
    ) async {
      await tapKey(tester, 'intake.start');
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.text('Answer this to start the games.'), findsWidgets);
    }

    testWidgets('tells the adult to watch and not to interrupt', (
      tester,
    ) async {
      await open(tester);
      expect(find.textContaining('watch them play'), findsOneWidget);
      expect(find.textContaining('Nothing will interrupt'), findsOneWidget);
    });

    testWidgets('needs only who is watching; background is optional', (
      tester,
    ) async {
      final (saved, popped) = await open(tester);
      expect(find.text('Choose who is watching to start.'), findsOneWidget);

      // Start stays tappable; too early, it points at what is missing.
      expect(startEnabled(tester), isTrue);
      await tapKey(tester, 'intake.start');
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(popped, isEmpty);
      expect(find.text('Answer this to start the games.'), findsOneWidget);

      await tapKey(tester, 'intake.role.teacher');
      expect(find.text('Answer this to start the games.'), findsNothing);
      expect(
        find.textContaining('Watching: SPED teacher · 0 of 3 answered'),
        findsOneWidget,
      );
      await tapKey(tester, 'intake.diagnosis.evaluating');
      await tapKey(tester, 'intake.school.kinder');
      await tapKey(tester, 'intake.therapies.speech');
      await tapKey(tester, 'intake.start');
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single['questionnaire_type'], 'pre_intake');
      expect(saved.single['assessment_run_id'], 'run-1');
      final responses = saved.single['responses'] as Map<String, dynamic>;
      expect(responses['observer_role'], 'teacher');
      expect(responses['template_id'], 'aumazing_observer_intake');
      expect(responses['answers'], {
        'diagnosis': 'evaluating',
        'school': 'kinder',
        'therapies': ['speech'],
      });
      expect((popped.single as IntakeRecord).role, ObserverRole.teacher);
    });

    testWidgets('"None" clears the other therapies', (tester) async {
      final (saved, _) = await open(tester);
      await tapKey(tester, 'intake.role.parent');
      await tapKey(tester, 'intake.therapies.speech');
      await tapKey(tester, 'intake.therapies.none');
      await tapKey(tester, 'intake.start');
      await tester.pumpAndSettle();
      expect((saved.single['responses'] as Map<String, dynamic>)['answers'], {
        'therapies': ['none'],
      });
    });

    testWidgets(
      'explicit reuse retains provenance and asks who watches today',
      (tester) async {
        final (saved, _) = await open(
          tester,
          previous: [
            row(
              'pre_intake',
              'run-0',
              IntakeRecord.answer(
                kDefaultIntakeTemplate,
                ObserverRole.guardian,
                {'school': 'grade_1', 'retired_question': 'x'},
              ).toResponses(kDefaultIntakeTemplate),
            ),
          ],
        );
        await expectStartHeld(tester, saved);
        expect(find.byKey(const Key('intake.school.grade_1')), findsNothing);
        await tapKey(tester, 'intake.reuse');
        await tapKey(tester, 'intake.role.parent');
        await tapKey(tester, 'intake.start');
        await tester.pumpAndSettle();
        final responses = saved.single['responses'] as Map<String, dynamic>;
        expect(responses['observer_role'], 'parent');
        expect(responses['background_mode'], 'reuse');
        expect(responses['reused_question_ids'], ['school']);
        expect(
          (responses['answer_sources'] as Map)['school'],
          containsPair('completed_at', '2026-09-28T10:00:00'),
        );
        // A question the current template no longer asks is not carried over.
        expect(responses['answers'], {'school': 'grade_1'});
      },
    );

    testWidgets(
      'update edits background and keeps untouched answers labeled earlier',
      (tester) async {
        final (saved, _) = await open(
          tester,
          previous: [
            row(
              'pre_intake',
              'run-0',
              IntakeRecord.answer(kDefaultIntakeTemplate, ObserverRole.parent, {
                'school': 'grade_1',
                'diagnosis': 'diagnosed',
              }).toResponses(kDefaultIntakeTemplate),
            ),
          ],
        );
        await tapKey(tester, 'intake.update');
        await tapKey(tester, 'intake.role.guardian');
        await tapKey(tester, 'intake.school.sped');
        await tapKey(tester, 'intake.start');
        await tester.pumpAndSettle();
        final responses = saved.single['responses'] as Map<String, dynamic>;
        expect(responses['background_mode'], 'update');
        expect(responses['answers'], {
          'school': 'sped',
          'diagnosis': 'diagnosed',
        });
        expect(responses['reused_question_ids'], ['diagnosis']);
        expect(
          (responses['answer_sources'] as Map).containsKey('school'),
          isFalse,
        );
      },
    );

    testWidgets(
      'session questions are asked anew even when background is reused',
      (tester) async {
        const template = ChoiceTemplate(
          key: 'intake',
          version: 1,
          status: 'validated',
          kind: TemplateKind.intake,
          title: 'Before play',
          intro: '',
          questions: [
            TemplateQuestion(
              id: 'school',
              text: 'School',
              type: QuestionType.text,
            ),
            TemplateQuestion(
              id: 'sleep',
              text: 'Sleep today',
              type: QuestionType.text,
              timing: AnswerTiming.currentSession,
              required: true,
            ),
          ],
        );
        final (saved, _) = await open(
          tester,
          template: template,
          previous: [
            row(
              'pre_intake',
              'older',
              IntakeRecord.answer(template, ObserverRole.parent, {
                'school': 'Kinder',
                'sleep': 'Good',
              }).toResponses(template),
            ),
          ],
        );
        await tapKey(tester, 'intake.reuse');
        await tapKey(tester, 'intake.role.parent');
        await expectStartHeld(tester, saved);
        expect(find.text('Good'), findsNothing);
        await tester.enterText(find.byKey(const Key('intake.sleep')), 'Tired');
        await tester.pump();
        await tapKey(tester, 'intake.start');
        await tester.pumpAndSettle();
        final data = saved.single['responses'] as Map;
        expect(data['background_answers'], {'school': 'Kinder'});
        expect(data['session_answers'], {'sleep': 'Tired'});
        expect(data['reused_question_ids'], ['school']);
      },
    );

    testWidgets('asks a practitioner\'s own questions', (tester) async {
      const custom = ChoiceTemplate(
        key: 'sped_intake',
        version: 2,
        status: 'validated',
        kind: TemplateKind.intake,
        title: 'Bago magsimula',
        intro: 'Panoorin ang bata.',
        questions: [
          TemplateQuestion(
            id: 'language',
            text: 'Language at home',
            type: QuestionType.single,
            required: true,
            options: [
              ChoiceOption(id: 'fil', label: 'Filipino'),
              ChoiceOption(id: 'en', label: 'English'),
            ],
          ),
        ],
      );
      final (saved, _) = await open(tester, template: custom);
      expect(find.text('Bago magsimula'), findsOneWidget);
      expect(find.text('Panoorin ang bata.'), findsOneWidget);
      expect(find.byKey(const Key('intake.diagnosis.diagnosed')), findsNothing);

      await tapKey(tester, 'intake.role.parent');
      // A required practitioner question holds the start.
      await expectStartHeld(tester, saved);
      await tapKey(tester, 'intake.language.fil');
      await tapKey(tester, 'intake.start');
      await tester.pumpAndSettle();
      final responses = saved.single['responses'] as Map<String, dynamic>;
      expect(responses['template_id'], 'sped_intake');
      expect(responses['template_version'], 2);
      expect(responses['template_status'], 'validated');
      expect(responses['summary'], ['Filipino']);
    });

    testWidgets('Skip starts the games without saving', (tester) async {
      final (saved, popped) = await open(tester);
      await tester.tap(find.byKey(const Key('intake.skip')));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(popped, [null]);
    });
  });

  group('what did you see', () {
    Future<(List<Saved>, List<String>)> open(
      WidgetTester tester, {
      List<Map<String, dynamic>> rows = const [],
    }) async {
      await tester.binding.setSurfaceSize(const Size(900, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final saved = <Saved>[];
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SessionObservationScreen(
            assessmentType: 'post',
            childId: 'child-1',
            assessmentRunId: 'run-2',
            gameIds: const ['copy_me', 'match_it'],
            onDone: (_) => events.add('done'),
            loader: (_) async => rows,
            saver:
                ({
                  required id,
                  required childId,
                  required assessmentRunId,
                  required questionnaireType,
                  required responses,
                }) => saverInto(
                  saved,
                  id: id,
                  childId: childId,
                  assessmentRunId: assessmentRunId,
                  questionnaireType: questionnaireType,
                  responses: responses,
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (saved, events);
    }

    Future<void> answerGame(WidgetTester tester, String game) async {
      await tapKey(tester, 'observation.details.$game');
      await tapKey(tester, 'observation.$game.understood.yes');
      await tapKey(tester, 'observation.$game.help.showed');
      await tapKey(tester, 'observation.$game.mood.calm');
      await tapKey(tester, 'observation.$game.as_usual.usual');
    }

    bool saveEnabled(WidgetTester tester) =>
        tester
            .widget<FilledButton>(find.byKey(const Key('observation.save')))
            .onPressed !=
        null;

    testWidgets(
      'starts short and adds details only for a selected played game',
      (tester) async {
        await open(tester);
        expect(find.byKey(const Key('observation.game.copy_me')), findsNothing);
        await tapKey(tester, 'observation.details.copy_me');
        expect(
          find.byKey(const Key('observation.game.copy_me')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('observation.game.match_it')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('observation.game.do_what_i_say')),
          findsNothing,
        );
      },
    );

    testWidgets('Save waits for every game and the day', (tester) async {
      final (saved, events) = await open(
        tester,
        rows: [
          row(
            'post_intake',
            'run-2',
            const IntakeRecord(
              role: ObserverRole.therapist,
            ).toResponses(kDefaultIntakeTemplate),
          ),
          // Another run's intake must not be taken for this one.
          row(
            'post_intake',
            'run-1',
            const IntakeRecord(
              role: ObserverRole.parent,
            ).toResponses(kDefaultIntakeTemplate),
          ),
        ],
      );
      expect(find.text('Answering as: Therapist'), findsOneWidget);

      await answerGame(tester, 'copy_me');
      expect(saveEnabled(tester), isFalse);
      await answerGame(tester, 'match_it');
      expect(saveEnabled(tester), isFalse);
      await tapKey(tester, 'observation.session.day.normal');
      await tapKey(tester, 'observation.session.session_help.some');
      await tapKey(tester, 'observation.session.session_mood.calm');
      expect(saveEnabled(tester), isTrue);

      await tester.enterText(
        find.byKey(const Key('observation.session.note')),
        'Liked the matching game',
      );
      await tapKey(tester, 'observation.save');
      await tester.pumpAndSettle();

      expect(events, ['done']);
      expect(saved.single['questionnaire_type'], 'post_observation');
      expect(saved.single['assessment_run_id'], 'run-2');
      final responses = saved.single['responses'] as Map<String, dynamic>;
      expect(responses['observer_role'], 'therapist');
      final games = responses['games'] as Map;
      expect((games['match_it'] as Map)['answers'], {
        'understood': 'yes',
        'help': 'showed',
        'mood': 'calm',
        'as_usual': 'usual',
      });
      expect((games['match_it'] as Map)['flags'], [
        'Played with help (pointed or showed)',
      ]);
      final session = responses['session'] as Map;
      expect(session['answers'], {
        'day': 'normal',
        'session_help': 'some',
        'session_mood': 'calm',
        'note': 'Liked the matching game',
      });
      expect(session['notes'], ['Liked the matching game']);
    });

    testWidgets(
      'check-in can save without game details; deselection removes hidden answers',
      (tester) async {
        final (saved, events) = await open(tester);
        await answerGame(tester, 'copy_me');
        await tapKey(tester, 'observation.details.copy_me');
        await tapKey(tester, 'observation.session.session_help.none');
        await tapKey(tester, 'observation.session.session_mood.excited');
        await tapKey(tester, 'observation.session.day.normal');
        await tapKey(tester, 'observation.save');
        await tester.pumpAndSettle();
        expect(events, ['done']);
        final data = saved.single['responses'] as Map;
        expect(data['games'], isEmpty);
        expect((data['session'] as Map)['answers'], {
          'session_help': 'none',
          'session_mood': 'excited',
          'day': 'normal',
        });
        expect(data.containsKey('background_answers'), isFalse);
      },
    );

    testWidgets('Skip for now carries on without saving', (tester) async {
      final (saved, events) = await open(tester);
      await tester.tap(find.byKey(const Key('observation.skip')));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(events, ['done']);
    });
  });

  group('the results card', () {
    AssessmentResult result(String gameId, int score) => AssessmentResult(
      id: 'r-$gameId',
      childId: 'child-1',
      assessmentRunId: 'run-1',
      type: 'pre',
      gameId: gameId,
      score: score,
      totalItems: 10,
      errorCount: 0,
      avgResponseTimeMs: 1200,
      completedAt: DateTime(2026, 9, 28),
    );

    Future<void> pumpCard(
      WidgetTester tester,
      List<Map<String, dynamic>> rows,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SessionObservationCard(
                childId: 'child-1',
                assessmentRunId: 'run-1',
                results: [result('copy_me', 7), result('match_it', 9)],
                loader: (_) async => rows,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('puts what was seen beside each score, with flags', (
      tester,
    ) async {
      await pumpCard(tester, [
        row(
          'pre_intake',
          'run-1',
          IntakeRecord.answer(kDefaultIntakeTemplate, ObserverRole.teacher, {
            'school': 'sped',
          }).toResponses(kDefaultIntakeTemplate),
        ),
        row(
          'pre_observation',
          'run-1',
          ObservationRecord.answer(
            kDefaultObservationTemplate,
            role: ObserverRole.teacher,
            games: {
              'copy_me': {
                'understood': 'partly',
                'help': 'hand',
                'mood': 'calm',
                'as_usual': 'usual',
              },
              'match_it': {
                'understood': 'yes',
                'help': 'none',
                'mood': 'excited',
                'as_usual': 'better',
              },
            },
            session: {'day': 'distracted'},
          ).toResponses(kDefaultObservationTemplate),
        ),
      ]);

      expect(find.text('What the SPED teacher saw'), findsOneWidget);
      expect(
        find.text('Watched by: SPED teacher · SPED class or school'),
        findsOneWidget,
      );
      expect(find.text('Score 7/10'), findsOneWidget);
      expect(find.text('Score 9/10'), findsOneWidget);
      expect(
        find.text('Understood: Partly · Helped their hand · Calm · As usual'),
        findsOneWidget,
      );
      expect(find.text('Played with help (helped their hand)'), findsOneWidget);
      expect(
        find.text('Not a typical day (new place or distracted)'),
        findsOneWidget,
      );
    });

    testWidgets('ignores another run and shows nothing without answers', (
      tester,
    ) async {
      await pumpCard(tester, [
        row(
          'pre_observation',
          'run-9',
          const ObservationRecord(
            games: {},
          ).toResponses(kDefaultObservationTemplate),
        ),
      ]);
      expect(find.byKey(const Key('session-observation-card')), findsNothing);
    });
  });

  group('templates from the portal', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Map<String, dynamic> templateRow(
      TemplateKind kind,
      String type,
      List<Map<String, Object?>> items,
    ) => {
      'template_key': 'portal_template',
      'version': 3,
      'kind': kind.key,
      'questionnaire_type': type,
      'title': 'From the portal',
      'intro': '',
      'items': items,
      'status': 'draft',
    };

    const noteOnly = [
      {'id': 'note', 'text': 'Anything?', 'type': 'text'},
    ];

    test('the active template of the right kind is used', () async {
      final repo = QuestionnaireTemplateRepository(
        choiceFetcher:
            (kind, type) async => [
              templateRow(TemplateKind.home, 'both', const []),
              templateRow(TemplateKind.intake, 'both', noteOnly),
            ],
      );
      final intake = await repo.choiceTemplateFor(TemplateKind.intake, 'pre');
      expect(intake.key, 'portal_template');
      expect(intake.version, 3);
    });

    test(
      'a broken or missing template falls back to the bundled one',
      () async {
        final broken = QuestionnaireTemplateRepository(
          choiceFetcher:
              (kind, type) async => [
                templateRow(TemplateKind.observation, 'pre', const []),
              ],
        );
        // An empty template cannot provide a check-in.
        expect(
          (await broken.choiceTemplateFor(TemplateKind.observation, 'pre')).key,
          kDefaultObservationTemplate.key,
        );
        final none = QuestionnaireTemplateRepository(
          choiceFetcher: (kind, type) async => const [],
        );
        expect(
          (await none.choiceTemplateFor(TemplateKind.intake, 'post')).key,
          kDefaultIntakeTemplate.key,
        );
      },
    );

    test('the last template seen is used offline', () async {
      final online = QuestionnaireTemplateRepository(
        choiceFetcher:
            (kind, type) async => [
              templateRow(TemplateKind.intake, 'pre', noteOnly),
            ],
      );
      await online.choiceTemplateFor(TemplateKind.intake, 'pre');
      final offline = QuestionnaireTemplateRepository(
        choiceFetcher: (kind, type) async => throw Exception('offline'),
      );
      expect(
        (await offline.choiceTemplateFor(TemplateKind.intake, 'pre')).key,
        'portal_template',
      );
    });

    test('the home questionnaire ignores the other kinds', () {
      expect(
        QuestionnaireTemplateRepository.pickActive([
          templateRow(TemplateKind.observation, 'pre', noteOnly),
        ], 'pre'),
        isNull,
      );
      expect(
        QuestionnaireTemplateRepository.pickActive([
          {'questionnaire_type': 'pre', 'template_key': 'old_row'},
        ], 'pre')?['template_key'],
        'old_row',
      );
    });
  });

  group('sync', () {
    Map<String, dynamic> local(Map<String, dynamic> responses) => {
      'id': 'q-1',
      'child_id': 'child-1',
      'assessment_run_id': 'run-1',
      'questionnaire_type': 'pre_observation',
      'responses': jsonEncode(responses),
      'completed_at': '2026-09-28T10:00:00',
    };

    test('records who observed as completed_by_role', () {
      for (final role in ObserverRole.values) {
        final row = SyncService.mapQuestionnaireToSupabase(
          local({'observer_role': role.key}),
        );
        expect(row['completed_by_role'], role.key);
      }
    });

    test('falls back to parent without a known observer', () {
      expect(
        SyncService.mapQuestionnaireToSupabase(local({}))['completed_by_role'],
        'parent',
      );
      expect(
        SyncService.mapQuestionnaireToSupabase(
          local({'observer_role': 'neighbour'}),
        )['completed_by_role'],
        'parent',
      );
    });
  });
}
