import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Result of the sensory consent dialog.
enum SensoryConsentResult { accepted, declined }

/// A parent-facing dialog that explains sensory preference testing and
/// asks for consent before the pre-assessment begins.
///
/// The dialog explains that background music and haptic feedback will be
/// toggled across rounds to find the child's most comfortable settings.
///
/// Returns [SensoryConsentResult.accepted] if the parent allows testing,
/// or [SensoryConsentResult.declined] if they prefer to keep their own
/// settings for all rounds.
class SensoryConsentDialog extends StatelessWidget {
  const SensoryConsentDialog({super.key});

  /// Shows the consent dialog and returns the parent's choice.
  ///
  /// Defaults to [SensoryConsentResult.declined] if dismissed.
  static Future<SensoryConsentResult> show(BuildContext context) async {
    final result = await showDialog<SensoryConsentResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.foreground.withAlpha(120),
      builder: (_) => const SensoryConsentDialog(),
    );
    return result ?? SensoryConsentResult.declined;
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
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon ────────────────────────────────────────────────
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.lavenderLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: AppColors.primaryPurple,
                  size: 28,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Title ───────────────────────────────────────────────
              Text(
                'Sensory Preference Check',
                style: AppTextStyles.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Description ─────────────────────────────────────────
              Text(
                'Before we start, we would like to find out what '
                'helps your child focus best.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.mutedForeground,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Explanation card ────────────────────────────────────
              Container(
                padding: AppSpacing.paddingMd,
                decoration: BoxDecoration(
                  color: AppColors.lavenderLight.withAlpha(80),
                  borderRadius: AppRadius.smallBorder,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      icon: Icons.music_note_rounded,
                      text: 'Background music will be turned on and off '
                          'across different rounds.',
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _InfoRow(
                      icon: Icons.vibration_rounded,
                      text: 'Gentle vibrations will be turned on and off '
                          'across different rounds.',
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _InfoRow(
                      icon: Icons.insights_rounded,
                      text: 'We will use the results to set the most '
                          'comfortable experience for your child.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Buttons ─────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(
                        SensoryConsentResult.declined,
                      ),
                      child: Text(
                        'Use My Settings',
                        style: AppTextStyles.buttonMedium.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(
                        SensoryConsentResult.accepted,
                      ),
                      child: const Text('Allow Testing'),
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

/// A single row in the explanation section with an icon and text.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primaryPurple),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.foreground,
            ),
          ),
        ),
      ],
    );
  }
}
