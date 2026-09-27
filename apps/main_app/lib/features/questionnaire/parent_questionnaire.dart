/// The parent questionnaire answered alongside the pre- and post-assessment
/// (pre-final defense note: "pre and post assessment survey or questionnaire
/// for parents").
///
/// The games measure what the child *does on the tablet*; this records what
/// the parent sees *at home*, in the same four domains the assessment reports
/// on. Asking the identical questions before and after lets the parent's view
/// of change sit next to the game-measured change.
///
/// The questions are data, not code: a [QuestionnaireTemplate] is a list of
/// items, each tagged with the domain it informs. That is so a template
/// authored or approved by a practitioner can replace this one without an app
/// release.
///
/// **This item set is a draft.** It describes plain, observable everyday
/// behaviours, and it has not yet been validated. It is marked as such in
/// [QuestionnaireTemplate.status] and in every stored response, so a draft
/// answer can never be mistaken later for a validated instrument's.
library;

/// The four domains the assessment reports on, with the labels the parent
/// dashboard already uses.
enum QuestionnaireDomain {
  communication('communication', 'Communication'),
  play('play', 'Play Skills'),
  social('social', 'Social Interaction'),
  attention('attention', 'Attention & Focus');

  const QuestionnaireDomain(this.key, this.label);

  /// Stable key used in stored responses; matches the dashboard's area keys.
  final String key;
  final String label;
}

/// One statement the parent rates by how often it is true.
class QuestionnaireItem {
  const QuestionnaireItem({
    required this.id,
    required this.domain,
    required this.text,
  });

  /// Stable id stored with the answer. Never reuse an id for a changed
  /// statement — bump the template version instead.
  final String id;
  final QuestionnaireDomain domain;
  final String text;
}

/// A five-point frequency scale. Every item is phrased so that "Always" is
/// the more developed end, so a domain score reads the same way as the
/// game-measured levels: higher is more of the skill.
enum Frequency {
  never(0, 'Never'),
  rarely(1, 'Rarely'),
  sometimes(2, 'Sometimes'),
  often(3, 'Often'),
  always(4, 'Always');

  const Frequency(this.value, this.label);

  final int value;
  final String label;

  static const int maxValue = 4;
}

class QuestionnaireTemplate {
  const QuestionnaireTemplate({
    required this.id,
    required this.version,
    required this.status,
    required this.title,
    required this.intro,
    required this.items,
  });

  /// Stored with each response so answers from different templates are never
  /// averaged together.
  final String id;
  final int version;

  /// `draft` until the item set has been validated; `validated` after.
  final String status;
  final String title;
  final String intro;
  final List<QuestionnaireItem> items;

  bool get isDraft => status != 'validated';

  List<QuestionnaireItem> itemsFor(QuestionnaireDomain domain) =>
      items.where((i) => i.domain == domain).toList();
}

/// The template the app ships with.
const kParentQuestionnaireDraft = QuestionnaireTemplate(
  id: 'aumazing_parent_checklist',
  version: 1,
  status: 'draft',
  title: 'A few questions about your child',
  intro:
      'Think about the last two weeks at home. For each sentence, choose how '
      'often it is true for your child. There are no right or wrong answers — '
      'this is your view, and it sits beside what the games measured.',
  items: [
    // Communication
    QuestionnaireItem(
      id: 'comm_name',
      domain: QuestionnaireDomain.communication,
      text: 'My child responds when I call their name.',
    ),
    QuestionnaireItem(
      id: 'comm_request',
      domain: QuestionnaireDomain.communication,
      text: 'My child uses words, signs or gestures to ask for what they want.',
    ),
    QuestionnaireItem(
      id: 'comm_instruction',
      domain: QuestionnaireDomain.communication,
      text:
          'My child follows a simple one-step instruction, like '
          '"Give me the ball."',
    ),
    QuestionnaireItem(
      id: 'comm_point',
      domain: QuestionnaireDomain.communication,
      text: 'My child points to show me something interesting.',
    ),
    // Play skills
    QuestionnaireItem(
      id: 'play_functional',
      domain: QuestionnaireDomain.play,
      text:
          'My child plays with toys the way they are meant to be used, like '
          'pushing a car or stacking blocks.',
    ),
    QuestionnaireItem(
      id: 'play_pretend',
      domain: QuestionnaireDomain.play,
      text:
          'My child plays pretend, like feeding a doll or talking on a toy '
          'phone.',
    ),
    QuestionnaireItem(
      id: 'play_imitate',
      domain: QuestionnaireDomain.play,
      text: 'My child copies a simple action I show them during play.',
    ),
    QuestionnaireItem(
      id: 'play_stay',
      domain: QuestionnaireDomain.play,
      text: 'My child stays with one toy or game for a few minutes.',
    ),
    // Social interaction
    QuestionnaireItem(
      id: 'social_face',
      domain: QuestionnaireDomain.social,
      text: 'My child looks at my face when I talk or play with them.',
    ),
    QuestionnaireItem(
      id: 'social_turn',
      domain: QuestionnaireDomain.social,
      text: 'My child waits for their turn in a simple game.',
    ),
    QuestionnaireItem(
      id: 'social_greet',
      domain: QuestionnaireDomain.social,
      text: 'My child waves or greets back when someone says hello.',
    ),
    QuestionnaireItem(
      id: 'social_share',
      domain: QuestionnaireDomain.social,
      text: 'My child brings or shows me things to share their interest.',
    ),
    // Attention & focus
    QuestionnaireItem(
      id: 'attn_finish',
      domain: QuestionnaireDomain.attention,
      text: 'My child sits with me and finishes a short activity.',
    ),
    QuestionnaireItem(
      id: 'attn_follow_point',
      domain: QuestionnaireDomain.attention,
      text: 'When I point at something, my child looks where I am pointing.',
    ),
    QuestionnaireItem(
      id: 'attn_return',
      domain: QuestionnaireDomain.attention,
      text: 'My child goes back to a task after a small distraction.',
    ),
    QuestionnaireItem(
      id: 'attn_listen',
      domain: QuestionnaireDomain.attention,
      text: 'My child listens to a short instruction without walking away.',
    ),
  ],
);

/// Domain scores for a set of answers, each 0–100.
///
/// A domain's score is the mean of its answered items on the 0–4 scale,
/// expressed as a percentage. A domain with no answered items has no score
/// (null) rather than a zero — an unanswered domain is unknown, not low.
Map<QuestionnaireDomain, double?> scoreQuestionnaire(
  QuestionnaireTemplate template,
  Map<String, Frequency> answers,
) {
  return {
    for (final domain in QuestionnaireDomain.values)
      domain: () {
        final values = [
          for (final item in template.itemsFor(domain))
            if (answers[item.id] case final a?) a.value,
        ];
        if (values.isEmpty) return null;
        final mean = values.reduce((a, b) => a + b) / values.length;
        return (mean / Frequency.maxValue * 100).roundToDouble();
      }(),
  };
}
