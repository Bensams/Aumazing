import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Beta Review — the SPED validation workspace.
///
/// Shows research-consented children ONLY (the get_beta_children /
/// get_child_report RPCs refuse everything else server-side). For each
/// child: the raw gameplay indicators the rubric consumes, the per-area
/// rubric outcome with the thresholds applied, and the AI recommendation —
/// side by side so a SPED professional can judge whether the
/// recommendation matches the child's developmental needs, and record an
/// agree/disagree review per area (the study's validation data).
class BetaPage extends StatefulWidget {
  const BetaPage({super.key});

  @override
  State<BetaPage> createState() => _BetaPageState();
}

class _BetaPageState extends State<BetaPage> {
  List<Map<String, dynamic>> _children = const [];
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _thresholds;
  String? _selectedChildId;
  bool _loadingList = true;
  bool _loadingReport = false;
  String? _error;

  static const _areas = [
    ('communication', 'Communication'),
    ('social', 'Social Interaction'),
    ('play', 'Play Skills'),
    ('attention', 'Attention'),
    ('recommendation', 'AI Recommendation'),
  ];

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    setState(() {
      _loadingList = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client.rpc('get_beta_children');
      final thresholds = await Supabase.instance.client
          .from('rubric_thresholds')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _children = List<Map<String, dynamic>>.from(rows as List);
        _thresholds = thresholds;
        _loadingList = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load: $e';
          _loadingList = false;
        });
      }
    }
  }

  Future<void> _loadReport(String childId) async {
    setState(() {
      _selectedChildId = childId;
      _loadingReport = true;
      _report = null;
    });
    try {
      final report = await Supabase.instance.client
          .rpc('get_child_report', params: {'p_child_id': childId});
      if (!mounted) return;
      setState(() {
        _report = Map<String, dynamic>.from(report as Map);
        _loadingReport = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load report: $e';
          _loadingReport = false;
        });
      }
    }
  }

  Future<void> _review(String area, bool agrees) async {
    final commentController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(agrees ? 'Agree' : 'Disagree'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: commentController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save review'),
          ),
        ],
      ),
    );
    if (confirmed != true || _selectedChildId == null) return;

    try {
      await Supabase.instance.client.from('validator_reviews').insert({
        'child_id': _selectedChildId,
        'area': area,
        'agrees': agrees,
        'comment': commentController.text.trim().isEmpty
            ? null
            : commentController.text.trim(),
        'reviewer_id': Supabase.instance.client.auth.currentUser?.id,
      });
      _loadReport(_selectedChildId!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  int? _ageYears(String? birthDate) {
    final date = DateTime.tryParse(birthDate ?? '');
    if (date == null) return null;
    final now = DateTime.now();
    var age = now.year - date.year;
    if (now.month < date.month ||
        (now.month == date.month && now.day < date.day)) {
      age--;
    }
    return age;
  }

  /// Levels arrive as 0/1/2, 'needs_support'-style slugs, or display
  /// names depending on which pipeline wrote them — normalize all three.
  String _formatLevel(dynamic value) {
    if (value == null) return '—';
    final raw = value.toString();
    switch (raw) {
      case '0':
      case 'needs_support':
        return 'Needs Support';
      case '1':
      case 'emerging':
        return 'Emerging';
      case '2':
      case 'strength':
        return 'Strength';
      default:
        return raw;
    }
  }

  Color _levelColor(String formatted) => switch (formatted) {
        'Strength' => Colors.green.shade700,
        'Emerging' => Colors.orange.shade800,
        'Needs Support' => Colors.red.shade700,
        _ => Colors.grey,
      };

  String _pct(dynamic value) {
    final v = (value as num?)?.toDouble();
    return v == null ? '—' : '${(v * 100).toStringAsFixed(0)}%';
  }

  String _num(dynamic value, {int decimals = 0, String suffix = ''}) {
    final v = (value as num?)?.toDouble();
    return v == null ? '—' : '${v.toStringAsFixed(decimals)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Beta Review',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Only children whose parents gave research '
                    'consent are listed. Access is enforced by the '
                    'database, not this page.',
                child: Icon(Icons.verified_user_rounded,
                    size: 18, color: Colors.green.shade700),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadChildren,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
              ),
            ],
          ),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 300, child: _buildChildList()),
                const VerticalDivider(width: 24),
                Expanded(child: _buildReport()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChildList() {
    if (_loadingList) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_children.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No research-consented children yet.\n\nParents give consent '
            'in the app before the pre-assessment.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _children.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final child = _children[i];
        final childId = child['child_id'] as String;
        final age = _ageYears(child['birth_date'] as String?);
        final selected = childId == _selectedChildId;
        return Card(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            onTap: () => _loadReport(childId),
            leading: const Icon(Icons.child_care_rounded,
                color: Color(0xFF7E57C2)),
            title: Text(
                '${child['display_name']}${age == null ? '' : ' · $age y/o'}'),
            subtitle: Text(
              '${child['session_count']} sessions · '
              '${child['review_count']} reviews'
              '${child['ai_training_opt_in'] == true ? ' · AI-training ✓' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReport() {
    if (_selectedChildId == null) {
      return const Center(
          child: Text('Select a child to open their report.'));
    }
    if (_loadingReport || _report == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final sessions =
        List<Map<String, dynamic>>.from(_report!['sessions'] as List);
    final results =
        List<Map<String, dynamic>>.from(_report!['results'] as List);
    final recommendations =
        List<Map<String, dynamic>>.from(_report!['recommendations'] as List);
    final reviews =
        List<Map<String, dynamic>>.from(_report!['reviews'] as List);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Gameplay Indicators '
              '(${sessions.length} assessment sessions)'),
          _buildSessionsTable(sessions),
          const SizedBox(height: 24),
          _sectionTitle('Rubric Outcome (latest assessment)'),
          _buildRubricTable(results.isEmpty ? null : results.first),
          const SizedBox(height: 24),
          _sectionTitle('AI Recommendation'),
          _buildRecommendation(
              recommendations.isEmpty ? null : recommendations.first),
          const SizedBox(height: 24),
          _sectionTitle('SPED Validator Sign-off'),
          _buildValidatorPanel(reviews),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _buildSessionsTable(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No assessment sessions synced yet.'),
        ),
      );
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(fontWeight: FontWeight.w700),
          columns: const [
            DataColumn(label: Text('Game')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Score')),
            DataColumn(label: Text('Accuracy')),
            DataColumn(label: Text('Completion')),
            DataColumn(label: Text('Errors')),
            DataColumn(label: Text('Avg resp')),
            DataColumn(label: Text('Hints')),
            DataColumn(label: Text('Prompts')),
            DataColumn(label: Text('Prompt dep')),
            DataColumn(label: Text('Idle')),
            DataColumn(label: Text('Random taps')),
            DataColumn(label: Text('Turn-taking')),
          ],
          rows: [
            for (final s in sessions)
              DataRow(cells: [
                DataCell(Text((s['game_id'] as String? ?? '')
                    .replaceAll('_', ' '))),
                DataCell(Text(
                    s['context'] == 'pre_assessment' ? 'pre' : 'post')),
                DataCell(Text('${s['score']}/${s['total_items']}')),
                DataCell(Text(_pct(s['accuracy']))),
                DataCell(Text(_pct(s['task_completion_rate']))),
                DataCell(Text('${s['error_count'] ?? '—'}')),
                DataCell(
                    Text(_num(s['avg_response_time'], decimals: 1, suffix: 's'))),
                DataCell(Text('${s['hint_count'] ?? '—'}')),
                DataCell(Text('${s['prompt_count'] ?? '—'}')),
                DataCell(Text(_pct(s['prompt_dependency_score']))),
                DataCell(Text(
                    _num(s['idle_time_seconds'], decimals: 0, suffix: 's'))),
                DataCell(Text('${s['random_touch_count'] ?? '—'}')),
                DataCell(Text(_pct(s['turn_taking_success_rate']))),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _buildRubricTable(Map<String, dynamic>? result) {
    if (result == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No assessment result synced yet.'),
        ),
      );
    }
    final t = _thresholds;
    String cutoff(String area) {
      if (t == null) return '';
      final strengthAcc = _pct(t['strength_accuracy']);
      final emergingAcc = _pct(t['emerging_accuracy']);
      switch (area) {
        case 'communication':
        case 'play':
          return 'Strength ≥ $strengthAcc acc · Emerging ≥ $emergingAcc';
        case 'social':
          return 'Strength ≥ ${_pct(t['strength_turn_taking'])} turn-taking '
              '· Emerging ≥ ${_pct(t['emerging_turn_taking'])}';
        case 'attention':
          return 'Sustained ≤ ${_num(t['sustained_max_idle_seconds'], suffix: 's')} idle '
              '· Variable ≤ ${_num(t['variable_max_idle_seconds'], suffix: 's')}';
        default:
          return '';
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final (key, label) in _areas.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                        width: 160,
                        child: Text(label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600))),
                    SizedBox(
                      width: 130,
                      child: Builder(builder: (_) {
                        final formatted =
                            _formatLevel(result['${key}_level']);
                        return Text(
                          formatted,
                          style: TextStyle(
                            color: _levelColor(formatted),
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      }),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                          'conf ${_pct(result['${key}_confidence'])}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                    Expanded(
                      child: Text(cutoff(key),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendation(Map<String, dynamic>? recommendation) {
    if (recommendation == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No recommendation synced yet.'),
        ),
      );
    }
    final path = recommendation['recommended_path_json'];
    final steps = path is List ? path : const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top module: ${recommendation['top_module'] ?? '—'}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < steps.length; i++)
                    Chip(
                      avatar: CircleAvatar(
                        backgroundColor: const Color(0xFF7E57C2),
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white)),
                      ),
                      label: Text(_stepLabel(steps[i])),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _stepLabel(dynamic step) {
    if (step is Map) {
      final name = step['name'] ?? step['game_id'] ?? step['module'] ?? '?';
      final level = step['starting_level'] ?? step['level'];
      return level == null ? '$name' : '$name (Lvl $level)';
    }
    return step.toString();
  }

  Widget _buildValidatorPanel(List<Map<String, dynamic>> reviews) {
    final dateFormat = DateFormat('MMM d, HH:mm');
    Map<String, dynamic>? latestFor(String area) {
      for (final r in reviews) {
        if (r['area'] == area) return r; // reviews arrive newest-first
      }
      return null;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Does each rubric outcome — and the overall recommendation — '
              'match this child\'s developmental needs?',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final (key, label) in _areas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                        width: 160,
                        child: Text(label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600))),
                    IconButton(
                      onPressed: () => _review(key, true),
                      icon: const Icon(Icons.thumb_up_rounded),
                      color: Colors.green.shade700,
                      tooltip: 'Agree',
                    ),
                    IconButton(
                      onPressed: () => _review(key, false),
                      icon: const Icon(Icons.thumb_down_rounded),
                      color: Colors.red.shade700,
                      tooltip: 'Disagree',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Builder(builder: (_) {
                        final latest = latestFor(key);
                        if (latest == null) {
                          return Text('Not yet reviewed',
                              style:
                                  Theme.of(context).textTheme.bodySmall);
                        }
                        final when = DateTime.tryParse(
                            latest['created_at'] as String? ?? '');
                        return Text(
                          '${latest['agrees'] == true ? '✔ Agreed' : '✘ Disagreed'}'
                          '${latest['comment'] == null ? '' : ' — ${latest['comment']}'}'
                          '${when == null ? '' : ' (${dateFormat.format(when.toLocal())})'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        );
                      }),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
