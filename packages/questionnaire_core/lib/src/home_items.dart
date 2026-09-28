/// The home questionnaire's items (AUM-341): statements the parent rates by
/// how often they are true, each tagged with one of the four domains the
/// assessment reports on.
library;

/// Domain keys, matching the parent dashboard's area keys.
const kHomeDomains = <String, String>{
  'communication': 'Communication',
  'play': 'Play Skills',
  'social': 'Social Interaction',
  'attention': 'Attention & Focus',
};

/// Problems with a home template's items, in words a practitioner can act
/// on; empty when the app will accept it.
///
/// Every item needs a unique id, a known domain and a statement, and every
/// domain needs at least one item — otherwise that domain has no score.
List<String> validateHomeItems(Object? items) {
  if (items is! List) return ['The questions are missing.'];
  if (items.isEmpty) return ['Add at least one question for each area.'];
  final errors = <String>[];
  final ids = <String>{};
  for (var i = 0; i < items.length; i++) {
    final raw = items[i];
    final n = i + 1;
    if (raw is! Map) {
      errors.add('Question $n is not in the right format.');
      continue;
    }
    final id = raw['id'];
    if (id is! String || id.trim().isEmpty) {
      errors.add('Question $n needs an id.');
    } else if (!ids.add(id)) {
      errors.add('Question $n reuses the id "$id".');
    }
    if (!kHomeDomains.containsKey(raw['domain'])) {
      errors.add('Question $n needs an area.');
    }
    final text = raw['text'];
    if (text is! String || text.trim().isEmpty) {
      errors.add('Question $n needs a statement.');
    }
  }
  for (final entry in kHomeDomains.entries) {
    if (!items.any((raw) => raw is Map && raw['domain'] == entry.key)) {
      errors.add('Add at least one question for ${entry.value}.');
    }
  }
  return errors;
}

/// The bundled home questionnaire, as template rows store it.
const kDefaultHomeTemplate = <String, Object>{
  'template_key': 'aumazing_parent_checklist',
  'title': 'A few questions about your child',
  'intro':
      'Think about the last two weeks at home. For each sentence, choose how '
      'often it is true for your child. There are no right or wrong answers — '
      'this is your view, and it sits beside what the games measured.',
  'items': [
    {
      'id': 'comm_name',
      'domain': 'communication',
      'text': 'My child responds when I call their name.',
    },
    {
      'id': 'comm_request',
      'domain': 'communication',
      'text':
          'My child uses words, signs or gestures to ask for what they want.',
    },
    {
      'id': 'comm_instruction',
      'domain': 'communication',
      'text':
          'My child follows a simple one-step instruction, like '
          '"Give me the ball."',
    },
    {
      'id': 'comm_point',
      'domain': 'communication',
      'text': 'My child points to show me something interesting.',
    },
    {
      'id': 'play_functional',
      'domain': 'play',
      'text':
          'My child plays with toys the way they are meant to be used, like '
          'pushing a car or stacking blocks.',
    },
    {
      'id': 'play_pretend',
      'domain': 'play',
      'text':
          'My child plays pretend, like feeding a doll or talking on a toy '
          'phone.',
    },
    {
      'id': 'play_imitate',
      'domain': 'play',
      'text': 'My child copies a simple action I show them during play.',
    },
    {
      'id': 'play_stay',
      'domain': 'play',
      'text': 'My child stays with one toy or game for a few minutes.',
    },
    {
      'id': 'social_face',
      'domain': 'social',
      'text': 'My child looks at my face when I talk or play with them.',
    },
    {
      'id': 'social_turn',
      'domain': 'social',
      'text': 'My child waits for their turn in a simple game.',
    },
    {
      'id': 'social_greet',
      'domain': 'social',
      'text': 'My child waves or greets back when someone says hello.',
    },
    {
      'id': 'social_share',
      'domain': 'social',
      'text': 'My child brings or shows me things to share their interest.',
    },
    {
      'id': 'attn_finish',
      'domain': 'attention',
      'text': 'My child sits with me and finishes a short activity.',
    },
    {
      'id': 'attn_follow_point',
      'domain': 'attention',
      'text': 'When I point at something, my child looks where I am pointing.',
    },
    {
      'id': 'attn_return',
      'domain': 'attention',
      'text': 'My child goes back to a task after a small distraction.',
    },
    {
      'id': 'attn_listen',
      'domain': 'attention',
      'text': 'My child listens to a short instruction without walking away.',
    },
  ],
};
