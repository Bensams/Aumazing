import 'dart:math';

import 'package:flutter/animation.dart';

/// Sine curve for gentle sway/wobble animations.
///
/// Maps 0→0 and 1→1 with sine wave oscillation in between.
/// Used by balloon, bubble, and candy reward animations.
class SineCurve extends Curve {
  /// Number of sine wave cycles during the animation.
  final int cycles;

  /// Amplitude of the sine wave oscillation.
  final double amplitude;

  const SineCurve({this.cycles = 1, this.amplitude = 0.5});

  @override
  double transform(double t) {
    // Linear progression from 0 to 1 with sine wobble added.
    // At t=0: returns 0, at t=1: returns 1 (with sine(2π * cycles) ≈ 0)
    return t + sin(t * 2 * pi * cycles) * amplitude;
  }
}
