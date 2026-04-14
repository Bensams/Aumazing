import 'package:flutter/material.dart';

import '../theme/app_animations.dart';
import '../theme/app_colors.dart';

/// A small icon button placed in the top-right of child screens to allow
/// parents to exit child mode. Requires a long press to prevent accidental taps.
class ParentModeIconButton extends StatefulWidget {
  const ParentModeIconButton({
    super.key,
    required this.onLongPress,
  });

  final VoidCallback onLongPress;

  @override
  State<ParentModeIconButton> createState() => _ParentModeIconButtonState();
}

class _ParentModeIconButtonState extends State<ParentModeIconButton> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Exit child mode',
      hint: 'Long press to exit child mode',
      button: true,
      onLongPress: widget.onLongPress,
      child: Tooltip(
        message: 'Exit child mode (long press)',
        child: GestureDetector(
          onLongPress: widget.onLongPress,
          onLongPressStart: (_) => setState(() => _pressing = true),
          onLongPressEnd: (_) => setState(() => _pressing = false),
          onLongPressCancel: () => setState(() => _pressing = false),
          child: AnimatedScale(
            scale: _pressing ? 0.9 : 1.0,
            duration: AppAnimations.tapFeedback,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.white.withAlpha(200),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 20,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
