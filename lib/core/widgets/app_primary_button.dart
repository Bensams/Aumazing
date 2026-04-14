import 'package:flutter/material.dart';

import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

class AppPrimaryButton extends StatefulWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.gradient,
    this.width,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final LinearGradient? gradient;
  final double? width;

  @override
  State<AppPrimaryButton> createState() => _AppPrimaryButtonState();
}

class _AppPrimaryButtonState extends State<AppPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? AppAnimations.tapScaleFactor : 1.0,
        duration: AppAnimations.tapFeedback,
        curve: AppAnimations.defaultCurve,
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.6,
          duration: AppAnimations.tapFeedback,
          child: Container(
            width: widget.width ?? double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
            decoration: BoxDecoration(
              gradient: enabled
                  ? (widget.gradient ?? AppGradients.primaryCta)
                  : null,
              color: enabled ? null : AppColors.lavender,
              borderRadius: AppRadius.button,
              boxShadow: enabled ? AppShadows.interactive : null,
            ),
            child: Center(
              child: widget.isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: AppColors.white, size: 20),
                          const SizedBox(width: 10),
                        ],
                        Text(widget.label, style: AppTextStyles.buttonLarge),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
