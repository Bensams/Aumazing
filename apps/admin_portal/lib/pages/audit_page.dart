import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Audit trail of admin actions (accountability FR). Entries are written
/// by database triggers, so they can't be skipped by any client.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  List<Map<String, dynamic>> _logs = const [];
  String _query = '';
  String? _action;
  String? _table;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await Supabase.instance.client
        .from('audit_logs')
        .select()
        .order('created_at', ascending: false)
        .limit(200);
    if (mounted) {
      setState(() {
        _logs = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    }
  }

  IconData _iconFor(String action) => switch (action) {
        'INSERT' => Icons.add_circle_outline_rounded,
        'DELETE' => Icons.remove_circle_outline_rounded,
        _ => Icons.edit_rounded,
      };

  String _describe(Map<String, dynamic> log) {
    final newData = log['new_data'] as Map<String, dynamic>?;
    final oldData = log['old_data'] as Map<String, dynamic>?;
    final name = (newData?['title'] ??
            newData?['name'] ??
            oldData?['title'] ??
            oldData?['name'] ??
            log['record_id'] ??
            '')
        .toString();
    return '${log['action']} ${log['table_name']} — $name';
  }

  List<Map<String, dynamic>> get _filteredLogs {
    final query = _query.trim().toLowerCase();
    return _logs.where((log) {
      if (_action != null && log['action'] != _action) return false;
      if (_table != null && log['table_name'] != _table) return false;
      if (query.isEmpty) return true;
      return _describe(log).toLowerCase().contains(query) ||
          (log['actor_id']?.toString().toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final dateFormat = DateFormat('MMM d, y HH:mm');
    final actions = _logs.map((e) => e['action']?.toString()).whereType<String>().toSet().toList()..sort();
    final tables = _logs.map((e) => e['table_name']?.toString()).whereType<String>().toSet().toList()..sort();
    final filtered = _filteredLogs;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Audit Log',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search audit log',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              DropdownButton<String?>(
                value: _action,
                hint: const Text('All actions'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All actions')),
                  ...actions.map((value) => DropdownMenuItem<String?>(value: value, child: Text(value))),
                ],
                onChanged: (value) => setState(() => _action = value),
              ),
              DropdownButton<String?>(
                value: _table,
                hint: const Text('All tables'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All tables')),
                  ...tables.map((value) => DropdownMenuItem<String?>(value: value, child: Text(value))),
                ],
                onChanged: (value) => setState(() => _table = value),
              ),
              Text('${filtered.length} of ${_logs.length} entries'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No admin actions recorded yet.'))
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final log = filtered[i];
                      final createdAt = DateTime.tryParse(
                          log['created_at'] as String? ?? '');
                      return ListTile(
                        dense: true,
                        leading: Icon(_iconFor(log['action'] as String? ?? ''),
                            color: const Color(0xFF7E57C2)),
                        title: Text(_describe(log)),
                        subtitle: Text(
                          'actor: ${log['actor_id'] ?? 'system'}',
                        ),
                        trailing: Text(createdAt == null
                            ? ''
                            : dateFormat.format(createdAt.toLocal())),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
