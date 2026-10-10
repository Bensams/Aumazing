import 'dart:convert';

import 'package:aumazing/features/questionnaire/intake_background.dart';
import 'package:aumazing/features/questionnaire/observed_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questionnaire_core/questionnaire_core.dart';

void main() {
  ChoiceTemplate template({
    int version = 1,
    String wording = 'School',
    String option = 'Kinder',
  }) => ChoiceTemplate(
    key: 'custom',
    version: version,
    status: 'validated',
    kind: TemplateKind.intake,
    title: 'Before',
    intro: '',
    questions: [
      TemplateQuestion(
        id: 'school',
        text: wording,
        type: QuestionType.single,
        options: [
          ChoiceOption(id: 'k', label: option),
          const ChoiceOption(id: 's', label: 'SPED'),
        ],
      ),
      const TemplateQuestion(
        id: 'today',
        text: 'Today',
        type: QuestionType.text,
        timing: AnswerTiming.currentSession,
      ),
    ],
  );
  Map<String, dynamic> row(Map<String, dynamic> data) => {
    'id': 'earlier',
    'questionnaire_type': 'pre_intake',
    'completed_at': '2026-09-01T10:00:00',
    'responses': jsonEncode(data),
  };
  Map<String, dynamic> responses(ChoiceTemplate t) => IntakeRecord.answer(
    t,
    ObserverRole.parent,
    {'school': 'k', 'today': 'Tired'},
  ).toResponses(t);

  test('compatible background can cross a version; current session cannot', () {
    final previous =
        IntakeBackground.latest([
          row(responses(template())),
        ], template(version: 2))!;
    expect(previous.answers, {'school': 'k'});
    expect((previous.sources['school'] as Map)['template_version'], 1);
    expect((previous.sources['school'] as Map)['questionnaire_id'], 'earlier');
  });
  test('reworded questions and relabeled choices need new answers', () {
    final rows = [row(responses(template()))];
    expect(
      IntakeBackground.latest(
        rows,
        template(version: 2, wording: 'Previous school'),
      )!.answers,
      isEmpty,
    );
    expect(
      IntakeBackground.latest(
        rows,
        template(version: 2, option: 'Daycare'),
      )!.answers,
      isEmpty,
    );
  });
  test(
    'legacy records without signatures are accepted only at the exact version',
    () {
      final old = responses(template())..remove('question_signatures');
      expect(IntakeBackground.latest([row(old)], template())!.answers, {
        'school': 'k',
      });
      expect(
        IntakeBackground.latest([row(old)], template(version: 2))!.answers,
        isEmpty,
      );
    },
  );
  test('repeated reuse retains the original observation date and source', () {
    final original =
        IntakeBackground.latest([row(responses(template()))], template())!;
    final reused = IntakeRecord(
      role: ObserverRole.guardian,
      answers: original.answers,
      reusedQuestionIds: ['school'],
      answerSources: original.sources,
      backgroundMode: 'reuse',
    ).toResponses(template());
    final next =
        IntakeBackground.latest([
          {
            ...row(reused),
            'id': 'recent',
            'completed_at': '2026-10-01T10:00:00',
          },
        ], template())!;
    expect((next.sources['school'] as Map)['questionnaire_id'], 'earlier');
    expect((next.sources['school'] as Map)['observer_role'], 'parent');
    expect(
      (next.sources['school'] as Map)['completed_at'],
      '2026-09-01T10:00:00',
    );
    expect(
      IntakeRecord.fromResponses(reused)!.headline,
      contains('not new observations'),
    );
  });
  test('malformed records are skipped and another template is not reused', () {
    expect(
      IntakeBackground.latest([
        {...row({}), 'responses': '{broken'},
        row({...responses(template()), 'template_id': 'other'}),
        row(responses(template())),
      ], template())!.answers,
      {'school': 'k'},
    );
  });
}
