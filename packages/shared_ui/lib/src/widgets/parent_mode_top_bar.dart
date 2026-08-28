import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// A clean top bar for parent-facing screens in portrait mode.
class ParentModeTopBar extends StatelessWidget implements PreferredSizeWidget {
  const ParentModeTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions,
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 48,
      centerTitle: false,
      titleSpacing: 0,
      leading: onBack != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.foreground,
              onPressed: onBack,
            )
          : null,
      title: Text(title, style: AppTextStyles.titleLarge),
      actions: [
        if (actions != null) ...actions!,
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}
