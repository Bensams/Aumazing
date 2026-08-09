import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../services/parent_pin_service.dart';
import 'parent_pin_reset_screen.dart';

/// Asks the parent for a new 4-digit PIN (entered twice) and saves it.
///
/// Only reachable from the parent dashboard, which already sits behind the
/// lock — so this does not re-challenge for the existing PIN. A parent who
/// cannot get past the lock uses [ParentPinResetScreen] instead.
class ParentPinSetupDialog extends StatefulWidget {
  const ParentPinSetupDialog({super.key, required this.isChange});

  /// True when replacing an existing PIN (changes the copy only).
  final bool isChange;

  /// Shows the dialog. Returns true when a new PIN was saved.
  static Future<bool> show(BuildContext context, {bool isChange = false}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ParentPinSetupDialog(isChange: isChange),
    );
    return result ?? false;
  }

  @override
  State<ParentPinSetupDialog> createState() => _ParentPinSetupDialogState();
}

class _ParentPinSetupDialogState extends State<ParentPinSetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ParentPinService.instance.setPin(_pinController.text);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.isChange ? 'Change Parent PIN' : 'Set Parent PIN',
        style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimary),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose 4 digits your child cannot guess. Avoid birthdays and '
              'the PIN you use on this device.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ParentPinField(
              controller: _pinController,
              label: widget.isChange ? 'New PIN' : 'PIN',
              validator: ParentPinService.validatePin,
            ),
            const SizedBox(height: AppSpacing.sm),
            ParentPinField(
              controller: _confirmController,
              label: 'Confirm PIN',
              validator: (value) =>
                  value == _pinController.text ? null : 'PINs do not match',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
