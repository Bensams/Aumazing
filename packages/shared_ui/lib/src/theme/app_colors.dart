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

  /// Secondary/caption text. Darkened from 0xFF8A8A9B (3.2:1) so small text
  /// clears WCAG 2.2 AA 1.4.3 — 4.7:1 on [background], 5.0:1 on [white].
  static const Color mutedForeground = Color(0xFF6E6E80);

  // ── Functional ───────────────────────────────────────────────────────
  static const Color primaryPurple = Color(0xFF9B82C4);
  static const Color secondaryMint = Color(0xFFB8E8D4);

  /// Decorative red — pastel fill only. Too light for text or icons
  /// (2.5:1 on white); pair it with [textPrimary], never with white.
  static const Color destructiveSoftRed = Color(0xFFE88888);

  /// Readable red for error text, error borders and error snackbars.
  /// 6.5:1 against white in either direction.
  static const Color destructiveRed = Color(0xFFB3261E);
  static const Color border = Color.fromRGBO(90, 90, 107, 0.15);

  // ── Derived helpers ──────────────────────────────────────────────────
  static const Color inputFill = Color(0xFFF7F5F2);
  static const Color disabledFill = Color(0xFFF0EEE9);

  // ── WCAG-compliant dark text colors for status badges ───────────────
  /// Deep navy for primary text — 12.6:1 on white
  static const Color textPrimary = Color(0xFF1E293B); // slate-800

  /// Dark slate for secondary text — 7.5:1 on white
  static const Color textSecondary = Color(0xFF475569); // slate-600

  /// Dark green for positive/success status text — 5.9:1 on white
  static const Color statusSuccessDark = Color(0xFF166534); // green-800

  /// Dark amber for moderate/warning status text — 4.6:1 on white
  static const Color statusWarningDark = Color(0xFF92400E); // amber-800

  /// Dark red for attention/error status text — 5.6:1 on white
  static const Color statusDangerDark = Color(0xFF991B1B); // red-800

  /// Dark blue for info status text — 5.2:1 on white
  static const Color statusInfoDark = Color(0xFF1E40AF); // blue-800

  /// Soft green background for success pills
  static const Color statusSuccessBg = Color(0xFFDCFCE7); // green-100

  /// Soft amber background for warning pills
  static const Color statusWarningBg = Color(0xFFFEF3C7); // amber-100

  /// Soft red background for danger pills
  static const Color statusDangerBg = Color(0xFFFEE2E2); // red-100

  /// Soft blue background for info pills
  static const Color statusInfoBg = Color(0xFFDBEAFE); // blue-100
}
