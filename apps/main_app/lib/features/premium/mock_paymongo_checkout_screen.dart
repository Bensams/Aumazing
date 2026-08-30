import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// How a simulated checkout ended (AUM-331).
///
/// Mirrors the three outcomes the real hosted checkout can produce, because a
/// demo that only ever succeeds teaches nobody what a decline looks like — and
/// the decline path is the one most likely to be broken when it matters.
enum MockCheckoutOutcome {
  /// The parent "paid". Premium unlocks for this process only.
  paid,

  /// The payment was "declined". Nothing unlocks.
  declined,

  /// The parent backed out before paying.
  cancelled,
}

/// A stand-in for PayMongo's hosted checkout that never leaves the device.
///
/// Every visible element says the same thing in a different way: this is a
/// simulation, no money moves, nothing is charged. That is not decoration.
/// A screen that asks for money and looks convincing while doing something
/// else is the exact shape of a scam, and the only thing separating this from
/// one is that it never stops saying what it is.
///
/// Deliberately offers the same payment methods the real gateway does (cards,
/// GCash, GrabPay, Maya) so a demo shows the product as it will actually be,
/// but the choice changes nothing beyond the label on the receipt line — there
/// is no processing to differ.
class MockPaymongoCheckoutScreen extends StatefulWidget {
  const MockPaymongoCheckoutScreen({
    super.key,
    this.amountLabel = '₱299.00',
    this.planLabel = 'Aumazing Premium — Monthly',
  });

  final String amountLabel;
  final String planLabel;

  @override
  State<MockPaymongoCheckoutScreen> createState() =>
      _MockPaymongoCheckoutScreenState();
}

class _MockPaymongoCheckoutScreenState
    extends State<MockPaymongoCheckoutScreen> {
  static const _methods = [
    (Icons.credit_card_rounded, 'Card'),
    (Icons.account_balance_wallet_rounded, 'GCash'),
    (Icons.directions_car_rounded, 'GrabPay'),
    (Icons.payments_rounded, 'Maya'),
  ];

  int _selectedMethod = 0;
  bool _processing = false;

  /// A beat of "processing" before the outcome.
  ///
  /// Not theatre for its own sake: a demo that resolves instantly hides the
  /// spinner state, and the spinner state is real UI that can regress.
  Future<void> _finish(MockCheckoutOutcome outcome) async {
    setState(() => _processing = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulated checkout'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _processing
              ? null
              : () => Navigator.of(context).pop(MockCheckoutOutcome.cancelled),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.statusWarningDark.withValues(alpha: 0.12),
                      borderRadius: AppRadius.mediumBorder,
                      border: Border.all(color: AppColors.statusWarningDark),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.science_rounded,
                            color: AppColors.statusWarningDark),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'SIMULATION — this is not PayMongo. No payment is '
                            'processed and nothing is charged.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.statusWarningDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Text(widget.planLabel, style: AppTextStyles.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${widget.amountLabel} — pretend amount, never collected',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Text('Payment method', style: AppTextStyles.labelLarge),
                  const SizedBox(height: AppSpacing.sm),
                  for (var i = 0; i < _methods.length; i++)
                    ListTile(
                      onTap: _processing
                          ? null
                          : () => setState(() => _selectedMethod = i),
                      leading: Icon(_methods[i].$1),
                      title: Text(_methods[i].$2),
                      trailing: i == _selectedMethod
                          ? const Icon(Icons.check_circle_rounded)
                          : const Icon(Icons.circle_outlined),
                      selected: i == _selectedMethod,
                    ),
                  // No card number, no wallet number, no field of any kind:
                  // there is nothing to collect, and a form that looked ready
                  // to take a real card would invite someone to type one in.
                  const SizedBox(height: AppSpacing.md),

                  AppPrimaryButton(
                    label: 'Simulate successful payment',
                    icon: Icons.check_circle_rounded,
                    isLoading: _processing,
                    onPressed: _processing
                        ? null
                        : () => _finish(MockCheckoutOutcome.paid),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _processing
                        ? null
                        : () => _finish(MockCheckoutOutcome.declined),
                    icon: const Icon(Icons.cancel_rounded),
                    label: const Text('Simulate declined payment'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _processing
                        ? null
                        : () => Navigator.of(context)
                            .pop(MockCheckoutOutcome.cancelled),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
