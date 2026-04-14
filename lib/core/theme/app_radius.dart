import 'package:flutter/material.dart';

abstract final class AppRadius {
  static const double small = 16;
  static const double medium = 18;
  static const double large = 20;
  static const double extraLarge = 24;

  // Pre-built BorderRadius values used repeatedly across the UI.
  static const BorderRadius smallBorder = BorderRadius.all(Radius.circular(small));
  static const BorderRadius mediumBorder = BorderRadius.all(Radius.circular(medium));
  static const BorderRadius largeBorder = BorderRadius.all(Radius.circular(large));
  static const BorderRadius extraLargeBorder = BorderRadius.all(Radius.circular(extraLarge));

  // Semantic aliases
  static const BorderRadius card = extraLargeBorder;
  static const BorderRadius button = smallBorder;
  static const BorderRadius gameObject = extraLargeBorder;
  static const BorderRadius chip = BorderRadius.all(Radius.circular(12));
}
