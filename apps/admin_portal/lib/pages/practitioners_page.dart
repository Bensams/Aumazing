import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/questionnaire_api.dart';

/// Administrators approve practitioners (AUM-352): only an approved
/// practitioner can write questionnaires. Check the licence before
/// approving; revoking stops further edits but keeps what they wrote.
class PractitionersPage extends StatefulWidget {
  const PractitionersPage({super.key, required this.api});

  final QuestionnaireApi api;

  @override
  State<PractitionersPage> createState() => _PractitionersPageState();
}

class _PractitionersPageState extends State<PractitionersPage> {
  List<Map<String, dynamic>> _rows = const [];
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
      final rows = await widget.api.practitioners();
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load practitioners: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _set(Map<String, dynamic> row, String status) async {
    try {
      await widget.api.setPractitionerStatus('${row['user_id']}', status);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('That did not work: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final format = DateFormat('MMM d, y');
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Practitioners',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Therapists and SPED teachers apply by signing in to this portal. '
            'Check their licence before approving.',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _rows.isEmpty
                ? const Center(child: Text('No applications yet.'))
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final row = _rows[i];
                      final status = '${row['status']}';
                      final applied =
                          DateTime.tryParse('${row['created_at']}');
                      return ListTile(
                        key: Key('practitioners.row.${row['user_id']}'),
                        leading: Icon(
                          switch (status) {
                            'approved' => Icons.verified_rounded,
                            'revoked' => Icons.block_rounded,
                            _ => Icons.hourglass_top_rounded,
                          },
                          color: status == 'approved' ? Colors.green : null,
                        ),
                        title: Text('${row['full_name']} · ${row['profession']}'),
                        subtitle: Text([
                          'Licence: ${row['license_number'] ?? 'not given'}',
                          status[0].toUpperCase() + status.substring(1),
                          if (applied != null)
                            'Applied ${format.format(applied.toLocal())}',
                        ].join(' · ')),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            if (status != 'approved')
                              FilledButton(
                                key: Key(
                                  'practitioners.approve.${row['user_id']}',
                                ),
                                onPressed: () => _set(row, 'approved'),
                                child: const Text('Approve'),
                              ),
                            if (status != 'revoked')
                              OutlinedButton(
                                key: Key(
                                  'practitioners.revoke.${row['user_id']}',
                                ),
                                onPressed: () => _set(row, 'revoked'),
                                child: Text(
                                  status == 'pending' ? 'Decline' : 'Revoke',
                                ),
                              ),
                          ],
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
