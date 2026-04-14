import 'package:flutter/material.dart';

abstract final class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color.fromRGBO(90, 90, 107, 0.06),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color.fromRGBO(90, 90, 107, 0.04),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> interactive = [
    BoxShadow(
      color: Color.fromRGBO(155, 130, 196, 0.18),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color.fromRGBO(155, 130, 196, 0.08),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> modal = [
    BoxShadow(
      color: Color.fromRGBO(90, 90, 107, 0.12),
      blurRadius: 32,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color.fromRGBO(90, 90, 107, 0.06),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];
}
