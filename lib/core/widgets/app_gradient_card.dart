import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

class AppGradientCard extends StatelessWidget {
  const AppGradientCard({
    super.key,
    required this.gradient,
    required this.child,
    this.padding,
    this.shadow,
  });

  final LinearGradient gradient;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? AppSpacing.paddingLg,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: AppRadius.card,
        boxShadow: shadow ?? AppShadows.card,
      ),
      child: child,
    );
  }
}
