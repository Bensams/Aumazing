import 'package:flutter/material.dart';

import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_touch_targets.dart';

/// A large, ASD-friendly interactive card for child game screens.
/// Includes soft bounce animation on tap.
class LargeGameObjectCard extends StatefulWidget {
  const LargeGameObjectCard({
    super.key,
    required this.child,
    required this.onTap,
    this.size = AppTouchTargets.large,
    this.color,
    this.isHighlighted = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final double size;
  final Color? color;
  final bool isHighlighted;

  @override
  State<LargeGameObjectCard> createState() => _LargeGameObjectCardState();
}

class _LargeGameObjectCardState extends State<LargeGameObjectCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: AppAnimations.cueLoop,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: AppAnimations.pulseScaleMax)
        .animate(CurvedAnimation(
      parent: _pulseController,
      curve: AppAnimations.defaultCurve,
    ));
  }

  @override
  void didUpdateWidget(covariant LargeGameObjectCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHighlighted && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isHighlighted && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedBuilder(
        listenable: _pulseAnimation,
        builder: (context, child) {
          final pulseScale =
              widget.isHighlighted ? _pulseAnimation.value : 1.0;
          final tapScale = _pressed ? AppAnimations.tapScaleFactor : 1.0;

          return Transform.scale(
            scale: pulseScale * tapScale,
            child: child,
          );
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color ?? AppColors.white,
            borderRadius: AppRadius.gameObject,
            boxShadow: widget.isHighlighted
                ? AppShadows.interactive
                : AppShadows.card,
            border: widget.isHighlighted
                ? Border.all(
                    color: AppColors.primaryPurple.withAlpha(80), width: 2)
                : null,
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}

/// A simple [AnimatedWidget] wrapper that takes a builder callback,
/// similar to Flutter's [AnimatedBuilder] but avoids any naming conflicts.
class AnimatedBuilder extends StatelessWidget {
  const AnimatedBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
  });

  final Listenable listenable;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => builder(context, child),
      child: child,
    );
  }
}
