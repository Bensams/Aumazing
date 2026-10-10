import 'package:questionnaire_core/questionnaire_core.dart';
import 'package:test/test.dart';

void main() {
  group('the bundled templates', () {
    test('pass their own validation', () {
      expect(validateHomeItems(kDefaultHomeTemplate['items']), isEmpty);
      for (final t in [kDefaultIntakeTemplate, kDefaultObservationTemplate]) {
        expect(
          ChoiceTemplate.validateItems(t.kind, t.itemsJson()),
          isEmpty,
          reason: t.key,
        );
      }
    });

    test('round-trip through a stored row unchanged', () {
      for (final t in [kDefaultIntakeTemplate, kDefaultObservationTemplate]) {
        final back =
            ChoiceTemplate.fromRow({
              'template_key': t.key,
              'version': t.version,
              'kind': t.kind.key,
              'title': t.title,
              'intro': t.intro,
              'items': t.itemsJson(),
              'status': 'validated',
            }, t.kind)!;
        expect(back.itemsJson(), t.itemsJson());
        expect(back.status, 'validated');
      }
    });
  });

  group('validation', () {
    test('home items need every area', () {
      final errors = validateHomeItems([
        {'id': 'a', 'domain': 'play', 'text': 'Plays'},
        {'id': 'a', 'domain': 'nope', 'text': ''},
      ]);
      expect(errors, contains('Question 2 reuses the id "a".'));
      expect(errors, contains('Question 2 needs an area.'));
      expect(errors, contains('Question 2 needs a statement.'));
      expect(errors, contains('Add at least one question for Communication.'));
      expect(errors.any((e) => e.contains('Play Skills')), isFalse);
    });

    test('choice questions need two answers with ids and labels', () {
      final errors = ChoiceTemplate.validateItems(TemplateKind.intake, [
        {
          'id': 'School',
          'text': 'Where?',
          'type': 'single',
          'options': [
            {'id': 'k', 'label': 'Kinder'},
          ],
        },
        {
          'id': 'x',
          'text': 'Which?',
          'type': 'multi',
          'options': [
            {'id': 'a', 'label': 'A'},
            {'id': 'a', 'label': ''},
          ],
        },
      ]);
      expect(errors, [
        'Question 1 needs an id of lowercase letters, numbers and _.',
        'Question 1 needs at least two answers to choose from.',
        'Question 2 reuses the answer id "a".',
        'Question 2, answer 2 needs a label.',
      ]);
    });

    test('before the session nothing can be asked per game', () {
      expect(
        ChoiceTemplate.validateItems(TemplateKind.intake, [
          {'id': 'n', 'text': 'Note', 'type': 'text', 'scope': 'game'},
        ]),
        [
          'Question 1 is asked for each game, but no game has been played '
              'before the session.',
        ],
      );
    });

    test('a short check-in can contain only session questions', () {
      expect(
        ChoiceTemplate.validateItems(TemplateKind.observation, [
          {'id': 'n', 'text': 'Note', 'type': 'text'},
        ]),
        isEmpty,
      );
    });

    test('a row of another kind or with broken items is refused', () {
      final row = {
        'template_key': 'k',
        'kind': 'intake',
        'title': 't',
        'items': [
          {'id': 'n', 'text': 'Note', 'type': 'text'},
        ],
      };
      expect(ChoiceTemplate.fromRow(row, TemplateKind.intake), isNotNull);
      expect(ChoiceTemplate.fromRow(row, TemplateKind.observation), isNull);
      expect(
        ChoiceTemplate.fromRow({...row, 'items': '[]'}, TemplateKind.intake),
        isNull,
      );
      // A row written before kinds existed is a home questionnaire.
      expect(
        ChoiceTemplate.fromRow({...row}..remove('kind'), TemplateKind.intake),
        isNull,
      );
    });
  });

  group('answers', () {
    const t = kDefaultObservationTemplate;

    test('complete once every required question has an answer', () {
      final game = <String, Object?>{
        'understood': 'yes',
        'help': 'none',
        'mood': 'calm',
      };
      expect(t.isComplete(game, QuestionScope.game), isFalse);
      game['as_usual'] = 'usual';
      expect(t.isComplete(game, QuestionScope.game), isTrue);
      // The note is optional; the day is not.
      expect(t.isComplete({}, QuestionScope.session), isFalse);
      expect(
        t.isComplete({
          'day': 'normal',
          'session_help': 'none',
          'session_mood': 'calm',
        }, QuestionScope.session),
        isTrue,
      );
      // An answer the question does not offer does not count.
      expect(t.isComplete({'day': 'rainy'}, QuestionScope.session), isFalse);
    });

    test('flags, summary and notes come from the chosen answers', () {
      final game = {
        'understood': 'no',
        'help': 'hand',
        'mood': 'upset',
        'as_usual': 'worse',
      };
      expect(t.flags(game, QuestionScope.game), [
        'Did not understand the task',
        'Played with help (helped their hand)',
        'Was frustrated or upset',
        'Worse than usual',
      ]);
      expect(t.summary(game, QuestionScope.game), [
        'Understood: No',
        'Helped their hand',
        'Frustrated or upset',
        'Worse than usual',
      ]);
      final session = {'day': 'tired_or_sick', 'note': '  Sleepy  '};
      expect(t.flags(session, QuestionScope.session), [
        'Not a typical day (tired or sick)',
      ]);
      expect(t.notes(session, QuestionScope.session), ['Sleepy']);
    });

    test('quiet answers stay out of the summary; short labels prefix', () {
      const intake = kDefaultIntakeTemplate;
      expect(
        intake.summary({
          'diagnosis': 'prefer_not_to_say',
          'school': 'sped',
          'therapies': ['speech', 'occupational'],
        }, QuestionScope.session),
        ['SPED class or school', 'Therapy: Speech, Occupational'],
      );
      expect(
        intake.summary({
          'therapies': ['none'],
        }, QuestionScope.session),
        isEmpty,
      );
    });
  });
}
