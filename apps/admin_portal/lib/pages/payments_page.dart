import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only payment and entitlement review for administrators. RLS and the
/// existing `is_admin()` gate remain the source of authorization.
class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  List<Map<String, dynamic>> _payments = const [];
  List<Map<String, dynamic>> _entitlements = const [];
  String? _status;
  String? _error;
  bool _loading = true;

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
      final client = Supabase.instance.client;
      final payments = await client
          .from('payment_records')
          .select('id,user_id,checkout_session_id,amount,currency,status,created_at,updated_at')
          .order('created_at', ascending: false)
          .limit(200);
      final entitlements = await client
          .from('entitlements')
          .select('user_id,is_premium,source,activated_at,updated_at')
          .order('updated_at', ascending: false)
          .limit(200);
      if (mounted) {
        setState(() {
          _payments = List<Map<String, dynamic>>.from(payments as List);
          _entitlements = List<Map<String, dynamic>>.from(entitlements as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Unable to load payment records: $e'; _loading = false; });
    }
  }

  String _money(Map<String, dynamic> row) {
    final amount = row['amount'];
    if (amount is! num) return '-';
    return '${row['currency'] ?? 'PHP'} ${(amount / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final statuses = _payments.map((p) => p['status']?.toString()).whereType<String>().toSet().toList()..sort();
    final visible = _status == null ? _payments : _payments.where((p) => p['status'] == _status).toList();
    final format = DateFormat('MMM d, y HH:mm');
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Payments & Entitlements', style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          DropdownButton<String?>(
            value: _status,
            hint: const Text('All payment statuses'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('All statuses')), ...statuses.map((s) => DropdownMenuItem<String?>(value: s, child: Text(s)))],
            onChanged: (value) => setState(() => _status = value),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
        ]),
        const SizedBox(height: 12),
        Text('${visible.length} payment records · ${_entitlements.where((e) => e['is_premium'] == true).length} active Premium entitlements'),
        const SizedBox(height: 12),
        Expanded(child: ListView.separated(
          itemCount: visible.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final row = visible[index];
            final date = DateTime.tryParse(row['created_at']?.toString() ?? '');
            return ListTile(
              leading: Icon(row['status'] == 'paid' ? Icons.check_circle_rounded : Icons.receipt_long_rounded, color: row['status'] == 'paid' ? Colors.green : null),
              title: Text('${row['status'] ?? 'unknown'} · ${_money(row)}'),
              subtitle: Text('User ${row['user_id'] ?? '-'}\nSession ${row['checkout_session_id'] ?? '-'}'),
              isThreeLine: true,
              trailing: Text(date == null ? '-' : format.format(date.toLocal())),
            );
          },
        )),
      ]),
    );
  }
}
