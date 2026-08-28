import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// A circular hue/saturation wheel with a brightness slider underneath.
///
/// Hand-painted rather than pulled from a package: the app ships offline to
/// low-end Android devices, and this is two `CustomPainter`s.
///
/// Hue runs around the wheel, saturation from the white centre to the rim,
/// and brightness is the slider — splitting it that way keeps the wheel
/// itself readable at small sizes.
///
/// A wheel is a drag surface, which a screen-reader or switch user cannot
/// operate. It is never the only way to choose a colour: the caller pairs it
/// with tappable swatches, and the wheel exposes adjustable semantics so the
/// hue can still be stepped without dragging.
class ColorWheelPicker extends StatelessWidget {
  const ColorWheelPicker({
    super.key,
    required this.colour,
    required this.onChanged,
    this.diameter = 200,
    this.label = 'Background colour',
  });

  final Color colour;
  final ValueChanged<Color> onChanged;
  final double diameter;

  /// Spoken name, e.g. "Start colour" for the gradient's first stop.
  final String label;

  HSVColor get _hsv => HSVColor.fromColor(colour);

  /// Hue moved by [degrees], wrapped into 0–360.
  static double _steppedHue(HSVColor hsv, double degrees) =>
      (hsv.hue + degrees + 360) % 360;

  void _handlePoint(Offset local) {
    final radius = diameter / 2;
    final centre = Offset(radius, radius);
    final delta = local - centre;
    final distance = delta.distance;
    // Past the rim still counts, clamped — dragging off the edge should pin
    // to full saturation rather than snapping the thumb back to the middle.
    final saturation = (distance / radius).clamp(0.0, 1.0);
    var hue = math.atan2(delta.dy, delta.dx) * 180 / math.pi + 90;
    if (hue < 0) hue += 360;
    onChanged(_hsv.withHue(hue % 360).withSaturation(saturation).toColor());
  }

  @override
  Widget build(BuildContext context) {
    final hsv = _hsv;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '$label hue',
          value: '${hsv.hue.round()} degrees',
          // Flutter asserts that an adjustable node annotates either both
          // `value` and `increasedValue` or neither — omitting these threw
          // as soon as a screen reader turned semantics on, which is the one
          // situation this control exists for.
          increasedValue: '${_steppedHue(hsv, 15).round()} degrees',
          decreasedValue: '${_steppedHue(hsv, -15).round()} degrees',
          slider: true,
          // Stepping by 15° gives 24 reachable hues without dragging.
          onIncrease: () =>
              onChanged(hsv.withHue(_steppedHue(hsv, 15)).toColor()),
          onDecrease: () =>
              onChanged(hsv.withHue(_steppedHue(hsv, -15)).toColor()),
          child: GestureDetector(
            onPanDown: (d) => _handlePoint(d.localPosition),
            onPanUpdate: (d) => _handlePoint(d.localPosition),
            child: SizedBox(
              width: diameter,
              height: diameter,
              child: CustomPaint(
                painter: _WheelPainter(hsv: hsv),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            const Icon(Icons.brightness_low_rounded,
                size: 18, color: AppColors.mutedForeground),
            Expanded(
              child: Slider(
                value: hsv.value,
                label: '${(hsv.value * 100).round()}%',
                divisions: 20,
                semanticFormatterCallback: (v) =>
                    '$label brightness ${(v * 100).round()} percent',
                onChanged: (v) => onChanged(hsv.withValue(v).toColor()),
              ),
            ),
            const Icon(Icons.brightness_high_rounded,
                size: 18, color: AppColors.mutedForeground),
          ],
        ),
        Text(
          '#${_hex(colour)}',
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.mutedForeground,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  static String _hex(Color c) => c
      .toARGB32()
      .toRadixString(16)
      .padLeft(8, '0')
      .substring(2)
      .toUpperCase();
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final centre = Offset(radius, radius);
    final rect = Rect.fromCircle(center: centre, radius: radius);

    // Hue ring. Starts at -90° so red sits at the top, which is what a
    // parent expects from a colour wheel.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [
            for (var h = 0; h <= 360; h += 30)
              HSVColor.fromAHSV(1, h % 360, 1, hsv.value).toColor(),
          ],
        ).createShader(rect),
    );

    // Saturation falls off towards the centre, which is white at full
    // brightness and grey as the slider comes down — so the wheel always
    // shows the colours the current brightness can actually produce.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            HSVColor.fromAHSV(1, 0, 0, hsv.value).toColor(),
            HSVColor.fromAHSV(0, 0, 0, hsv.value).toColor(),
          ],
        ).createShader(rect),
    );

    // Rim, so the wheel has an edge against a white settings card.
    canvas.drawCircle(
      centre,
      radius - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.border,
    );

    // Thumb.
    final angle = (hsv.hue - 90) * math.pi / 180;
    final thumb = centre +
        Offset(math.cos(angle), math.sin(angle)) * (hsv.saturation * radius);
    canvas.drawCircle(thumb, 11, Paint()..color = AppColors.white);
    canvas.drawCircle(
      thumb,
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.foreground.withValues(alpha: 0.55),
    );
    canvas.drawCircle(thumb, 7.5, Paint()..color = hsv.toColor());
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hsv != hsv;
}
