import 'package:flutter/material.dart';

/// Wraps a screen's body in a full-bleed gradient background.
class AppGradientBackground extends StatelessWidget {
  const AppGradientBackground({
    super.key,
    required this.gradient,
    required this.child,
  });

  final LinearGradient gradient;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: child,
    );
  }
}
