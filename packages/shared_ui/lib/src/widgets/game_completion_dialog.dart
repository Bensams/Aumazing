import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text_styles.dart';

/// Shows a child-friendly game-completion dialog.
///
/// For learning-path / practice modules ([showRetryNext] = true) it offers
/// large Retry and Next icon buttons so the child (or parent) can replay the
/// activity or move on. For assessment modules it must be called with
/// [showRetryNext] = false — assessment games follow a fixed sequence, so they
/// show only a single Continue action instead.
Future<void> showGameCompletionDialog(
  BuildContext context, {
  required bool showRetryNext,
  required VoidCallback onNext,
  VoidCallback? onRetry,
  String title = 'Great job!',
  String? message,
  String emoji = '🎉',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineSmall.copyWith(
                color: AppColors.primaryPurple,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 20),
            if (showRetryNext)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CompletionIconButton(
                    icon: Icons.refresh_rounded,
                    label: 'Retry',
                    color: const Color(0xFF5DAF8E),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      onRetry?.call();
                    },
                  ),
                  _CompletionIconButton(
                    icon: Icons.arrow_forward_rounded,
                    label: 'Next',
                    color: AppColors.primaryPurple,
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      onNext();
                    },
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    onNext();
                  },
                  child: Text(
                    'Continue',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.primaryPurple),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A large, kid-friendly circular icon button used in the completion dialog.
class _CompletionIconButton extends StatelessWidget {
  const _CompletionIconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withAlpha(80),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: AppColors.white, size: 32),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
