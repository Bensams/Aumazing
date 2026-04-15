import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'parent_mode_icon_button.dart';
import 'progress_dots.dart';

/// Top bar for child game screens: progress dots on the left, parent lock on
/// the right. Designed for landscape layout.
class ChildModeTopBar extends StatelessWidget {
  const ChildModeTopBar({
    super.key,
    required this.totalSteps,
    required this.currentStep,
    required this.onParentTap,
  });

  final int totalSteps;
  final int currentStep;
  final VoidCallback onParentTap;

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
            ParentModeIconButton(onLongPress: onParentTap),
          ],
        ),
      ),
    );
  }
}
