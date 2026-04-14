import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Primary Pastels ──────────────────────────────────────────────────
  static const Color lavender = Color(0xFFD4C5E8);
  static const Color lavenderLight = Color(0xFFE8DEFA);
  static const Color mint = Color(0xFFB8E8D4);
  static const Color mintLight = Color(0xFFD4F4E8);
  static const Color peach = Color(0xFFFFD4C4);
  static const Color peachLight = Color(0xFFFFE8DD);
  static const Color skyBlue = Color(0xFFB8D8F0);
  static const Color skyLight = Color(0xFFD4E8FA);
  static const Color butterYellow = Color(0xFFFFF4C4);
  static const Color butterLight = Color(0xFFFFF9DD);

  // ── Neutrals ─────────────────────────────────────────────────────────
  static const Color background = Color(0xFFFAF9F6);
  static const Color foreground = Color(0xFF5A5A6B);
  static const Color white = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFFF0EEE9);
  static const Color mutedForeground = Color(0xFF8A8A9B);

  // ── Functional ───────────────────────────────────────────────────────
  static const Color primaryPurple = Color(0xFF9B82C4);
  static const Color secondaryMint = Color(0xFFB8E8D4);
  static const Color destructiveSoftRed = Color(0xFFE88888);
  static const Color border = Color.fromRGBO(90, 90, 107, 0.15);

  // ── Derived helpers ──────────────────────────────────────────────────
  static const Color inputFill = Color(0xFFF7F5F2);
  static const Color disabledFill = Color(0xFFF0EEE9);
}
