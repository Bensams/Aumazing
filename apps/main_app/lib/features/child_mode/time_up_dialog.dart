import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../services/screen_time_service.dart';

/// Screen-time enforcement: a plain, full-screen black rest screen.
///
/// Deliberately featureless for the child — no message, no buttons,
/// nothing that explains or invites negotiation. The session simply ends.
/// The only interactive element is a discreet parent lock in the upper
/// right; after PIN verification the parent can add 15 minutes (resumes
/// play) or exit child mode.
class TimeUpDialog {
  TimeUpDialog._();

  static bool _showing = false;

  /// True while the lock screen is on top (usage counting pauses).
  static bool get isShowing => _showing;

  /// Pushes the lock screen above whatever is on screen (lobby or a game).
  /// If the parent chooses to exit, pops all the way back to the dashboard.
  static Future<void> show(BuildContext context) async {
    if (_showing) return;
    _showing = true;

    try {
      final result = await Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<_LockResult>(
          opaque: true,
          fullscreenDialog: true,
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (_, __, ___) => const _ScreenTimeLockScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
      if (!context.mounted) return;

      if (result != _LockResult.extended) {
        // Parent chose exit (or the route was removed): leave child mode.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } finally {
      _showing = false;
    }
  }
}

enum _LockResult { extended, exit }

class _ScreenTimeLockScreen extends StatelessWidget {
  const _ScreenTimeLockScreen();

  Future<void> _onParentLockTap(BuildContext context) async {
    final verified = await ParentVerificationDialog.show(context);
    if (!verified || !context.mounted) return;

    final choice = await showDialog<_LockResult>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Screen time is up',
          style: AppTextStyles.titleLarge
              .copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'Today\'s play limit has been reached.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_LockResult.extended),
            child: const Text('Add 15 minutes'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_LockResult.exit),
            child: const Text('Exit Child Mode'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice == _LockResult.extended) {
      await ScreenTimeService.instance.extendToday(15);
    }
    if (context.mounted) {
      Navigator.of(context).pop(choice);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              // Discreet parent lock — low contrast on purpose so it does
              // not draw the child's attention.
              child: IconButton(
                onPressed: () => _onParentLockTap(context),
                icon: const Icon(Icons.lock_rounded),
                color: Colors.white24,
                tooltip: 'Parent',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
