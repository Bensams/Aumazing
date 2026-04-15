import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class ProgressDots extends StatelessWidget {
  const ProgressDots({
    super.key,
    required this.total,
    required this.current,
    this.activeColor,
    this.inactiveColor,
    this.dotSize = 10,
  });

  final int total;
  final int current;
  final Color? activeColor;
  final Color? inactiveColor;
  final double dotSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (index) {
        final isActive = index <= current;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: isActive ? dotSize * 2.5 : dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: isActive
                  ? (activeColor ?? AppColors.primaryPurple)
                  : (inactiveColor ?? AppColors.muted),
              borderRadius: BorderRadius.circular(dotSize / 2),
            ),
          ),
        );
      }),
    );
  }
}
