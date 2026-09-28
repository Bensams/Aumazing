import 'dart:convert';

import 'template_kind.dart';

/// How a question is answered.
enum QuestionType {
  /// Pick one option.
  single('single', 'Choose one'),

  /// Pick any number of options.
  multi('multi', 'Choose any'),

  /// Free text.
  text('text', 'Written answer');

  const QuestionType(this.key, this.label);

  final String key;
  final String label;

  static QuestionType? fromKey(Object? key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// Where an after-session question is asked.
enum QuestionScope {
  /// Once for the whole session.
  session('session', 'Once for the session'),

  /// Once for every game the child played.
  game('game', 'For each game');

  const QuestionScope(this.key, this.label);

  final String key;
  final String label;

  static QuestionScope? fromKey(Object? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// One answer a question offers.
class ChoiceOption {
  const ChoiceOption({
    required this.id,
    required this.label,
    this.flag,
    this.quiet = false,
    this.exclusive = false,
  });

  final String id;
  final String label;

  /// Shown on the results when this answer is chosen — something the reader
  /// of a score should know, such as "Played with help". Never changes a
  /// score.
  final String? flag;

  /// Left out of the results summary ("Prefer not to say", "None").
  final bool quiet;

  /// Choose-any questions only: picking it clears the others, and picking
  /// another clears it ("None").
  final bool exclusive;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (flag != null && flag!.trim().isNotEmpty) 'flag': flag,
    if (quiet) 'quiet': true,
    if (exclusive) 'exclusive': true,
  };

  static ChoiceOption fromJson(Map raw) => ChoiceOption(
    id: '${raw['id'] ?? ''}',
    label: '${raw['label'] ?? ''}',
    flag: raw['flag'] is String && (raw['flag'] as String).trim().isNotEmpty
        ? raw['flag'] as String
        : null,
    quiet: raw['quiet'] == true,
    exclusive: raw['exclusive'] == true,
  );
}

/// One question of a before- or after-session template.
class TemplateQuestion {
  const TemplateQuestion({
    required this.id,
    required this.text,
    required this.type,
    this.scope = QuestionScope.session,
    this.required = false,
    this.shortLabel,
    this.options = const [],
  });

  final String id;
  final String text;
  final QuestionType type;
  final QuestionScope scope;

  /// Whether Save waits for an answer.
  final bool required;

  /// Prefix for the answer in the results summary, e.g. "Therapy" or
  /// "Understood".
  final String? shortLabel;

  final List<ChoiceOption> options;

  ChoiceOption? option(Object? id) {
    for (final o in options) {
      if (o.id == id) return o;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'type': type.key,
    'scope': scope.key,
    if (required) 'required': true,
    if (shortLabel != null && shortLabel!.trim().isNotEmpty)
      'short_label': shortLabel,
    if (type != QuestionType.text)
      'options': [for (final o in options) o.toJson()],
  };

  static TemplateQuestion fromJson(Map raw) => TemplateQuestion(
    id: '${raw['id'] ?? ''}',
    text: '${raw['text'] ?? ''}',
    type: QuestionType.fromKey(raw['type']) ?? QuestionType.single,
    scope: QuestionScope.fromKey(raw['scope']) ?? QuestionScope.session,
    required: raw['required'] == true,
    shortLabel: raw['short_label'] is String ? raw['short_label'] as String : null,
    options: [
      if (raw['options'] is List)
        for (final o in raw['options'] as List)
          if (o is Map) ChoiceOption.fromJson(o),
    ],
  );

  /// Whether [value] answers this question.
  bool isAnswered(Object? value) => switch (type) {
    QuestionType.single => value is String && option(value) != null,
    QuestionType.multi =>
      value is List && value.isNotEmpty && value.every((v) => option(v) != null),
    QuestionType.text => value is String && value.trim().isNotEmpty,
  };
}

/// A before-session ([TemplateKind.intake]) or after-session
/// ([TemplateKind.observation]) template: questions answered by tapping.
///
/// Answers are a map of question id to a value — an option id for a
/// choose-one question, a list of option ids for choose-any, a string for a
/// written answer.
class ChoiceTemplate {
  const ChoiceTemplate({
    required this.key,
    required this.version,
    required this.status,
    required this.kind,
    required this.title,
    required this.intro,
    required this.questions,
  });

  final String key;
  final int version;

  /// `draft` or `validated`; stored with every answer.
  final String status;
  final TemplateKind kind;
  final String title;
  final String intro;
  final List<TemplateQuestion> questions;

  bool get isDraft => status != 'validated';

  List<TemplateQuestion> questionsFor(QuestionScope scope) => [
    for (final q in questions)
      if (q.scope == scope) q,
  ];

  List<Map<String, Object?>> itemsJson() => [
    for (final q in questions) q.toJson(),
  ];

  /// Problems with a template's items, in words a practitioner can act on;
  /// empty when the app will accept it.
  static List<String> validateItems(TemplateKind kind, Object? items) {
    if (kind == TemplateKind.home) {
      throw ArgumentError('Home templates use validateHomeItems');
    }
    if (items is! List) return ['The questions are missing.'];
    if (items.isEmpty) return ['Add at least one question.'];
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
      if (id is! String || !_idPattern.hasMatch(id)) {
        errors.add(
          'Question $n needs an id of lowercase letters, numbers and _.',
        );
      } else if (!ids.add(id)) {
        errors.add('Question $n reuses the id "$id".');
      }
      final text = raw['text'];
      if (text is! String || text.trim().isEmpty) {
        errors.add('Question $n needs its wording.');
      }
      final type = QuestionType.fromKey(raw['type']);
      if (type == null) {
        errors.add('Question $n needs an answer type.');
        continue;
      }
      final scope = QuestionScope.fromKey(raw['scope'] ?? 'session');
      if (scope == null) {
        errors.add('Question $n has an unknown "asked" setting.');
      } else if (kind == TemplateKind.intake && scope == QuestionScope.game) {
        errors.add(
          'Question $n is asked for each game, but no game has been played '
          'before the session.',
        );
      }
      final options = raw['options'];
      if (type == QuestionType.text) continue;
      if (options is! List || options.length < 2) {
        errors.add('Question $n needs at least two answers to choose from.');
        continue;
      }
      final optionIds = <String>{};
      for (var j = 0; j < options.length; j++) {
        final o = options[j];
        if (o is! Map) {
          errors.add('Question $n, answer ${j + 1} is not in the right format.');
          continue;
        }
        final oid = o['id'];
        if (oid is! String || !_idPattern.hasMatch(oid)) {
          errors.add(
            'Question $n, answer ${j + 1} needs an id of lowercase letters, '
            'numbers and _.',
          );
        } else if (!optionIds.add(oid)) {
          errors.add('Question $n reuses the answer id "$oid".');
        }
        final label = o['label'];
        if (label is! String || label.trim().isEmpty) {
          errors.add('Question $n, answer ${j + 1} needs a label.');
        }
      }
    }
    if (kind == TemplateKind.observation &&
        !items.any((raw) => raw is Map && raw['scope'] == 'game')) {
      errors.add('Ask at least one question for each game.');
    }
    return errors;
  }

  static final _idPattern = RegExp(r'^[a-z0-9_]+$');

  /// A template from a `questionnaire_templates` row of [kind], or null when
  /// the row is not one or would not work.
  static ChoiceTemplate? fromRow(Map<String, dynamic> row, TemplateKind kind) {
    try {
      if ((TemplateKind.fromKey(row['kind']) ?? TemplateKind.home) != kind) {
        return null;
      }
      final items = row['items'] is String
          ? jsonDecode(row['items'] as String)
          : row['items'];
      if (validateItems(kind, items).isNotEmpty) return null;
      final key = row['template_key'];
      final title = row['title'];
      if (key is! String || title is! String) return null;
      return ChoiceTemplate(
        key: key,
        version: (row['version'] as num?)?.toInt() ?? 1,
        status: row['status'] == 'validated' ? 'validated' : 'draft',
        kind: kind,
        title: title,
        intro: (row['intro'] as String?) ?? '',
        questions: [
          for (final raw in items as List) TemplateQuestion.fromJson(raw as Map),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  /// Whether every required question in [scope] is answered.
  bool isComplete(Map<String, Object?> answers, QuestionScope scope) =>
      questionsFor(scope).every(
        (q) => !q.required || q.isAnswered(answers[q.id]),
      );

  /// Readable answers for the results, e.g. "Kinder", "Therapy: Speech".
  List<String> summary(Map<String, Object?> answers, QuestionScope scope) {
    final out = <String>[];
    for (final q in questionsFor(scope)) {
      if (q.type == QuestionType.text) continue;
      final labels = [
        for (final id in _chosen(q, answers[q.id]))
          if (q.option(id) case final o? when !o.quiet) o.label,
      ];
      if (labels.isEmpty) continue;
      final joined = labels.join(', ');
      final prefix = q.shortLabel?.trim() ?? '';
      out.add(prefix.isEmpty ? joined : '$prefix: $joined');
    }
    return out;
  }

  /// What a reader of the results should know, from the answers chosen.
  List<String> flags(Map<String, Object?> answers, QuestionScope scope) => [
    for (final q in questionsFor(scope))
      for (final id in _chosen(q, answers[q.id]))
        if (q.option(id)?.flag case final flag?) flag,
  ];

  /// Written answers, in question order.
  List<String> notes(Map<String, Object?> answers, QuestionScope scope) => [
    for (final q in questionsFor(scope))
      if (q.type == QuestionType.text)
        if (answers[q.id] case final String text when text.trim().isNotEmpty)
          text.trim(),
  ];

  static List<Object?> _chosen(TemplateQuestion q, Object? value) =>
      switch (q.type) {
        QuestionType.single => [value],
        QuestionType.multi => value is List ? value : const [],
        QuestionType.text => const [],
      };

  /// The template fields stored with every answer, so answers from
  /// different templates are never mixed.
  Map<String, Object> get stamp => {
    'template_id': key,
    'template_version': version,
    'template_status': status,
  };
}
