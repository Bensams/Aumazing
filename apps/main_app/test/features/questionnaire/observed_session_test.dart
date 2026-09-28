import 'dart:convert';

import 'package:aumazing/core/services/sync_service.dart';
import 'package:aumazing/features/questionnaire/observed_session.dart';
import 'package:aumazing/features/questionnaire/observer_intake_screen.dart';
import 'package:aumazing/features/questionnaire/session_observation_card.dart';
import 'package:aumazing/features/questionnaire/session_observation_screen.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// AUM-351 — the observed assessment: the child plays while an adult watches;
/// the adult answers only before the child starts and after they finish.
typedef Saved = Map<String, dynamic>;

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

  group('the model', () {
    test('an intake round-trips and summarises the background', () {
      const intake = ObserverIntake(
        role: ObserverRole.teacher,
        diagnosis: DiagnosisStatus.diagnosed,
        school: SchoolLevel.sped,
        therapies: {Therapy.speech, Therapy.occupational},
      );
      final back = ObserverIntake.fromResponses(intake.toResponses())!;
      expect(back.role, ObserverRole.teacher);
      expect(back.diagnosis, DiagnosisStatus.diagnosed);
      expect(back.school, SchoolLevel.sped);
      expect(back.therapies, {Therapy.speech, Therapy.occupational});
      expect(
        back.summary,
        'Watched by: SPED teacher · Diagnosed with autism · '
        'SPED class or school · Therapy: Speech, Occupational',
      );
    });

    test('"prefer not to say" and "no therapy" stay out of the summary', () {
      const intake = ObserverIntake(
        role: ObserverRole.parent,
        diagnosis: DiagnosisStatus.preferNotToSay,
        therapies: {Therapy.none},
      );
      expect(intake.summary, 'Watched by: Parent');
    });

    test('a game flags help, confusion, upset and a worse-than-usual try', () {
      const calm = GameObservation(
        understood: Understood.yes,
        help: HelpGiven.told,
        mood: ChildMood.calm,
        asUsual: AsUsual.usual,
      );
      expect(calm.flags, isEmpty, reason: 'a spoken reminder is not a flag');

      const hard = GameObservation(
        understood: Understood.no,
        help: HelpGiven.hand,
        mood: ChildMood.upset,
        asUsual: AsUsual.worse,
      );
      expect(hard.flags, [
        'Played with help (helped their hand)',
        'Did not understand the task',
        'Was frustrated or upset',
        'Worse than usual',
      ]);
    });

    test('an observation is complete only with every game and the day', () {
      const done = GameObservation(
        understood: Understood.yes,
        help: HelpGiven.none,
        mood: ChildMood.calm,
        asUsual: AsUsual.usual,
      );
      expect(
        const SessionObservation(games: {'copy_me': done}).complete,
        isFalse,
      );
      expect(
        const SessionObservation(
          games: {'copy_me': done, 'match_it': GameObservation()},
          day: SessionDay.normal,
        ).complete,
        isFalse,
      );
      const full = SessionObservation(
        games: {'copy_me': done},
        day: SessionDay.tiredOrSick,
        role: ObserverRole.guardian,
        note: '  Sleepy after lunch  ',
      );
      expect(full.complete, isTrue);
      expect(full.dayFlag, 'Not a typical day (tired or sick)');

      final back = SessionObservation.fromResponses(full.toResponses());
      expect(back.role, ObserverRole.guardian);
      expect(back.games['copy_me']!.complete, isTrue);
      expect(back.note, 'Sleepy after lunch');
    });
  });

  group('before your child starts', () {
    Future<(List<Saved>, List<Object?>)> open(
      WidgetTester tester, {
      List<Map<String, dynamic>> previous = const [],
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

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }

    bool startEnabled(WidgetTester tester) =>
        tester
            .widget<FilledButton>(find.byKey(const Key('intake.start')))
            .onPressed !=
        null;

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
      expect(startEnabled(tester), isFalse);

      await tapKey(tester, 'intake.role.teacher');
      expect(startEnabled(tester), isTrue);
      await tapKey(tester, 'intake.diagnosis.evaluating');
      await tapKey(tester, 'intake.school.kinder');
      await tapKey(tester, 'intake.therapy.speech');
      await tapKey(tester, 'intake.start');
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single['questionnaire_type'], 'pre_intake');
      expect(saved.single['assessment_run_id'], 'run-1');
      final responses = saved.single['responses'] as Map<String, dynamic>;
      expect(responses['observer_role'], 'teacher');
      expect(responses['diagnosis'], 'evaluating');
      expect(responses['school'], 'kinder');
      expect(responses['therapies'], ['speech']);
      expect((popped.single as ObserverIntake).role, ObserverRole.teacher);
    });

    testWidgets('"None" clears the other therapies and the other way round', (
      tester,
    ) async {
      final (saved, _) = await open(tester);
      await tapKey(tester, 'intake.role.parent');
      await tapKey(tester, 'intake.therapy.speech');
      await tapKey(tester, 'intake.therapy.none');
      await tapKey(tester, 'intake.start');
      await tester.pumpAndSettle();
      expect(
        (saved.single['responses'] as Map<String, dynamic>)['therapies'],
        ['none'],
      );
    });

    testWidgets('answers from last time are filled in', (tester) async {
      final (saved, _) = await open(
        tester,
        previous: [
          row('pre_intake', 'run-0', const ObserverIntake(
            role: ObserverRole.guardian,
            school: SchoolLevel.grade1,
          ).toResponses()),
        ],
      );
      expect(startEnabled(tester), isTrue);
      await tapKey(tester, 'intake.start');
      await tester.pumpAndSettle();
      final responses = saved.single['responses'] as Map<String, dynamic>;
      expect(responses['observer_role'], 'guardian');
      expect(responses['school'], 'grade_1');
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
      await tester.binding.setSurfaceSize(const Size(900, 2400));
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

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }

    Future<void> answerGame(WidgetTester tester, String game) async {
      await tapKey(tester, 'observation.$game.understood.yes');
      await tapKey(tester, 'observation.$game.help.showed');
      await tapKey(tester, 'observation.$game.mood.calm');
      await tapKey(tester, 'observation.$game.usual.usual');
    }

    bool saveEnabled(WidgetTester tester) =>
        tester
            .widget<FilledButton>(find.byKey(const Key('observation.save')))
            .onPressed !=
        null;

    testWidgets('asks about each game the child played', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('observation.game.copy_me')), findsOneWidget);
      expect(find.byKey(const Key('observation.game.match_it')), findsOneWidget);
      expect(
        find.byKey(const Key('observation.game.do_what_i_say')),
        findsNothing,
      );
    });

    testWidgets('Save waits for every game and the day', (tester) async {
      final (saved, events) = await open(
        tester,
        rows: [
          row('post_intake', 'run-2', const ObserverIntake(
            role: ObserverRole.therapist,
          ).toResponses()),
          // Another run's intake must not be taken for this one.
          row('post_intake', 'run-1', const ObserverIntake(
            role: ObserverRole.parent,
          ).toResponses()),
        ],
      );
      expect(find.text('Answering as: Therapist'), findsOneWidget);

      await answerGame(tester, 'copy_me');
      expect(saveEnabled(tester), isFalse);
      await answerGame(tester, 'match_it');
      expect(saveEnabled(tester), isFalse);
      await tapKey(tester, 'observation.day.normal');
      expect(saveEnabled(tester), isTrue);

      await tester.enterText(
        find.byKey(const Key('observation.note')),
        'Liked the matching game',
      );
      await tapKey(tester, 'observation.save');
      await tester.pumpAndSettle();

      expect(events, ['done']);
      expect(saved.single['questionnaire_type'], 'post_observation');
      expect(saved.single['assessment_run_id'], 'run-2');
      final responses = saved.single['responses'] as Map<String, dynamic>;
      expect(responses['observer_role'], 'therapist');
      expect(responses['day'], 'normal');
      expect(responses['note'], 'Liked the matching game');
      expect((responses['games'] as Map)['match_it'], {
        'understood': 'yes',
        'help': 'showed',
        'mood': 'calm',
        'as_usual': 'usual',
      });
    });

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
        row('pre_intake', 'run-1', const ObserverIntake(
          role: ObserverRole.teacher,
          school: SchoolLevel.sped,
        ).toResponses()),
        row('pre_observation', 'run-1', const SessionObservation(
          role: ObserverRole.teacher,
          day: SessionDay.distracted,
          games: {
            'copy_me': GameObservation(
              understood: Understood.partly,
              help: HelpGiven.hand,
              mood: ChildMood.calm,
              asUsual: AsUsual.usual,
            ),
            'match_it': GameObservation(
              understood: Understood.yes,
              help: HelpGiven.none,
              mood: ChildMood.excited,
              asUsual: AsUsual.better,
            ),
          },
        ).toResponses()),
      ]);

      expect(find.text('What the SPED teacher saw'), findsOneWidget);
      expect(
        find.text('Watched by: SPED teacher · SPED class or school'),
        findsOneWidget,
      );
      expect(find.text('Score 7/10'), findsOneWidget);
      expect(find.text('Score 9/10'), findsOneWidget);
      expect(
        find.text('Played with help (helped their hand)'),
        findsOneWidget,
      );
      expect(
        find.text('Not a typical day (new place or distracted)'),
        findsOneWidget,
      );
    });

    testWidgets('ignores another run and shows nothing without answers', (
      tester,
    ) async {
      await pumpCard(tester, [
        row('pre_observation', 'run-9', const SessionObservation(
          games: {},
          day: SessionDay.normal,
        ).toResponses()),
      ]);
      expect(find.byKey(const Key('session-observation-card')), findsNothing);
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
