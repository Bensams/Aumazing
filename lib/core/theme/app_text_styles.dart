import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTextStyles {
  // ── Base font families ───────────────────────────────────────────────
  static String get _poppins => GoogleFonts.poppins().fontFamily!;
  static String get _nunito => GoogleFonts.nunito().fontFamily!;

  // ── Heading styles (Poppins) ─────────────────────────────────────────
  static TextStyle get displayLarge => TextStyle(
        fontFamily: _poppins,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
        height: 1.2,
      );

  static TextStyle get displayMedium => TextStyle(
        fontFamily: _poppins,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
        height: 1.25,
      );

  static TextStyle get headlineLarge => TextStyle(
        fontFamily: _poppins,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.foreground,
        height: 1.3,
      );

  static TextStyle get headlineMedium => TextStyle(
        fontFamily: _poppins,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.foreground,
        height: 1.3,
      );

  static TextStyle get headlineSmall => TextStyle(
        fontFamily: _poppins,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.foreground,
        height: 1.35,
      );

  static TextStyle get titleLarge => TextStyle(
        fontFamily: _poppins,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.foreground,
        height: 1.4,
      );

  static TextStyle get titleMedium => TextStyle(
        fontFamily: _poppins,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.foreground,
        height: 1.4,
      );

  // ── Body styles (Nunito) ─────────────────────────────────────────────
  static TextStyle get bodyLarge => TextStyle(
        fontFamily: _nunito,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.foreground,
        height: 1.5,
      );

  static TextStyle get bodyMedium => TextStyle(
        fontFamily: _nunito,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.foreground,
        height: 1.5,
      );

  static TextStyle get bodySmall => TextStyle(
        fontFamily: _nunito,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.mutedForeground,
        height: 1.5,
      );

  // ── Button / label styles (Poppins) ──────────────────────────────────
  static TextStyle get buttonLarge => TextStyle(
        fontFamily: _poppins,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
        height: 1.2,
      );

  static TextStyle get buttonMedium => TextStyle(
        fontFamily: _poppins,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
        height: 1.2,
      );

  static TextStyle get labelLarge => TextStyle(
        fontFamily: _poppins,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.foreground,
        height: 1.4,
      );

  static TextStyle get labelSmall => TextStyle(
        fontFamily: _nunito,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.mutedForeground,
        height: 1.4,
        letterSpacing: 0.5,
      );
}
