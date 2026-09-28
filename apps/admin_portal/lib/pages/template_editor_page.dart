import 'package:flutter/material.dart';
import 'package:questionnaire_core/questionnaire_core.dart';

import '../data/questionnaire_api.dart';

/// Writes or edits one questionnaire template (AUM-352): the home
/// questionnaire, "Before your child starts" or "What did you see?".
///
/// Uses the same validation the app runs before showing a template, so
/// anything this page saves is something the app will use. Pops `true`
/// after a save.
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

  String id;
  String domain;
  String text;

  Map<String, Object?> toJson() => {'id': id.trim(), 'domain': domain, 'text': text.trim()};
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

  String id;
  String label;
  String flag;
  bool quiet;
  bool exclusive;

  Map<String, Object?> toJson() => ChoiceOption(
    id: id.trim(),
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
    List<_Option>? options,
  }) : options = options ?? [_Option(), _Option()];

  factory _Question.from(TemplateQuestion q) => _Question(
    id: q.id,
    text: q.text,
    type: q.type,
    scope: q.scope,
    required: q.required,
    shortLabel: q.shortLabel ?? '',
    options: [for (final o in q.options) _Option.from(o)],
  );

  String id;
  String text;
  QuestionType type;
  QuestionScope scope;
  bool required;
  String shortLabel;
  List<_Option> options;

  Map<String, Object?> toJson() => {
    'id': id.trim(),
    'text': text.trim(),
    'type': type.key,
    'scope': scope.key,
    if (required) 'required': true,
    if (shortLabel.trim().isNotEmpty) 'short_label': shortLabel.trim(),
    if (type != QuestionType.text)
      'options': [for (final o in options) o.toJson()],
  };
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
    _scope = AssessmentScope.fromKey(source['questionnaire_type']) ??
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
              domain: kHomeDomains.containsKey(raw['domain'])
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
  void _startFromBuiltIn() {
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

  List<Object?> get _itemsJson => _kind == TemplateKind.home
      ? [for (final i in _home) i.toJson()]
      : [for (final q in _questions) q.toJson()];

  List<String> get _errors => [
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(_key.trim()))
      'Give the questionnaire a name of lowercase letters, numbers and _ '
          '(for example sped_parent_checklist).',
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
      } else {
        await widget.api.insertTemplate({
          ...fields,
          'template_key': _key.trim(),
          'version': _version,
        });
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '$e'.contains('duplicate key')
            ? 'Version $_version of "${_key.trim()}" already exists. '
                'Use a different name or version.'
            : 'Could not save: $e';
      });
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
          TextButton.icon(
            key: const Key('editor.builtIn'),
            onPressed: _saving ? null : _startFromBuiltIn,
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: const Text('Start from the built-in questions'),
          ),
          const SizedBox(width: 8),
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
        Wrap(
          spacing: 16,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<TemplateKind>(
              key: const Key('editor.kind'),
              segments: [
                for (final k in TemplateKind.values)
                  ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {_kind},
              // Which set a template is cannot change once it exists; its
              // questions would not fit the other kind.
              onSelectionChanged:
                  _editingInPlace || widget.asNewVersionOf != null
                      ? null
                      : (s) => setState(() {
                        _kind = s.single;
                        _loadItems(const []);
                        _generation++;
                      }),
            ),
            DropdownButton<AssessmentScope>(
              key: const Key('editor.scope'),
              value: _scope,
              items: [
                for (final s in AssessmentScope.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (s) => setState(() => _scope = s ?? _scope),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          switch (_kind) {
            TemplateKind.home =>
              'Statements the parent rates from Never to Always, about the '
                  'child at home. Each belongs to one of the four areas the '
                  'games measure.',
            TemplateKind.intake =>
              'Asked of the adult who will watch, before the first game. The '
                  'app always asks who is watching first; these questions '
                  'follow.',
            TemplateKind.observation =>
              'Asked of the adult after the last game, before any result. '
                  '"For each game" questions repeat for every game played; '
                  'answers with a flag are highlighted beside that game\'s '
                  'score.',
          },
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                key: const Key('editor.key'),
                initialValue: _key,
                enabled: !_editingInPlace && widget.asNewVersionOf == null,
                decoration: const InputDecoration(
                  labelText: 'Name (lowercase, e.g. sped_parent_checklist)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _key = v),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Version',
                  border: OutlineInputBorder(),
                ),
                child: Text('$_version'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('editor.title.$_generation'),
          initialValue: _title,
          decoration: const InputDecoration(
            labelText: 'Title parents see',
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
            labelText: 'Introduction',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _intro = v),
        ),
        const SizedBox(height: 24),
        Text('Questions', style: Theme.of(context).textTheme.titleLarge),
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
            onPressed: () => setState(() {
              if (_kind == TemplateKind.home) {
                _home.add(_HomeItem());
              } else {
                _questions.add(
                  _Question(
                    scope: _kind == TemplateKind.observation
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

  Widget _moveButtons<T>(List<T> list, int index) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Move up',
        onPressed: index == 0
            ? null
            : () => setState(() {
                list.insert(index - 1, list.removeAt(index));
                _generation++;
              }),
        icon: const Icon(Icons.arrow_upward_rounded),
      ),
      IconButton(
        tooltip: 'Move down',
        onPressed: index == list.length - 1
            ? null
            : () => setState(() {
                list.insert(index + 1, list.removeAt(index));
                _generation++;
              }),
        icon: const Icon(Icons.arrow_downward_rounded),
      ),
      IconButton(
        tooltip: 'Remove',
        onPressed: () => setState(() {
          list.removeAt(index);
          _generation++;
        }),
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    ],
  );

  List<Widget> _homeEditors() => [
    for (var i = 0; i < _home.length; i++)
      Card(
        key: ValueKey('editor.home.$_generation.$i'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 160,
                child: TextFormField(
                  initialValue: _home[i].id,
                  decoration: const InputDecoration(labelText: 'Id'),
                  onChanged: (v) => setState(() => _home[i].id = v),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _home[i].domain,
                items: [
                  for (final d in kHomeDomains.entries)
                    DropdownMenuItem(value: d.key, child: Text(d.value)),
                ],
                onChanged: (v) =>
                    setState(() => _home[i].domain = v ?? _home[i].domain),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: _home[i].text,
                  decoration: const InputDecoration(
                    labelText: 'Statement, e.g. "My child responds when I '
                        'call their name."',
                  ),
                  onChanged: (v) => setState(() => _home[i].text = v),
                ),
              ),
              _moveButtons(_home, i),
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
        actions: _moveButtons(_questions, i),
        onChanged: () => setState(() {}),
      ),
  ];

  /// Roughly how the questions read in the app.
  Widget _preview() {
    final theme = Theme.of(context);
    Widget chips(List<String> labels) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final l in labels)
          Chip(label: Text(l.isEmpty ? '…' : l), visualDensity: VisualDensity.compact),
      ],
    );
    return ListView(
      key: const Key('editor.preview'),
      padding: const EdgeInsets.all(24),
      children: [
        Text('Preview', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Text(_title.isEmpty ? 'Title' : _title, style: theme.textTheme.titleLarge),
        if (_intro.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(_intro),
        ],
        const SizedBox(height: 16),
        if (_kind == TemplateKind.home)
          for (final i in _home)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.text.isEmpty ? '…' : i.text),
                  const SizedBox(height: 4),
                  chips(const ['Never', 'Rarely', 'Sometimes', 'Often', 'Always']),
                ],
              ),
            )
        else ...[
          if (_kind == TemplateKind.intake) ...[
            const Text('Who is watching?'),
            const SizedBox(height: 4),
            chips(const ['Parent', 'Guardian', 'SPED teacher', 'Therapist']),
            const SizedBox(height: 12),
          ],
          for (final scope in [QuestionScope.game, QuestionScope.session])
            for (final q in _questions.where((q) => q.scope == scope))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${scope == QuestionScope.game ? '[each game] ' : ''}'
                      '${q.text.isEmpty ? '…' : q.text}'
                      '${q.required ? ' *' : ''}',
                    ),
                    const SizedBox(height: 4),
                    if (q.type == QuestionType.text)
                      const TextField(
                        enabled: false,
                        decoration: InputDecoration(border: OutlineInputBorder()),
                      )
                    else
                      chips([for (final o in q.options) o.label]),
                  ],
                ),
              ),
        ],
      ],
    );
  }
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
    required this.actions,
    required this.onChanged,
  });

  final int number;
  final _Question question;
  final bool allowPerGame;
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
            Row(
              children: [
                Text('Question $number',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                actions,
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 160,
                  child: TextFormField(
                    initialValue: q.id,
                    decoration: const InputDecoration(labelText: 'Id'),
                    onChanged: (v) {
                      q.id = v;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: q.text,
                    decoration: const InputDecoration(labelText: 'Wording'),
                    onChanged: (v) {
                      q.text = v;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<QuestionType>(
                  value: q.type,
                  items: [
                    for (final t in QuestionType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
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
                if (allowPerGame)
                  DropdownButton<QuestionScope>(
                    value: q.scope,
                    items: [
                      for (final s in QuestionScope.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (s) {
                      q.scope = s ?? q.scope;
                      onChanged();
                    },
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
                if (q.type != QuestionType.text)
                  SizedBox(
                    width: 220,
                    child: TextFormField(
                      initialValue: q.shortLabel,
                      decoration: const InputDecoration(
                        labelText: 'Label in results (optional)',
                        hintText: 'e.g. Therapy',
                      ),
                      onChanged: (v) {
                        q.shortLabel = v;
                        onChanged();
                      },
                    ),
                  ),
              ],
            ),
            if (q.type != QuestionType.text) ...[
              const SizedBox(height: 8),
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
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: TextFormField(
              initialValue: o.id,
              decoration: const InputDecoration(labelText: 'Id'),
              onChanged: (v) {
                o.id = v;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: o.label,
              decoration: const InputDecoration(labelText: 'Label'),
              onChanged: (v) {
                o.label = v;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: o.flag,
              decoration: const InputDecoration(
                labelText: 'Flag on results (optional)',
                hintText: 'e.g. Played with help',
              ),
              onChanged: (v) {
                o.flag = v;
                onChanged();
              },
            ),
          ),
          Tooltip(
            message: 'Leave this answer out of the results summary',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: o.quiet,
                  onChanged: (v) {
                    o.quiet = v ?? false;
                    onChanged();
                  },
                ),
                const Text('Hide'),
              ],
            ),
          ),
          if (allowExclusive)
            Tooltip(
              message: 'Choosing this clears the other answers (like "None")',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: o.exclusive,
                    onChanged: (v) {
                      o.exclusive = v ?? false;
                      onChanged();
                    },
                  ),
                  const Text('Only'),
                ],
              ),
            ),
          IconButton(
            tooltip: 'Remove answer',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
