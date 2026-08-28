import 'package:flutter/material.dart';

abstract final class AppAnimations {
  static const Duration cueLoop = Duration(milliseconds: 1750);
  static const Duration tapFeedback = Duration(milliseconds: 200);
  static const Duration pageTransition = Duration(milliseconds: 350);
  static const Duration entrance = Duration(milliseconds: 600);

  static const Curve defaultCurve = Curves.easeInOut;
  static const Curve bounceCurve = Curves.elasticOut;
  static const Curve gentleCurve = Curves.easeOutCubic;

  static const double tapScaleFactor = 0.95;
  static const double pulseScaleMax = 1.05;
}
