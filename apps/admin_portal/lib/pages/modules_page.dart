import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Learning-module (game) management: enable/disable games app-wide
/// (content management FR). The mobile app's ActiveGamesService reads the
/// `active` flag, so a toggle here filters recommendations, the learning
/// path, and the child lobby on next refresh.
class ModulesPage extends StatefulWidget {
  const ModulesPage({super.key});

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage> {
  List<Map<String, dynamic>> _modules = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await Supabase.instance.client
        .from('learning_modules')
        .select()
        .order('module_code');
    if (mounted) {
      setState(() {
        _modules = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    }
  }

  Future<void> _toggle(Map<String, dynamic> module, bool active) async {
    setState(() => module['active'] = active); // optimistic
    try {
      await Supabase.instance.client
          .from('learning_modules')
          .update({'active': active}).eq('id', module['id']);
    } catch (e) {
      setState(() => module['active'] = !active); // revert
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Games & Learning Modules',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Disabled modules disappear from recommendations, the learning '
            'path, and the child lobby.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: _modules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final module = _modules[i];
                return Card(
                  child: SwitchListTile(
                    title: Text(module['title'] as String? ?? ''),
                    subtitle: Text(module['description'] as String? ?? ''),
                    secondary: const Icon(Icons.extension_rounded,
                        color: Color(0xFF7E57C2)),
                    value: module['active'] as bool? ?? false,
                    onChanged: (v) => _toggle(module, v),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
