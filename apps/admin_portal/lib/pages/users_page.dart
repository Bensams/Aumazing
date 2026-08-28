import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Parent account management (Section B FR): search, filter, and
/// suspend/reactivate accounts.
///
/// Listing and suspension both run through admin-only SECURITY DEFINER
/// RPCs; suspension sets `banned_until` so the account can no longer sign
/// in or refresh its session, and every action lands in the audit log.
/// Administrator accounts cannot be suspended (enforced server-side).
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _search = TextEditingController();
  String _filter = 'all';
  List<Map<String, dynamic>> _users = const [];
  bool _loading = true;
  String? _error;

  static const _filters = [
    ('all', 'All'),
    ('active', 'Active'),
    ('suspended', 'Suspended'),
    ('guests', 'Guests'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client.rpc('get_admin_users',
          params: {'p_search': _search.text.trim(), 'p_filter': _filter});
      if (mounted) {
        setState(() {
          _users = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load accounts: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _setSuspension(Map<String, dynamic> user, bool suspend) async {
    final email = user['email'] as String? ?? 'this guest account';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(suspend ? 'Suspend account?' : 'Reactivate account?'),
        content: Text(suspend
            ? '$email will no longer be able to sign in. Their data is '
                'kept and the account can be reactivated at any time.'
            : '$email will be able to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: suspend
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(suspend ? 'Suspend' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.rpc('set_user_suspension', params: {
        'p_user_id': user['id'],
        'p_suspend': suspend,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, y');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Parent Accounts',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search by email…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _search.clear();
                              _load();
                            },
                          ),
                  ),
                  onSubmitted: (_) => _load(),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 16),
              for (final (value, label) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _filter == value,
                    onSelected: (_) {
                      setState(() => _filter = value);
                      _load();
                    },
                  ),
                ),
              const Spacer(),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                    ? const Center(child: Text('No accounts match.'))
                    : ListView.separated(
                        itemCount: _users.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final user = _users[i];
                          final suspended = user['suspended'] == true;
                          final isAdmin = user['is_admin'] == true;
                          final isGuest = user['is_anonymous'] == true;
                          final createdAt = DateTime.tryParse(
                              user['created_at'] as String? ?? '');
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                isGuest
                                    ? Icons.person_outline_rounded
                                    : Icons.person_rounded,
                                color: suspended
                                    ? Colors.grey
                                    : const Color(0xFF7E57C2),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      user['email'] as String? ??
                                          'Guest account',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isAdmin) _pill('Admin', Colors.indigo),
                                  if (isGuest) _pill('Guest', Colors.grey),
                                  if (user['is_premium'] == true)
                                    _pill('Premium', Colors.amber.shade800),
                                  if (suspended)
                                    _pill('Suspended', Colors.red),
                                ],
                              ),
                              subtitle: Text(
                                '${user['children_count'] ?? 0} child '
                                'profile(s)'
                                '${createdAt == null ? '' : ' · joined '
                                    '${dateFormat.format(createdAt.toLocal())}'}',
                              ),
                              trailing: isAdmin
                                  ? null
                                  : suspended
                                      ? FilledButton.tonal(
                                          onPressed: () =>
                                              _setSuspension(user, false),
                                          child: const Text('Reactivate'),
                                        )
                                      : OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                          onPressed: () =>
                                              _setSuspension(user, true),
                                          child: const Text('Suspend'),
                                        ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
