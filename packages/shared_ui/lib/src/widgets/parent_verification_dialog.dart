import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// A modal dialog that requires a parent to solve a simple math problem
/// before gaining access to the parent dashboard from child mode.
class ParentVerificationDialog extends StatefulWidget {
  const ParentVerificationDialog({super.key});

  /// Shows the dialog and returns `true` if the parent verified successfully.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.foreground.withAlpha(120),
      builder: (_) => const ParentVerificationDialog(),
    );
    return result ?? false;
  }

  @override
  State<ParentVerificationDialog> createState() =>
      _ParentVerificationDialogState();
}

class _ParentVerificationDialogState extends State<ParentVerificationDialog> {
  late final int _a;
  late final int _b;
  final _controller = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _a = rng.nextInt(9) + 1;
    _b = rng.nextInt(9) + 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _verify() {
    final answer = int.tryParse(_controller.text.trim());
    if (answer == _a + _b) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'Incorrect answer. Try again.');
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
      child: Container(
        padding: AppSpacing.paddingLg,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.card,
          boxShadow: AppShadows.modal,
        ),
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.lavenderLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primaryPurple,
                size: 28,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Parent Verification', style: AppTextStyles.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Solve this to continue:',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'What is $_a + $_b?',
              style: AppTextStyles.displayMedium.copyWith(
                color: AppColors.primaryPurple,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMedium,
              decoration: InputDecoration(
                hintText: 'Answer',
                errorText: _error,
              ),
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: AppTextStyles.buttonMedium.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _verify,
                    child: const Text('Verify'),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
