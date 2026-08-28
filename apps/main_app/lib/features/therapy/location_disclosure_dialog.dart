import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

/// Plain-language disclosure shown *before* the OS location prompt
/// (RA 10173-aligned, and Play Store prominent-disclosure guidance).
///
/// Only shown when permission has not been granted yet, so a parent who
/// already said yes is never nagged again. Declining here means the OS
/// prompt is never raised at all — the directory simply stays unranked.
class LocationDisclosureDialog {
  LocationDisclosureDialog._();

  /// Returns true when the parent agrees to continue to the OS prompt.
  static Future<bool> show(BuildContext context) async {
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.my_location_rounded,
                  color: AppColors.primaryPurple,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Find centers near you',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'To sort therapy centers from nearest to farthest, '
                      'Aumazing needs your location once.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const _DisclosurePoint(
                      icon: Icons.phone_android_rounded,
                      text: 'The distance is calculated on your phone.',
                    ),
                    const _DisclosurePoint(
                      icon: Icons.cloud_off_rounded,
                      text:
                          'Your location is never saved and never uploaded — not '
                          'to us, and not to the research study.',
                    ),
                    const _DisclosurePoint(
                      icon: Icons.delete_outline_rounded,
                      text: 'It is discarded as soon as you leave this screen.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'You can say no — the directory still works, it just '
                      'won\'t be sorted by distance.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Not now'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
    );
    return agreed ?? false;
  }
}

class _DisclosurePoint extends StatelessWidget {
  const _DisclosurePoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primaryPurple),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
