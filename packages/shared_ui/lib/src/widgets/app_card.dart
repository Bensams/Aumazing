import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.shadow,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: color ?? AppColors.white,
        borderRadius: AppRadius.card,
        boxShadow: shadow ?? AppShadows.card,
      ),
      child: child,
    );
  }
}
