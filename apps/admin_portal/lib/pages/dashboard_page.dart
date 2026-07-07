import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// System overview with date-range analytics (Section B FR: "view usage
/// analytics, filter reports by date range").
///
/// Activity counts (new users, new child profiles, assessments, game
/// sessions) are scoped to the selected period; state counts (totals,
/// active content, Premium subscribers) are point-in-time.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

enum _Range { week, month, all, custom }

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _stats;
  String? _error;
  _Range _range = _Range.all;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime?, DateTime?) _bounds() {
    final now = DateTime.now();
    switch (_range) {
      case _Range.week:
        return (now.subtract(const Duration(days: 7)), null);
      case _Range.month:
        return (now.subtract(const Duration(days: 30)), null);
      case _Range.all:
        return (null, null);
      case _Range.custom:
        final r = _customRange;
        if (r == null) return (null, null);
        // Include the whole end day.
        return (r.start, r.end.add(const Duration(days: 1)));
    }
  }

  Future<void> _load() async {
    setState(() {
      _stats = null;
      _error = null;
    });
    try {
      final (from, to) = _bounds();
      final stats =
          await Supabase.instance.client.rpc('get_admin_stats', params: {
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
      });
      if (mounted) {
        setState(() => _stats = Map<String, dynamic>.from(stats as Map));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load stats: $e');
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
              start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _range = _Range.custom;
      });
      _load();
    }
  }

  String get _periodLabel {
    switch (_range) {
      case _Range.week:
        return 'last 7 days';
      case _Range.month:
        return 'last 30 days';
      case _Range.all:
        return 'all time';
      case _Range.custom:
        final r = _customRange;
        if (r == null) return 'custom';
        final f = DateFormat('MMM d, y');
        return '${f.format(r.start)} – ${f.format(r.end)}';
    }
  }

  static const _periodCards = [
    ('new_users', 'New Users', Icons.person_add_rounded),
    ('new_children', 'New Child Profiles', Icons.child_care_rounded),
    ('assessment_results', 'Assessment Results', Icons.assessment_rounded),
    ('game_sessions', 'Game Sessions', Icons.sports_esports_rounded),
  ];

  static const _stateCards = [
    ('users', 'Total Users', Icons.people_rounded),
    ('children', 'Total Child Profiles', Icons.family_restroom_rounded),
    ('active_modules', 'Active Modules', Icons.extension_rounded),
    ('therapy_centers', 'Therapy Centers', Icons.local_hospital_rounded),
    ('premium_users', 'Premium Subscribers', Icons.star_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('System Overview',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              ChoiceChip(
                label: const Text('7 days'),
                selected: _range == _Range.week,
                onSelected: (_) {
                  setState(() => _range = _Range.week);
                  _load();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('30 days'),
                selected: _range == _Range.month,
                onSelected: (_) {
                  setState(() => _range = _Range.month);
                  _load();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('All time'),
                selected: _range == _Range.all,
                onSelected: (_) {
                  setState(() => _range = _Range.all);
                  _load();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(_range == _Range.custom
                    ? _periodLabel
                    : 'Custom…'),
                selected: _range == _Range.custom,
                onSelected: (_) => _pickCustomRange(),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _stats == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Activity ($_periodLabel)',
                            style:
                                Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _cardGrid(_periodCards),
                        const SizedBox(height: 24),
                        Text('Current state',
                            style:
                                Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _cardGrid(_stateCards),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cardGrid(List<(String, String, IconData)> cards) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final (key, label, icon) in cards)
          SizedBox(
            width: 280,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(icon, size: 36, color: const Color(0xFF7E57C2)),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_stats![key] ?? 0}',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium),
                        Text(label,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
