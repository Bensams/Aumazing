import 'package:flutter/material.dart';

import '../theme/app_radius.dart';

/// A card frame with an animated rainbow outline that flows left → right.
///
/// The border is drawn as a repeating linear gradient that is translated
/// horizontally by one full colour cycle per [period]; because the colour
/// list starts and ends on the same hue the loop is seamless. Used to make
/// the Premium upgrade card stand out on the parent dashboard.
///
/// Honours the platform "reduce motion" setting: when animations are
/// disabled the border is rendered as a static rainbow.
class RainbowBorderCard extends StatefulWidget {
  const RainbowBorderCard({
    super.key,
    required this.child,
    this.borderWidth = 3,
    this.borderRadius,
    this.period = const Duration(seconds: 3),
  });

  final Widget child;

  /// Thickness of the rainbow outline.
  final double borderWidth;

  /// Radius of the outline. Defaults to the card radius grown by
  /// [borderWidth] so the inset child's own corners sit concentrically
  /// inside it instead of clipping the outline.
  final BorderRadius? borderRadius;

  /// Time for one full colour cycle to travel across the card.
  final Duration period;

  /// Rainbow sweep, repeated so the gradient tiles seamlessly.
  static const List<Color> colors = [
    Color(0xFFFF5F6D), // red
    Color(0xFFFFA751), // orange
    Color(0xFFFFE259), // yellow
    Color(0xFF56E39F), // green
    Color(0xFF4FC3F7), // blue
    Color(0xFF9D7BEA), // violet
    Color(0xFFFF5F6D), // back to red — closes the loop
  ];

  @override
  State<RainbowBorderCard> createState() => _RainbowBorderCardState();
}

class _RainbowBorderCardState extends State<RainbowBorderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void didUpdateWidget(RainbowBorderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period) {
      _controller.duration = widget.period;
      _controller
        ..reset()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final radius = widget.borderRadius ??
        BorderRadius.circular(AppRadius.extraLarge + widget.borderWidth);
    final inner = Padding(
      padding: EdgeInsets.all(widget.borderWidth),
      child: widget.child,
    );

    Widget frame(double t) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: RainbowBorderCard.colors,
              tileMode: TileMode.repeated,
              transform: _SlidingGradient(t),
            ),
          ),
          child: inner,
        );

    if (reduceMotion) return frame(0);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => frame(_controller.value),
    );
  }
}

/// Shifts a horizontal gradient by [progress] of the paint box's width.
class _SlidingGradient extends GradientTransform {
  const _SlidingGradient(this.progress);

  final double progress;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * progress, 0, 0);
  }
}
