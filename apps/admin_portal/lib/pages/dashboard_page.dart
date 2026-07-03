import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// System overview: registered users, child profiles, completed
/// assessments, sessions, and content counts (admin dashboard FR).
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await Supabase.instance.client.rpc('get_admin_stats');
      if (mounted) {
        setState(() => _stats = Map<String, dynamic>.from(stats as Map));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load stats: $e');
    }
  }

  static const _cards = [
    ('users', 'Registered Users', Icons.people_rounded),
    ('children', 'Child Profiles', Icons.child_care_rounded),
    ('assessment_results', 'Assessment Results', Icons.assessment_rounded),
    ('game_sessions', 'Game Sessions', Icons.sports_esports_rounded),
    ('active_modules', 'Active Modules', Icons.extension_rounded),
    ('therapy_centers', 'Therapy Centers', Icons.local_hospital_rounded),
    ('premium_users', 'Premium Subscribers', Icons.star_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_stats == null) {
      return const Center(child: CircularProgressIndicator());
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
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 2.2,
              children: [
                for (final (key, label, icon) in _cards)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(icon,
                              size: 36, color: const Color(0xFF7E57C2)),
                          const SizedBox(width: 16),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_stats![key] ?? 0}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              Text(label,
                                  style:
                                      Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
