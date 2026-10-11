import 'package:flutter/material.dart';
import 'package:questionnaire_core/questionnaire_core.dart';

import '../data/auto_id.dart';
import '../data/questionnaire_api.dart';

/// Writes or edits one questionnaire template (AUM-352): the home
/// questionnaire, "Before your child starts" or "What did you see?".
///
/// Uses the same validation the app runs before showing a template, so
/// anything this page saves is something the app will use. Pops `true`
/// after a save.
///
/// Practitioners only write words. The questionnaire's name and every
/// question and answer id are made from those words (AUM-356); ids a
/// template already has are kept, so answers recorded against it still
/// match.
class TemplateEditorPage extends StatefulWidget {
  const TemplateEditorPage({
    super.key,
    required this.api,
    required this.isAdmin,
    this.existing,
    this.asNewVersionOf,
  });

  final QuestionnaireApi api;
  final bool isAdmin;

  /// The template being edited in place.
  final Map<String, dynamic>? existing;

  /// A template to copy into a new version, leaving the original untouched.
  final Map<String, dynamic>? asNewVersionOf;

  @override
  State<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _HomeItem {
  _HomeItem({this.id = '', this.domain = 'communication', this.text = ''});

  /// Empty until saved; [toJson] is then given one made from [text].
  String id;
  String domain;
  String text;

  Map<String, Object?> toJson(String id) => {
    'id': id,
    'domain': domain,
    'text': text.trim(),
  };
}

class _Option {
  _Option({
    this.id = '',
    this.label = '',
    this.flag = '',
    this.quiet = false,
    this.exclusive = false,
  });

  factory _Option.from(ChoiceOption o) => _Option(
    id: o.id,
    label: o.label,
    flag: o.flag ?? '',
    quiet: o.quiet,
    exclusive: o.exclusive,
  );

  /// Empty until saved; [toJson] is then given one made from [label].
  String id;
  String label;
  String flag;
  bool quiet;
  bool exclusive;

  Map<String, Object?> toJson(String id) =>
      ChoiceOption(
        id: id,
        label: label.trim(),
        flag: flag.trim().isEmpty ? null : flag.trim(),
        quiet: quiet,
        exclusive: exclusive,
      ).toJson();
}

class _Question {
  _Question({
    this.id = '',
    this.text = '',
    this.type = QuestionType.single,
    this.scope = QuestionScope.session,
    this.required = false,
    this.shortLabel = '',
    this.timing = AnswerTiming.background,
    List<_Option>? options,
  }) : options = options ?? [_Option(), _Option()];

  factory _Question.from(TemplateQuestion q) => _Question(
    id: q.id,
    text: q.text,
    type: q.type,
    scope: q.scope,
    required: q.required,
    shortLabel: q.shortLabel ?? '',
    timing: q.timing,
    options: [for (final o in q.options) _Option.from(o)],
  );

  /// Empty until saved; [toJson] is then given one made from [text].
  String id;
  String text;
  QuestionType type;
  QuestionScope scope;
  bool required;
  String shortLabel;
  AnswerTiming timing;
  List<_Option> options;

  Map<String, Object?> toJson(String id) {
    final taken = {
      for (final o in options)
        if (o.id.isNotEmpty) o.id,
    };
    return {
      'id': id,
      'text': text.trim(),
      'type': type.key,
      'scope': scope.key,
      'timing': timing.key,
      if (required) 'required': true,
      if (shortLabel.trim().isNotEmpty) 'short_label': shortLabel.trim(),
      if (type != QuestionType.text)
        'options': [
          for (var j = 0; j < options.length; j++)
            options[j].toJson(
              options[j].id.isNotEmpty
                  ? options[j].id
                  : uniqueSlug(
                    options[j].label,
                    taken,
                    fallback: 'answer_${j + 1}',
                  ),
            ),
        ],
    };
  }
}

class _TemplateEditorPageState extends State<TemplateEditorPage> {
  late TemplateKind _kind;
  late AssessmentScope _scope;
  late String _key;
  late int _version;
  late String _title;
  late String _intro;
  List<_HomeItem> _home = [];
  List<_Question> _questions = [];
  bool _saving = false;
  String? _saveError;

  static const _areaHelp = {
    'communication': 'Expressing needs and understanding words or gestures.',
    'play': 'Using toys, pretending and joining play activities.',
    'social': 'Connecting with others, sharing and taking turns.',
    'attention': 'Following instructions and staying with an activity.',
  };

  /// Bumped whenever the lists are replaced wholesale, so the fields rebuild.
  int _generation = 0;

  bool get _editingInPlace => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final source = widget.existing ?? widget.asNewVersionOf;
    if (source == null) {
      _kind = TemplateKind.home;
      _scope = AssessmentScope.both;
      _key = '';
      _version = 1;
      _title = '';
      _intro = '';
      return;
    }
    _kind = TemplateKind.fromKey(source['kind']) ?? TemplateKind.home;
    _scope =
        AssessmentScope.fromKey(source['questionnaire_type']) ??
        AssessmentScope.both;
    _key = '${source['template_key'] ?? ''}';
    final version = (source['version'] as num?)?.toInt() ?? 1;
    _version = widget.asNewVersionOf != null ? version + 1 : version;
    _title = '${source['title'] ?? ''}';
    _intro = '${source['intro'] ?? ''}';
    _loadItems(source['items']);
  }

  void _loadItems(Object? items) {
    final list = items is List ? items : const [];
    if (_kind == TemplateKind.home) {
      _home = [
        for (final raw in list)
          if (raw is Map)
            _HomeItem(
              id: '${raw['id'] ?? ''}',
              domain:
                  kHomeDomains.containsKey(raw['domain'])
                      ? raw['domain'] as String
                      : 'communication',
              text: '${raw['text'] ?? ''}',
            ),
      ];
      _questions = [];
    } else {
      _questions = [
        for (final raw in list)
          if (raw is Map) _Question.from(TemplateQuestion.fromJson(raw)),
      ];
      _home = [];
    }
  }

  /// Replaces the questions with the ones the app ships with, as a starting
  /// point.
  Future<void> _startFromBuiltIn() async {
    if ((_home.isNotEmpty || _questions.isNotEmpty) &&
        !await _confirmReplace(
          'Replace these questions with sample questions?',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      if (_kind == TemplateKind.home) {
        _loadItems(kDefaultHomeTemplate['items']);
        if (_title.isEmpty) _title = kDefaultHomeTemplate['title'] as String;
        if (_intro.isEmpty) _intro = kDefaultHomeTemplate['intro'] as String;
      } else {
        final t = defaultChoiceTemplate(_kind);
        _loadItems(t.itemsJson());
        if (_title.isEmpty) _title = t.title;
        if (_intro.isEmpty) _intro = t.intro;
      }
      _generation++;
    });
  }

  Future<bool> _confirmReplace(String title) async =>
      await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(title),
              content: const Text(
                'The questions currently in this editor will be replaced.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep editing'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Replace questions'),
                ),
              ],
            ),
      ) ??
      false;

  Future<void> _changeKind(TemplateKind kind) async {
    if (kind == _kind) return;
    if ((_home.isNotEmpty || _questions.isNotEmpty) &&
        !await _confirmReplace('Change when these questions are asked?')) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _kind = kind;
      _loadItems(const []);
      _generation++;
    });
  }

  void _showPreview() {
    showDialog<void>(
      context: context,
      builder:
          (context) => Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  tooltip: 'Close preview',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text('Preview as a parent'),
              ),
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _preview(),
                ),
              ),
            ),
          ),
    );
  }

  /// The questions as template rows store them. A question without an id
  /// gets one from its wording that no other question uses.
  List<Object?> get _itemsJson {
    if (_kind == TemplateKind.home) {
      final taken = {
        for (final i in _home)
          if (i.id.isNotEmpty) i.id,
      };
      return [
        for (var k = 0; k < _home.length; k++)
          _home[k].toJson(
            _home[k].id.isNotEmpty
                ? _home[k].id
                : uniqueSlug(
                  _home[k].text,
                  taken,
                  fallback: 'question_${k + 1}',
                ),
          ),
      ];
    }
    final taken = {
      for (final q in _questions)
        if (q.id.isNotEmpty) q.id,
    };
    return [
      for (var k = 0; k < _questions.length; k++)
        _questions[k].toJson(
          _questions[k].id.isNotEmpty
              ? _questions[k].id
              : uniqueSlug(
                _questions[k].text,
                taken,
                fallback: 'question_${k + 1}',
              ),
        ),
    ];
  }

  bool get _isNewQuestionnaire =>
      !_editingInPlace && widget.asNewVersionOf == null;

  List<String> get _errors => [
    if (_title.trim().isEmpty) 'Give it a title parents will see.',
    ...(_kind == TemplateKind.home
        ? validateHomeItems(_itemsJson)
        : ChoiceTemplate.validateItems(_kind, _itemsJson)),
  ];

  Future<void> _save() async {
    if (_errors.isNotEmpty || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final fields = <String, dynamic>{
      'kind': _kind.key,
      'questionnaire_type': _scope.key,
      'title': _title.trim(),
      'intro': _intro.trim(),
      'items': _itemsJson,
    };
    try {
      if (_editingInPlace) {
        await widget.api.updateTemplate('${widget.existing!['id']}', fields);
      } else if (_isNewQuestionnaire) {
        await _insertUnderFreeName(fields);
      } else {
        await widget.api.insertTemplate({
          ...fields,
          'template_key': _key,
          'version': _version,
        });
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError =
            '$e'.contains('duplicate key')
                ? 'Version $_version of this questionnaire was already saved. '
                    'Go back and start a new version from the latest one.'
                : 'Could not save: $e';
      });
    }
  }

  /// Saves a brand-new questionnaire under a name made from its title.
  ///
  /// Names already in the list are skipped up front. A practitioner cannot
  /// see other practitioners' drafts, so a clash the database reports is
  /// skipped too and the save retried.
  Future<void> _insertUnderFreeName(Map<String, dynamic> fields) async {
    final taken = <String>{
      kDefaultHomeTemplate['template_key'] as String,
      kDefaultIntakeTemplate.key,
      kDefaultObservationTemplate.key,
    };
    try {
      for (final t in await widget.api.templates()) {
        taken.add('${t['template_key']}');
      }
    } catch (_) {
      // The database still rejects a clash, and the retries below skip it.
    }
    for (var attempt = 0; ; attempt++) {
      _key = uniqueSlug(
        _title,
        taken,
        fallback: 'questionnaire',
        maxLength: 40,
      );
      try {
        await widget.api.insertTemplate({
          ...fields,
          'template_key': _key,
          'version': _version,
        });
        return;
      } catch (e) {
        if (!'$e'.contains('duplicate key') || attempt >= 4) rethrow;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final errors = _errors;
    final wasActive = widget.existing?['is_active'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editingInPlace
              ? 'Edit questionnaire'
              : widget.asNewVersionOf != null
              ? 'New version'
              : 'New questionnaire',
        ),
        actions: [
          IconButton(
            key: const Key('editor.openPreview'),
            onPressed: _saving ? null : _showPreview,
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'Preview as a parent',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              key: const Key('editor.save'),
              onPressed: errors.isEmpty && !_saving ? _save : null,
              icon: const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final form = _form(errors, wasActive);
          if (constraints.maxWidth < 1100) return form;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: form),
              const VerticalDivider(width: 1),
              Expanded(flex: 2, child: _preview()),
            ],
          );
        },
      ),
    );
  }

  Widget _form(List<String> errors, bool wasActive) {
    return ListView(
      key: ValueKey('editor.form.$_generation'),
      padding: const EdgeInsets.all(24),
      children: [
        if (wasActive && !widget.isAdmin)
          const _Notice(
            icon: Icons.info_outline_rounded,
            text:
                'This questionnaire is in use. Saving a change takes it out '
                'of use until an administrator reviews and activates it '
                'again; parents see the built-in questions meanwhile.',
          ),
        if (!widget.isAdmin)
          const _Notice(
            icon: Icons.verified_user_outlined,
            text:
                'An administrator reviews every questionnaire before parents '
                'see it.',
          ),
        Text(
          '1. Questionnaire details',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        const Text('When will parents answer these questions?'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 290,
              child: DropdownButtonFormField<TemplateKind>(
                isExpanded: true,
                key: const Key('editor.kind'),
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Question set',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final k in TemplateKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged:
                    _editingInPlace || widget.asNewVersionOf != null
                        ? null
                        : (kind) async {
                          if (kind != null) await _changeKind(kind);
                          // Restore the selection if the practitioner kept their questions.
                          if (mounted) setState(() => _generation++);
                        },
              ),
            ),
            SizedBox(
              width: 290,
              child: DropdownButtonFormField<AssessmentScope>(
                isExpanded: true,
                key: const Key('editor.scope'),
                initialValue: _scope,
                decoration: const InputDecoration(
                  labelText: 'Use for',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in AssessmentScope.values)
                    DropdownMenuItem(value: s, child: Text(s.labelFor(_kind))),
                ],
                onChanged: (s) => setState(() => _scope = s ?? _scope),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(switch (_kind) {
          TemplateKind.home =>
            'Statements the parent rates from Never to Always, about the '
                'child at home. Each belongs to one of the four areas the '
                'games measure.',
          TemplateKind.intake =>
            'Asked of the adult who will watch, before the first game. The '
                'app asks who is watching today. Mark background questions '
                'for reuse and current-session questions to ask each time.',
          TemplateKind.observation =>
            'Asked of the adult after the last game, before any result. '
                'Session questions form a short check-in. Game questions '
                'are shown only for games the adult selects for extra details; '
                'flags appear beside results without changing scores.',
        }, style: Theme.of(context).textTheme.bodySmall),
        if (!_isNewQuestionnaire) ...[
          const SizedBox(height: 4),
          Text(
            'Version $_version',
            key: const Key('editor.version'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey('editor.title.$_generation'),
          initialValue: _title,
          decoration: const InputDecoration(
            labelText: 'Questionnaire title',
            hintText: 'My Child’s Everyday Skills',
            helperText:
                'Parents see this title. Use ordinary words and spaces.',
            helperMaxLines: 2,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _title = v),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('editor.intro.$_generation'),
          initialValue: _intro,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Instructions for parents (optional)',
            hintText:
                'Think about your child’s activities over the last two weeks.',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _intro = v),
        ),
        const SizedBox(height: 24),
        Text(
          '2. Write questions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Write one clear idea per question. Use familiar words and describe something a parent can observe.',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('editor.builtIn'),
            onPressed: _saving ? null : _startFromBuiltIn,
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: const Text('Start with sample questions'),
          ),
        ),
        if (_kind == TemplateKind.home) ...[
          const SizedBox(height: 12),
          const Text('Include at least one question in each skill area.'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final area in kHomeDomains.entries)
                Chip(
                  avatar: Icon(
                    _home.any((item) => item.domain == area.key)
                        ? Icons.check_circle_outline
                        : Icons.add_circle_outline,
                    size: 18,
                  ),
                  label: Text(
                    '${area.value}: ${_home.where((item) => item.domain == area.key).length}',
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        if (_kind == TemplateKind.home)
          ..._homeEditors()
        else
          ..._questionEditors(),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('editor.addQuestion'),
            onPressed:
                () => setState(() {
                  if (_kind == TemplateKind.home) {
                    _home.add(_HomeItem());
                  } else {
                    _questions.add(
                      _Question(
                        scope:
                            _kind == TemplateKind.observation
                                ? QuestionScope.game
                                : QuestionScope.session,
                      ),
                    );
                  }
                }),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add question'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '3. Preview and save',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Try the questions as a parent before saving. Preview answers are never recorded.',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _showPreview,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Preview as a parent'),
          ),
        ),
        const SizedBox(height: 12),
        if (errors.isNotEmpty)
          Card(
            key: const Key('editor.errors'),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fix these before saving',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  for (final e in errors) Text('• $e'),
                ],
              ),
            ),
          ),
        if (_saveError != null) ...[
          const SizedBox(height: 12),
          Text(
            _saveError!,
            key: const Key('editor.saveError'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  void _removeQuestion<T>(List<T> list, int index) {
    final removed = list[index];
    setState(() {
      list.removeAt(index);
      _generation++;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Question ${index + 1} removed.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted ||
                (!identical(list, _home) && !identical(list, _questions))) {
              return;
            }
            setState(() {
              list.insert(index.clamp(0, list.length), removed);
              _generation++;
            });
          },
        ),
      ),
    );
  }

  Widget _moveButtons<T>(List<T> list, int index) => Wrap(
    children: [
      IconButton(
        tooltip: 'Move up',
        onPressed:
            index == 0
                ? null
                : () => setState(() {
                  list.insert(index - 1, list.removeAt(index));
                  _generation++;
                }),
        icon: const Icon(Icons.arrow_upward_rounded),
      ),
      IconButton(
        tooltip: 'Move down',
        onPressed:
            index == list.length - 1
                ? null
                : () => setState(() {
                  list.insert(index + 1, list.removeAt(index));
                  _generation++;
                }),
        icon: const Icon(Icons.arrow_downward_rounded),
      ),
      IconButton(
        tooltip: 'Duplicate question',
        onPressed:
            () => setState(() {
              if (identical(list, _home)) {
                final item = _home[index];
                _home.insert(
                  index + 1,
                  _HomeItem(domain: item.domain, text: item.text),
                );
              } else {
                final q = _questions[index];
                _questions.insert(
                  index + 1,
                  _Question(
                    text: q.text,
                    type: q.type,
                    scope: q.scope,
                    required: q.required,
                    shortLabel: q.shortLabel,
                    timing: q.timing,
                    options: [
                      for (final o in q.options)
                        _Option(
                          label: o.label,
                          flag: o.flag,
                          quiet: o.quiet,
                          exclusive: o.exclusive,
                        ),
                    ],
                  ),
                );
              }
              _generation++;
            }),
        icon: const Icon(Icons.copy_outlined),
      ),
      IconButton(
        tooltip: 'Remove question',
        onPressed: () => _removeQuestion(list, index),
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    ],
  );

  List<Widget> _homeEditors() => [
    for (var i = 0; i < _home.length; i++)
      Card(
        key: ValueKey('editor.home.$_generation.$i'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Question ${i + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  _moveButtons(_home, i),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _home[i].domain,
                decoration: InputDecoration(
                  labelText: 'Skill area',
                  helperText: _areaHelp[_home[i].domain],
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final d in kHomeDomains.entries)
                    DropdownMenuItem(value: d.key, child: Text(d.value)),
                ],
                onChanged:
                    (v) =>
                        setState(() => _home[i].domain = v ?? _home[i].domain),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: ObjectKey(_home[i]),
                initialValue: _home[i].text,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Statement parents will rate',
                  hintText: 'My child responds when I call their name.',
                  errorText:
                      _home[i].text.trim().isEmpty
                          ? 'Write a statement for Question ${i + 1}.'
                          : null,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onChanged: (v) => setState(() => _home[i].text = v),
              ),
              const SizedBox(height: 12),
              Text(
                'Parents answer: Never · Rarely · Sometimes · Often · Always',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
  ];

  List<Widget> _questionEditors() => [
    for (var i = 0; i < _questions.length; i++)
      _QuestionEditor(
        key: ValueKey('editor.question.$_generation.$i'),
        number: i + 1,
        question: _questions[i],
        allowPerGame: _kind == TemplateKind.observation,
        allowReuse: _kind == TemplateKind.intake,
        actions: _moveButtons(_questions, i),
        onChanged: () => setState(() {}),
      ),
  ];

  Widget _preview() => _ParentPreview(
    title: _title,
    intro: _intro,
    kind: _kind,
    home: _home,
    questions: _questions,
  );
}

class _ParentPreview extends StatefulWidget {
  const _ParentPreview({
    required this.title,
    required this.intro,
    required this.kind,
    required this.home,
    required this.questions,
  });
  final String title;
  final String intro;
  final TemplateKind kind;
  final List<_HomeItem> home;
  final List<_Question> questions;

  @override
  State<_ParentPreview> createState() => _ParentPreviewState();
}

class _ParentPreviewState extends State<_ParentPreview> {
  final Map<Object, Set<Object>> _answers = {};

  Widget _choices(
    Object question,
    List<(Object, String)> choices, {
    bool multiple = false,
    Set<Object> exclusive = const {},
  }) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final choice in choices)
        FilterChip(
          label: Text(choice.$2.isEmpty ? 'Answer' : choice.$2),
          selected: _answers[question]?.contains(choice.$1) ?? false,
          onSelected:
              (selected) => setState(() {
                final answers = _answers.putIfAbsent(question, () => {});
                if (!multiple || exclusive.contains(choice.$1)) answers.clear();
                if (selected) {
                  answers.removeAll(exclusive);
                  answers.add(choice.$1);
                } else {
                  answers.remove(choice.$1);
                }
              }),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('editor.preview'),
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Parent preview',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      const Text(
        'Try selecting answers. This preview does not save responses.',
      ),
      const SizedBox(height: 20),
      Text(
        widget.title.isEmpty ? 'Your questionnaire title' : widget.title,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      if (widget.intro.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(widget.intro),
      ],
      const SizedBox(height: 24),
      if (widget.kind == TemplateKind.home)
        for (final item in widget.home) ...[
          Text(item.text.isEmpty ? 'Your statement appears here' : item.text),
          const SizedBox(height: 8),
          _choices(item, [
            for (final rating in [
              'Never',
              'Rarely',
              'Sometimes',
              'Often',
              'Always',
            ])
              (rating, rating),
          ]),
          const SizedBox(height: 24),
        ]
      else ...[
        if (widget.kind == TemplateKind.intake) ...[
          const Text('Who is watching?'),
          const SizedBox(height: 8),
          _choices('watcher', [
            for (final role in [
              'Parent',
              'Guardian',
              'SPED teacher',
              'Therapist',
            ])
              (role, role),
          ]),
          const SizedBox(height: 24),
        ],
        for (final scope in [QuestionScope.game, QuestionScope.session])
          for (final q in widget.questions.where((q) => q.scope == scope)) ...[
            if (scope == QuestionScope.game)
              const Text(
                'Asked only for games the parent selects for extra details',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            if (widget.kind == TemplateKind.intake)
              Text(
                q.timing.label,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            Text(
              '${q.text.isEmpty ? 'Your question appears here' : q.text}${q.required ? ' (required)' : ''}',
            ),
            const SizedBox(height: 8),
            if (q.type == QuestionType.text)
              TextField(
                key: ObjectKey(q),
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Your answer',
                  border: OutlineInputBorder(),
                ),
              )
            else
              _choices(
                q,
                [for (final o in q.options) (o, o.label)],
                multiple: q.type == QuestionType.multi,
                exclusive: {
                  for (final o in q.options)
                    if (o.exclusive) o,
                },
              ),
            const SizedBox(height: 24),
          ],
      ],
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _QuestionEditor extends StatelessWidget {
  const _QuestionEditor({
    super.key,
    required this.number,
    required this.question,
    required this.allowPerGame,
    required this.allowReuse,
    required this.actions,
    required this.onChanged,
  });

  final int number;
  final _Question question;
  final bool allowPerGame;
  final bool allowReuse;
  final Widget actions;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final q = question;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Question $number',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                actions,
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: q.text,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Question parents will answer',
                errorText:
                    q.text.trim().isEmpty
                        ? 'Write a question for Question $number.'
                        : null,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              onChanged: (v) {
                q.text = v;
                onChanged();
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<QuestionType>(
                    isExpanded: true,
                    initialValue: q.type,
                    decoration: const InputDecoration(
                      labelText: 'How will parents answer?',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final t in QuestionType.values)
                        DropdownMenuItem(
                          value: t,
                          child: Text(
                            t == QuestionType.multi
                                ? 'Choose several answers'
                                : t.label,
                          ),
                        ),
                    ],
                    onChanged: (t) {
                      q.type = t ?? q.type;
                      if (q.type != QuestionType.text && q.options.length < 2) {
                        q.options.addAll([
                          for (var i = q.options.length; i < 2; i++) _Option(),
                        ]);
                      }
                      onChanged();
                    },
                  ),
                ),
                if (allowReuse)
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<AnswerTiming>(
                      key: Key('editor.timing.$number'),
                      initialValue: q.timing,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'When to ask',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final timing in AnswerTiming.values)
                          DropdownMenuItem(
                            value: timing,
                            child: Text(timing.label),
                          ),
                      ],
                      onChanged: (value) {
                        q.timing = value ?? AnswerTiming.background;
                        onChanged();
                      },
                    ),
                  ),
                if (allowPerGame)
                  SizedBox(
                    width: 250,
                    child: DropdownButtonFormField<QuestionScope>(
                      isExpanded: true,
                      initialValue: q.scope,
                      decoration: const InputDecoration(
                        labelText: 'Ask this question',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in QuestionScope.values)
                          DropdownMenuItem(value: s, child: Text(s.label)),
                      ],
                      onChanged: (s) {
                        q.scope = s ?? q.scope;
                        onChanged();
                      },
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: q.required,
                      onChanged: (v) {
                        q.required = v ?? false;
                        onChanged();
                      },
                    ),
                    const Text('Answer required'),
                  ],
                ),
              ],
            ),
            if (q.type != QuestionType.text) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Additional question settings'),
                children: [
                  TextFormField(
                    initialValue: q.shortLabel,
                    decoration: const InputDecoration(
                      labelText: 'Short name in results (optional)',
                      hintText: 'Therapy',
                      helperText:
                          'A short heading shown with this answer in the results summary.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      q.shortLabel = v;
                      onChanged();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
              Text('Answers', style: Theme.of(context).textTheme.labelLarge),
              for (var j = 0; j < q.options.length; j++)
                _OptionEditor(
                  key: ObjectKey(q.options[j]),
                  option: q.options[j],
                  allowExclusive: q.type == QuestionType.multi,
                  onRemove: () {
                    q.options.removeAt(j);
                    onChanged();
                  },
                  onChanged: onChanged,
                ),
              TextButton.icon(
                onPressed: () {
                  q.options.add(_Option());
                  onChanged();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add answer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionEditor extends StatelessWidget {
  const _OptionEditor({
    super.key,
    required this.option,
    required this.allowExclusive,
    required this.onRemove,
    required this.onChanged,
  });

  final _Option option;
  final bool allowExclusive;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final o = option;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: o.label,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Answer choice',
                    errorText:
                        o.label.trim().isEmpty
                            ? 'Write an answer choice.'
                            : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    o.label = v;
                    onChanged();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Remove answer',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Additional answer settings'),
            children: [
              TextFormField(
                initialValue: o.flag,
                decoration: const InputDecoration(
                  labelText: 'Highlight in results (optional)',
                  hintText: 'Played with help',
                  helperText:
                      'Show this note beside the game’s score when this answer is chosen. It does not change the score.',
                  helperMaxLines: 3,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  o.flag = v;
                  onChanged();
                },
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Leave out of results summary'),
                subtitle: const Text(
                  'Useful for answers such as “Prefer not to say”.',
                ),
                value: o.quiet,
                onChanged: (v) {
                  o.quiet = v ?? false;
                  onChanged();
                },
              ),
              if (allowExclusive)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Cannot be selected with other answers'),
                  subtitle: const Text(
                    'Useful for “None”. Choosing it clears other selections.',
                  ),
                  value: o.exclusive,
                  onChanged: (v) {
                    o.exclusive = v ?? false;
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
