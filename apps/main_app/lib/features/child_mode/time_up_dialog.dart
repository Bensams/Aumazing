import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../services/screen_time_service.dart';

/// Gentle "time for a break" screen shown when the daily screen-time limit
/// is reached (FR: restrict/pause gameplay when the limit is exceeded).
///
/// ASD-friendly by design: calm colors, a predictable friendly message, no
/// alarms and no abrupt app exit — the child taps one big button to say
/// goodbye. A small lock lets the parent add extra time for today.
class TimeUpDialog {
  TimeUpDialog._();

  static bool _showing = false;

  /// Shows the dialog above whatever is on screen (lobby or a game).
  /// When the child accepts, pops all the way back to the parent home.
  static Future<void> show(BuildContext context) async {
    if (_showing) return;
    _showing = true;

    try {
      final result = await showDialog<_TimeUpResult>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black38,
        useRootNavigator: true,
        builder: (_) => const _TimeUpContent(),
      );
      if (!context.mounted) return;

      switch (result) {
        case _TimeUpResult.extended:
          // Parent added time — stay where we are and keep playing.
          break;
        case _TimeUpResult.done:
        case null:
          // Say goodbye: leave child mode entirely.
          Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } finally {
      _showing = false;
    }
  }
}

enum _TimeUpResult { done, extended }

class _TimeUpContent extends StatelessWidget {
  const _TimeUpContent();

  Future<void> _parentExtend(BuildContext context) async {
    final verified = await ParentVerificationDialog.show(context);
    if (!verified || !context.mounted) return;
    await ScreenTimeService.instance.extendToday(15);
    if (context.mounted) {
      Navigator.of(context).pop(_TimeUpResult.extended);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🌙', style: TextStyle(fontSize: 56)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Great playing today!',
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineSmall.copyWith(
                  color: AppColors.primaryPurple,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Time for a break. See you tomorrow!',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: 200,
                child: AppPrimaryButton(
                  label: 'Okay!',
                  icon: Icons.waving_hand_rounded,
                  onPressed: () =>
                      Navigator.of(context).pop(_TimeUpResult.done),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Parent-only escape hatch: +15 minutes for today.
              TextButton.icon(
                onPressed: () => _parentExtend(context),
                icon: const Icon(Icons.lock_rounded, size: 16),
                label: const Text('Parent: add 15 minutes'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
