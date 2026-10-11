import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:questionnaire_core/questionnaire_core.dart';

import '../data/questionnaire_api.dart';
import 'template_editor_page.dart';

/// The questionnaires parents answer around an assessment (AUM-352): the
/// home questionnaire, "Before your child starts" and "What did you see?".
///
/// Approved practitioners write and edit their own. Administrators see
/// every template, review it, and choose which one is in use — at most one
/// per question set and assessment type. With none in use the app asks its
/// built-in questions.
class QuestionnairesPage extends StatefulWidget {
  const QuestionnairesPage({
    super.key,
    required this.api,
    required this.isAdmin,
  });

  final QuestionnaireApi api;
  final bool isAdmin;

  @override
  State<QuestionnairesPage> createState() => _QuestionnairesPageState();
}

class _QuestionnairesPageState extends State<QuestionnairesPage> {
  List<Map<String, dynamic>> _templates = const [];
  Map<String, String> _authors = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final templates = await widget.api.templates();
      var authors = <String, String>{};
      if (widget.isAdmin) {
        authors = {
          for (final p in await widget.api.practitioners())
            '${p['user_id']}': '${p['full_name']} (${p['profession']})',
        };
      }
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _authors = authors;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load questionnaires: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openEditor({
    Map<String, dynamic>? existing,
    Map<String, dynamic>? copyOf,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder:
            (_) => TemplateEditorPage(
              api: widget.api,
              isAdmin: widget.isAdmin,
              existing: existing,
              asNewVersionOf: copyOf,
            ),
      ),
    );
    if (saved == true) {
      _snack(
        widget.isAdmin
            ? 'Saved. Activate this questionnaire when it is ready for parents.'
            : 'Saved. An administrator must review and activate this questionnaire before parents see it.',
      );
      _load();
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      _snack(done);
      _load();
    } catch (e) {
      _snack('That did not work: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _mine(Map<String, dynamic> t) => t['authored_by'] == widget.api.userId;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Questionnaires', style: theme.textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('questionnaires.new'),
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New questionnaire'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.isAdmin
                ? 'Review what practitioners write, then choose which '
                    'questionnaire is in use. With none in use, the app '
                    'asks its built-in questions.'
                : 'Write the questions parents, guardians and teachers '
                    'answer around an assessment. An administrator reviews '
                    'each one before parents see it.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                for (final kind in TemplateKind.values) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 4),
                    child: Text(kind.label, style: theme.textTheme.titleLarge),
                  ),
                  ..._rows(kind),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _rows(TemplateKind kind) {
    final rows = [
      for (final t in _templates)
        if ((TemplateKind.fromKey(t['kind']) ?? TemplateKind.home) == kind) t,
    ];
    return [_builtInRow(kind, rows), for (final t in rows) _row(t)];
  }

  /// The questions the app ships with, as a template row. They live in the
  /// app, not the database, so they are shown here to read and copy.
  static Map<String, dynamic> builtInRow(TemplateKind kind) {
    if (kind == TemplateKind.home) {
      return {
        ...kDefaultHomeTemplate,
        'kind': kind.key,
        'questionnaire_type': AssessmentScope.both.key,
        'version': 1,
      };
    }
    final t = defaultChoiceTemplate(kind);
    return {
      'kind': kind.key,
      'questionnaire_type': AssessmentScope.both.key,
      'template_key': t.key,
      'version': t.version,
      'title': t.title,
      'intro': t.intro,
      'items': t.itemsJson(),
    };
  }

  Widget _builtInRow(TemplateKind kind, List<Map<String, dynamic>> rows) {
    final builtIn = builtInRow(kind);
    final replaced = {
      for (final t in rows)
        if (t['is_active'] == true)
          AssessmentScope.fromKey(t['questionnaire_type']),
    };
    final String use;
    if (replaced.contains(AssessmentScope.both) ||
        (replaced.contains(AssessmentScope.pre) &&
            replaced.contains(AssessmentScope.post))) {
      use = 'Not in use — replaced below';
    } else if (replaced.contains(AssessmentScope.pre)) {
      use = AssessmentScope.post.inUseFor(kind);
    } else if (replaced.contains(AssessmentScope.post)) {
      use = AssessmentScope.pre.inUseFor(kind);
    } else {
      use = 'In use';
    }
    final inUse = !use.startsWith('Not');
    return Card(
      key: Key('questionnaires.builtIn.${kind.key}'),
      child: ListTile(
        leading: Icon(
          inUse ? Icons.check_circle_rounded : Icons.inventory_2_outlined,
          color: inUse ? Colors.green : null,
        ),
        title: Text('${builtIn['title']}  ·  built into the app'),
        subtitle: Text(
          [
            AssessmentScope.both.labelFor(kind),
            '${(builtIn['items'] as List).length} questions',
            use,
            'Not yet expert-validated',
          ].join(' · '),
        ),
        trailing: TextButton.icon(
          key: Key('questionnaires.builtIn.edit.${kind.key}'),
          onPressed: () => _openEditor(copyOf: builtIn),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('View and edit a copy'),
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> t) {
    final active = t['is_active'] == true;
    final validated = t['status'] == 'validated';
    final kind = TemplateKind.fromKey(t['kind']) ?? TemplateKind.home;
    final scope =
        AssessmentScope.fromKey(t['questionnaire_type'])?.labelFor(kind) ??
        '${t['questionnaire_type']}';
    final items = t['items'] is List ? (t['items'] as List).length : 0;
    final updated = DateTime.tryParse('${t['updated_at']}');
    final canEdit = widget.isAdmin || _mine(t);
    return Card(
      key: Key('questionnaires.row.${t['id']}'),
      child: ListTile(
        leading: Icon(
          active ? Icons.check_circle_rounded : Icons.description_outlined,
          color: active ? Colors.green : null,
        ),
        title: Text('${t['title']}  ·  Version ${t['version']}'),
        subtitle: Text(
          [
            scope,
            '$items questions',
            if (active) 'In use' else 'Not in use',
            if (validated) 'Validated' else 'Draft',
            if (widget.isAdmin && _authors[t['authored_by']] != null)
              'By ${_authors[t['authored_by']]}',
            if (updated != null)
              'Updated ${DateFormat('MMM d, y').format(updated.toLocal())}',
          ].join(' · '),
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (canEdit && !active)
              IconButton(
                key: Key('questionnaires.edit.${t['id']}'),
                tooltip: 'Edit',
                onPressed: () => _openEditor(existing: t),
                icon: const Icon(Icons.edit_rounded),
              ),
            TextButton.icon(
              key: Key('questionnaires.copy.${t['id']}'),
              onPressed: () => _openEditor(copyOf: t),
              icon: const Icon(Icons.copy_rounded),
              label: Text(active ? 'Create a revised version' : 'New version'),
            ),
            if (widget.isAdmin) ...[
              TextButton(
                key: Key('questionnaires.validate.${t['id']}'),
                onPressed:
                    () => _run(
                      () => widget.api.setStatus(
                        '${t['id']}',
                        validated ? 'draft' : 'validated',
                      ),
                      validated ? 'Marked as draft.' : 'Marked as validated.',
                    ),
                child: Text(validated ? 'Mark draft' : 'Mark validated'),
              ),
              FilledButton.tonal(
                key: Key('questionnaires.activate.${t['id']}'),
                onPressed:
                    () => _run(
                      () => widget.api.setActive(t, !active),
                      active
                          ? 'Taken out of use. The app asks its built-in '
                              'questions.'
                          : 'Now in use for new assessments.',
                    ),
                child: Text(active ? 'Stop using' : 'Use this'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
