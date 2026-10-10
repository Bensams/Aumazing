import 'package:flutter/material.dart';

import '../data/premium_admin.dart';

/// What the administrator chose in [PremiumGrantDialog].
typedef PremiumGrantChoice = ({int days, String reason});

/// Asks how many days of Premium to give an account and why (AUM-357). The
/// reason is required: it goes to the audit log beside the grant.
class PremiumGrantDialog extends StatefulWidget {
  const PremiumGrantDialog({super.key, required this.accountLabel});

  final String accountLabel;

  static Future<PremiumGrantChoice?> show(
    BuildContext context, {
    required String accountLabel,
  }) => showDialog<PremiumGrantChoice>(
    context: context,
    builder: (_) => PremiumGrantDialog(accountLabel: accountLabel),
  );

  @override
  State<PremiumGrantDialog> createState() => _PremiumGrantDialogState();
}

class _PremiumGrantDialogState extends State<PremiumGrantDialog> {
  final _reason = TextEditingController();
  int _days = kPremiumGrantDays.first;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason.text.trim();
    return AlertDialog(
      title: const Text('Grant Premium'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Premium for ${widget.accountLabel}. Days are added on top of '
              'any Premium the account already has.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final days in kPremiumGrantDays)
                  ChoiceChip(
                    key: Key('grant-days-$days'),
                    label: Text('$days days'),
                    selected: _days == days,
                    onSelected: (_) => setState(() => _days = days),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('grant-reason'),
              controller: _reason,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (kept in the audit log)',
                hintText: 'e.g. School study family, Oct 2026',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('grant-confirm'),
          onPressed:
              reason.isEmpty
                  ? null
                  : () =>
                      Navigator.of(context).pop((days: _days, reason: reason)),
          child: Text('Grant $_days days'),
        ),
      ],
    );
  }
}
