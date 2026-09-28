import 'choice_template.dart';
import 'template_kind.dart';

/// The bundled "Before your child starts" questions (AUM-351): optional
/// background about the child. Who is watching is asked by the app itself,
/// because it is stored as the record's role.
const kDefaultIntakeTemplate = ChoiceTemplate(
  key: 'aumazing_observer_intake',
  version: 1,
  status: 'draft',
  kind: TemplateKind.intake,
  title: 'Before your child starts',
  intro:
      'Sit beside your child and watch them play. Please help only if they '
      'are stuck or upset, and remember how much you helped. Nothing will '
      'interrupt the games — we will ask what you saw when your child '
      'finishes.',
  questions: [
    TemplateQuestion(
      id: 'diagnosis',
      text: 'Has your child been diagnosed with autism?',
      type: QuestionType.single,
      options: [
        ChoiceOption(id: 'diagnosed', label: 'Diagnosed with autism'),
        ChoiceOption(id: 'evaluating', label: 'Being evaluated or suspected'),
        ChoiceOption(id: 'not_diagnosed', label: 'Not diagnosed'),
        ChoiceOption(
          id: 'prefer_not_to_say',
          label: 'Prefer not to say',
          quiet: true,
        ),
      ],
    ),
    TemplateQuestion(
      id: 'school',
      text: 'Where does your child go to school?',
      type: QuestionType.single,
      options: [
        ChoiceOption(id: 'not_in_school', label: 'Not in school yet'),
        ChoiceOption(id: 'daycare', label: 'Daycare'),
        ChoiceOption(id: 'kinder', label: 'Kinder'),
        ChoiceOption(id: 'grade_1', label: 'Grade 1'),
        ChoiceOption(id: 'grade_2_up', label: 'Grade 2 or higher'),
        ChoiceOption(id: 'sped', label: 'SPED class or school'),
        ChoiceOption(id: 'inclusive', label: 'Regular class with SPED support'),
        ChoiceOption(id: 'homeschool', label: 'Home-schooled'),
      ],
    ),
    TemplateQuestion(
      id: 'therapies',
      text: 'Current therapy (choose any)',
      type: QuestionType.multi,
      shortLabel: 'Therapy',
      options: [
        ChoiceOption(id: 'speech', label: 'Speech'),
        ChoiceOption(id: 'occupational', label: 'Occupational'),
        ChoiceOption(id: 'behavioural', label: 'Behavioural'),
        ChoiceOption(id: 'other', label: 'Other'),
        ChoiceOption(id: 'none', label: 'None', quiet: true, exclusive: true),
      ],
    ),
  ],
);

/// The bundled "What did you see?" questions (AUM-351).
const kDefaultObservationTemplate = ChoiceTemplate(
  key: 'aumazing_session_observation',
  version: 1,
  status: 'draft',
  kind: TemplateKind.observation,
  title: 'What did you see?',
  intro:
      'Think back to the games your child just played. There are no right '
      'answers — tell us what you saw. Your answers appear beside each '
      'game\'s result and never change a score.',
  questions: [
    TemplateQuestion(
      id: 'understood',
      text: 'Did your child understand what to do?',
      type: QuestionType.single,
      shortLabel: 'Understood',
      scope: QuestionScope.game,
      required: true,
      options: [
        ChoiceOption(id: 'yes', label: 'Yes'),
        ChoiceOption(id: 'partly', label: 'Partly'),
        ChoiceOption(
          id: 'no',
          label: 'No',
          flag: 'Did not understand the task',
        ),
      ],
    ),
    TemplateQuestion(
      id: 'help',
      text: 'How much did you help?',
      type: QuestionType.single,
      scope: QuestionScope.game,
      required: true,
      options: [
        ChoiceOption(id: 'none', label: 'No help'),
        ChoiceOption(id: 'told', label: 'Told them'),
        ChoiceOption(
          id: 'showed',
          label: 'Pointed or showed',
          flag: 'Played with help (pointed or showed)',
        ),
        ChoiceOption(
          id: 'hand',
          label: 'Helped their hand',
          flag: 'Played with help (helped their hand)',
        ),
      ],
    ),
    TemplateQuestion(
      id: 'mood',
      text: 'How did your child seem?',
      type: QuestionType.single,
      scope: QuestionScope.game,
      required: true,
      options: [
        ChoiceOption(id: 'calm', label: 'Calm'),
        ChoiceOption(id: 'excited', label: 'Excited'),
        ChoiceOption(
          id: 'upset',
          label: 'Frustrated or upset',
          flag: 'Was frustrated or upset',
        ),
      ],
    ),
    TemplateQuestion(
      id: 'as_usual',
      text: 'Compared with how your child usually does tasks like this:',
      type: QuestionType.single,
      scope: QuestionScope.game,
      required: true,
      options: [
        ChoiceOption(id: 'usual', label: 'As usual'),
        ChoiceOption(id: 'better', label: 'Better than usual'),
        ChoiceOption(
          id: 'worse',
          label: 'Worse than usual',
          flag: 'Worse than usual',
        ),
      ],
    ),
    TemplateQuestion(
      id: 'day',
      text: 'Was today a typical day for your child?',
      type: QuestionType.single,
      required: true,
      options: [
        ChoiceOption(id: 'normal', label: 'A normal day'),
        ChoiceOption(
          id: 'tired_or_sick',
          label: 'Tired or sick',
          flag: 'Not a typical day (tired or sick)',
        ),
        ChoiceOption(
          id: 'distracted',
          label: 'New place or distracted',
          flag: 'Not a typical day (new place or distracted)',
        ),
      ],
    ),
    TemplateQuestion(
      id: 'note',
      text: 'Anything else you noticed? (optional)',
      type: QuestionType.text,
    ),
  ],
);

/// The bundled template of [kind] (not [TemplateKind.home], which the app
/// keeps with its scoring).
ChoiceTemplate defaultChoiceTemplate(TemplateKind kind) => switch (kind) {
  TemplateKind.intake => kDefaultIntakeTemplate,
  TemplateKind.observation => kDefaultObservationTemplate,
  TemplateKind.home => throw ArgumentError('Home is not a choice template'),
};
