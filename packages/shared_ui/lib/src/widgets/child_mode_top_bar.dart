import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'parent_mode_icon_button.dart';
import 'progress_dots.dart';

/// Top bar for child game screens: progress dots on the left, parent lock on
/// the right. Designed for landscape layout.
///
/// In non-assessment (practice / learning-path) games, pass [onRetry] and
/// [onMenu] to show two extra icons — Retry (replay the current game) and Menu
/// (back to the children lobby to pick the next game). Leave them null for
/// assessment games so the icons don't appear.
class ChildModeTopBar extends StatelessWidget {
  const ChildModeTopBar({
    super.key,
    required this.totalSteps,
    required this.currentStep,
    required this.onParentTap,
    this.onRetry,
    this.onMenu,
  });

  final int totalSteps;
  final int currentStep;
  final VoidCallback onParentTap;

  /// Practice-only: replay the current game from the start.
  final VoidCallback? onRetry;

  /// Practice-only: return to the children lobby (choose the next game).
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            ProgressDots(total: totalSteps, current: currentStep),
            const Spacer(),
            if (onRetry != null)
              _CircleIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Retry',
                onTap: onRetry!,
              ),
            if (onMenu != null)
              _CircleIconButton(
                icon: Icons.grid_view_rounded,
                tooltip: 'Games menu',
                onTap: onMenu!,
              ),
            ParentModeIconButton(onLongPress: onParentTap),
          ],
        ),
      ),
    );
  }
}

/// A round white icon button used for the in-game Retry / Menu controls.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: AppColors.white.withAlpha(230),
        shape: const CircleBorder(),
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: AppColors.primaryPurple),
          tooltip: tooltip,
          iconSize: 24,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        ),
      ),
    );
  }
}
