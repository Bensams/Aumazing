import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Therapy center directory management: add, edit, activate/deactivate
/// listings with precise coordinates (therapy directory admin FRs).
class CentersPage extends StatefulWidget {
  const CentersPage({super.key});

  @override
  State<CentersPage> createState() => _CentersPageState();
}

class _CentersPageState extends State<CentersPage> {
  List<Map<String, dynamic>> _centers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await Supabase.instance.client
        .from('therapy_centers')
        .select()
        .order('sort_order');
    if (mounted) {
      setState(() {
        _centers = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> center, bool active) async {
    setState(() => center['active'] = active);
    try {
      await Supabase.instance.client
          .from('therapy_centers')
          .update({'active': active}).eq('id', center['id']);
    } catch (e) {
      setState(() => center['active'] = !active);
      _showError('Update failed: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit([Map<String, dynamic>? center]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CenterEditDialog(center: center),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Therapy Centers',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add center'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: _centers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final center = _centers[i];
                final active = center['active'] as bool? ?? false;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_hospital_rounded,
                        color: Color(0xFF7E57C2)),
                    title: Text(center['name'] as String? ?? ''),
                    subtitle: Text(
                      '${center['address']} · '
                      '(${center['latitude']}, ${center['longitude']})',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _edit(center),
                          icon: const Icon(Icons.edit_rounded),
                          tooltip: 'Edit',
                        ),
                        Switch(
                          value: active,
                          onChanged: (v) => _toggleActive(center, v),
                        ),
                      ],
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
}

class _CenterEditDialog extends StatefulWidget {
  const _CenterEditDialog({this.center});

  final Map<String, dynamic>? center;

  @override
  State<_CenterEditDialog> createState() => _CenterEditDialogState();
}

class _CenterEditDialogState extends State<_CenterEditDialog> {
  late final _name =
      TextEditingController(text: widget.center?['name'] as String? ?? '');
  late final _address =
      TextEditingController(text: widget.center?['address'] as String? ?? '');
  late final _description = TextEditingController(
      text: widget.center?['description'] as String? ?? '');
  late final _lat = TextEditingController(
      text: (widget.center?['latitude'] ?? '').toString());
  late final _lng = TextEditingController(
      text: (widget.center?['longitude'] ?? '').toString());
  late final _phone =
      TextEditingController(text: widget.center?['phone'] as String? ?? '');
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (_name.text.trim().isEmpty ||
        _address.text.trim().isEmpty ||
        lat == null ||
        lng == null) {
      setState(() =>
          _error = 'Name, address, and numeric coordinates are required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final data = {
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'description': _description.text.trim(),
      'latitude': lat,
      'longitude': lng,
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
    };
    try {
      final client = Supabase.instance.client.from('therapy_centers');
      if (widget.center == null) {
        await client.insert(data);
      } else {
        await client.update(data).eq('id', widget.center!['id']);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Save failed: $e';
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _description, _lat, _lng, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.center == null ? 'Add center' : 'Edit center'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Address')),
              const SizedBox(height: 8),
              TextField(
                  controller: _description,
                  decoration:
                      const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                        controller: _lat,
                        decoration:
                            const InputDecoration(labelText: 'Latitude')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                        controller: _lng,
                        decoration:
                            const InputDecoration(labelText: 'Longitude')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: _phone,
                  decoration:
                      const InputDecoration(labelText: 'Phone (optional)')),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
