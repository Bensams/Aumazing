import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Rubric threshold editing (Section B FR: "update or adjust the rubric
/// scoring thresholds used for assigning skill labels").
///
/// Edits the singleton `rubric_thresholds` row. The mobile app fetches
/// these values at startup (with the previous hardcoded values as offline
/// defaults), so changes apply to the next assessment a child takes.
/// Database CHECK constraints guarantee Strength cutoffs stay above their
/// Emerging counterparts even if client validation is bypassed.
class RubricPage extends StatefulWidget {
  const RubricPage({super.key});

  @override
  State<RubricPage> createState() => _RubricPageState();
}

class _RubricPageState extends State<RubricPage> {
  Map<String, dynamic>? _row;
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;
  String? _message;
  bool _messageIsError = false;

  /// (column, label, help, isPercent) — percent fields are edited as 0–100
  /// for readability and stored as 0–1 fractions.
  static const _fields = [
    (
      'strength_accuracy',
      'Strength: minimum accuracy',
      'Average accuracy at or above this earns a Strength label.',
      true,
    ),
    (
      'emerging_accuracy',
      'Emerging: minimum accuracy',
      'Below this (and below the completion floor) means Needs Support.',
      true,
    ),
    (
      'strength_completion',
      'Strength: minimum completion',
      'Task completion rate required for Strength.',
      true,
    ),
    (
      'emerging_completion',
      'Emerging: minimum completion',
      'Completion rate that still counts as Emerging.',
      true,
    ),
    (
      'strength_max_prompt_dependency',
      'Strength: maximum prompt dependency',
      'Strength requires needing prompts on at most this share of items.',
      true,
    ),
    (
      'strength_turn_taking',
      'Strength: minimum turn-taking success',
      'Social interaction Strength cutoff (My Turn, Your Turn).',
      true,
    ),
    (
      'emerging_turn_taking',
      'Emerging: minimum turn-taking success',
      'Below this is Needs Support for social interaction.',
      true,
    ),
    (
      'sustained_max_idle_seconds',
      'Sustained attention: max idle seconds',
      'Average idle time allowed for a Sustained Attention label.',
      false,
    ),
    (
      'variable_max_idle_seconds',
      'Variable attention: max idle seconds',
      'Average idle time allowed for a Variable Attention label.',
      false,
    ),
  ];

  static const _defaults = {
    'strength_accuracy': 0.80,
    'emerging_accuracy': 0.50,
    'strength_completion': 0.80,
    'emerging_completion': 0.50,
    'strength_max_prompt_dependency': 0.20,
    'strength_turn_taking': 0.80,
    'emerging_turn_taking': 0.50,
    'sustained_max_idle_seconds': 5.0,
    'variable_max_idle_seconds': 15.0,
  };

  static const _domainNames = {
    'communication': 'Communication',
    'completion': 'Task Completion',
    'social': 'Social Interaction',
    'attention': 'Attention & Pacing',
  };

  String _fieldDomain(String column) {
    if (column.contains('accuracy')) return 'communication';
    if (column.contains('completion')) return 'completion';
    if (column.contains('turn_taking')) return 'social';
    return 'attention';
  }

  double _currentValue(String column, bool isPercent) {
    final parsed = double.tryParse(_controllers[column]?.text.trim() ?? '');
    if (parsed == null) return 0;
    return isPercent ? parsed / 100 : parsed;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final row = await Supabase.instance.client
        .from('rubric_thresholds')
        .select()
        .eq('id', 1)
        .single();
    if (!mounted) return;
    setState(() {
      _row = Map<String, dynamic>.from(row);
      for (final (column, _, _, isPercent) in _fields) {
        final value = (_row![column] as num).toDouble();
        _controllers[column] = TextEditingController(
          text: isPercent
              ? (value * 100).round().toString()
              : value.toStringAsFixed(0),
        );
      }
    });
  }

  void _applyDefaults() {
    setState(() {
      for (final (column, _, _, isPercent) in _fields) {
        final value = _defaults[column]!;
        _controllers[column]!.text = isPercent
            ? (value * 100).round().toString()
            : value.toStringAsFixed(0);
      }
      _message = 'Defaults restored — press Save to apply.';
      _messageIsError = false;
    });
  }

  String? _validate(Map<String, double> values) {
    for (final (column, label, _, isPercent) in _fields) {
      final v = values[column]!;
      if (isPercent && (v < 0 || v > 1)) {
        return '$label must be between 0 and 100%.';
      }
      if (!isPercent && (v <= 0 || v > 300)) {
        return '$label must be between 1 and 300 seconds.';
      }
    }
    if (values['strength_accuracy']! <= values['emerging_accuracy']!) {
      return 'Strength accuracy must be above Emerging accuracy.';
    }
    if (values['strength_completion']! <= values['emerging_completion']!) {
      return 'Strength completion must be above Emerging completion.';
    }
    if (values['strength_turn_taking']! <= values['emerging_turn_taking']!) {
      return 'Strength turn-taking must be above Emerging turn-taking.';
    }
    if (values['variable_max_idle_seconds']! <=
        values['sustained_max_idle_seconds']!) {
      return 'Variable idle limit must be above the Sustained idle limit.';
    }
    return null;
  }

  Future<void> _save() async {
    final values = <String, double>{};
    for (final (column, label, _, isPercent) in _fields) {
      final parsed = double.tryParse(_controllers[column]!.text.trim());
      if (parsed == null) {
        setState(() {
          _message = '$label needs a number.';
          _messageIsError = true;
        });
        return;
      }
      values[column] = isPercent ? parsed / 100.0 : parsed;
    }

    final error = _validate(values);
    if (error != null) {
      setState(() {
        _message = error;
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await Supabase.instance.client
          .from('rubric_thresholds')
          .update({
            ...values,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', 1);
      setState(() {
        _message = 'Saved. New assessments will use these thresholds.';
        _messageIsError = false;
      });
    } catch (e) {
      setState(() {
        _message = 'Save failed: $e';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_row == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Rubric Thresholds',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _applyDefaults,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset to defaults'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Cutoffs used to assign Strength / Emerging / Needs Support '
            'labels. The mobile app fetches these at startup; changes '
            'apply to the next assessment taken.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: TextStyle(
                color: _messageIsError
                    ? Theme.of(context).colorScheme.error
                    : Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildWarning(context),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final domain in _domainNames.keys)
                    _buildDomain(context, domain),
                  _buildReferenceTable(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarning(BuildContext context) {
    final values = <String, double>{};
    for (final (column, _, _, isPercent) in _fields) {
      values[column] = _currentValue(column, isPercent);
    }
    final warning = _validate(values);
    if (warning == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('Check before saving: $warning')),
        ],
      ),
    );
  }

  Widget _buildDomain(BuildContext context, String domain) {
    final fields = _fields.where((field) => _fieldDomain(field.$1) == domain);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _domainNames[domain]!,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              _domainHelp(domain),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (final (column, label, help, isPercent) in fields)
                  SizedBox(
                    width: 300,
                    child: _buildField(context, column, label, help, isPercent),
                  ),
              ],
            ),
            if (domain != 'attention') ...[
              const SizedBox(height: 12),
              _buildScale(context, domain),
            ],
          ],
        ),
      ),
    );
  }

  String _domainHelp(String domain) => switch (domain) {
    'communication' =>
      'How accurately does the learner respond and communicate?',
    'completion' => 'How consistently does the learner finish activities?',
    'social' => 'How successfully does the learner take turns with others?',
    _ => 'How long can the learner stay engaged before needing support?',
  };

  Widget _buildField(
    BuildContext context,
    String column,
    String label,
    String help,
    bool isPercent,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      Text(help, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      TextField(
        controller: _controllers[column],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          isDense: true,
          suffixText: isPercent ? '%' : 's',
        ),
      ),
    ],
  );

  Widget _buildScale(BuildContext context, String domain) {
    final levels = domain == 'social'
        ? (
            _currentValue('emerging_turn_taking', true),
            _currentValue('strength_turn_taking', true),
          )
        : (
            _currentValue(
              domain == 'communication'
                  ? 'emerging_accuracy'
                  : 'emerging_completion',
              true,
            ),
            _currentValue(
              domain == 'communication'
                  ? 'strength_accuracy'
                  : 'strength_completion',
              true,
            ),
          );
    return Row(
      children: [
        _scaleChip(
          context,
          'Needs Support',
          'Below ${(levels.$1 * 100).round()}%',
          Colors.red.shade100,
        ),
        const SizedBox(width: 6),
        _scaleChip(
          context,
          'Emerging',
          '${(levels.$1 * 100).round()}-${(levels.$2 * 100).round()}%',
          Colors.amber.shade100,
        ),
        const SizedBox(width: 6),
        _scaleChip(
          context,
          'Strength',
          '${(levels.$2 * 100).round()}%+',
          Colors.green.shade100,
        ),
      ],
    );
  }

  Widget _scaleChip(
    BuildContext context,
    String label,
    String range,
    Color color,
  ) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(8),
      color: color,
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(range, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );

  Widget _buildReferenceTable(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 24),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick reference for teachers',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Use the label that best describes the learner today. These cutoffs guide the next learning path; they are not a diagnosis.',
          ),
          const SizedBox(height: 10),
          Table(
            border: TableBorder.all(color: Colors.black12),
            children: const [
              TableRow(
                children: [
                  Padding(padding: EdgeInsets.all(8), child: Text('Label')),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Plain-language meaning'),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Needs Support'),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Offer more prompts, modelling, or a simpler step.',
                    ),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(padding: EdgeInsets.all(8), child: Text('Emerging')),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'The skill is developing with occasional support.',
                    ),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(padding: EdgeInsets.all(8), child: Text('Strength')),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'The learner usually demonstrates this skill independently.',
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Example learner preview',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'A learner at 65% accuracy is Emerging with the current thresholds. Try a visual prompt, then celebrate the next independent response.',
          ),
        ],
      ),
    ),
  );
}
