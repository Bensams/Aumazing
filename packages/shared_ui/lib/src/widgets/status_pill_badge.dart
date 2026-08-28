import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_radius.dart';

/// Semantic status level for the pill badge.
enum StatusLevel {
  /// Green — strong, good, sustained, ≥80%
  success,

  /// Amber — developing, moderate, improving, 50-79%
  warning,

  /// Red — emerging, needs support, short attention, <50%
  danger,

  /// Blue — informational, neutral status
  info,

  /// Gray — default, no semantic meaning
  neutral,
}

/// A WCAG-compliant pill-shaped status badge.
///
/// Replaces floating colored text with a distinct, accessible badge
/// that uses dark text on a light tinted background for ≥4.5:1 contrast.
///
/// Usage:
/// ```dart
/// StatusPillBadge(label: '94%', level: StatusLevel.success)
/// StatusPillBadge(label: 'developing', level: StatusLevel.warning)
/// StatusPillBadge(label: 'emerging', level: StatusLevel.danger)
/// StatusPillBadge.fromScore(94) // auto-selects level based on score
/// StatusPillBadge.fromLabel('developing') // auto-selects level based on known labels
/// ```
class StatusPillBadge extends StatelessWidget {
  const StatusPillBadge({
    super.key,
    required this.label,
    required this.level,
    this.icon,
    this.fontSize,
    this.compact = false,
  });

  /// The text to display inside the badge.
  final String label;

  /// Semantic status level controlling colors.
  final StatusLevel level;

  /// Optional leading icon widget (emoji Text or Icon).
  final Widget? icon;

  /// Override font size (default: 12).
  final double? fontSize;

  /// If true, uses smaller padding for inline use.
  final bool compact;

  /// Factory: auto-select level from a percentage score.
  factory StatusPillBadge.fromScore(
    int score, {
    Key? key,
    bool compact = false,
  }) {
    final StatusLevel level;
    if (score >= 80) {
      level = StatusLevel.success;
    } else if (score >= 50) {
      level = StatusLevel.warning;
    } else {
      level = StatusLevel.danger;
    }
    return StatusPillBadge(
      key: key,
      label: '$score%',
      level: level,
      compact: compact,
    );
  }

  /// Factory: auto-select level from a known status label string.
  factory StatusPillBadge.fromLabel(
    String label, {
    Key? key,
    bool compact = false,
  }) {
    final lower = label.toLowerCase().trim();
    final StatusLevel level;

    // Success labels
    if (['strong', 'good', 'sustained', 'excellent', 'proficient']
        .contains(lower)) {
      level = StatusLevel.success;
    }
    // Warning labels
    else if (['developing', 'moderate', 'improving', 'emerging']
        .contains(lower)) {
      level = StatusLevel.warning;
    }
    // Danger labels
    else if (['needs support', 'short attention', 'limited', 'weak']
        .contains(lower)) {
      level = StatusLevel.danger;
    }
    // Info labels
    else if (['prefers no music', 'low stimulation', 'combined']
        .contains(lower)) {
      level = StatusLevel.info;
    }
    // Default
    else {
      level = StatusLevel.neutral;
    }

    return StatusPillBadge(
      key: key,
      label: label,
      level: level,
      compact: compact,
    );
  }

  /// Returns the background color for the given level.
  Color _backgroundColor() {
    switch (level) {
      case StatusLevel.success:
        return AppColors.statusSuccessBg;
      case StatusLevel.warning:
        return AppColors.statusWarningBg;
      case StatusLevel.danger:
        return AppColors.statusDangerBg;
      case StatusLevel.info:
        return AppColors.statusInfoBg;
      case StatusLevel.neutral:
        return AppColors.muted;
    }
  }

  /// Returns the text color for the given level.
  Color _textColor() {
    switch (level) {
      case StatusLevel.success:
        return AppColors.statusSuccessDark;
      case StatusLevel.warning:
        return AppColors.statusWarningDark;
      case StatusLevel.danger:
        return AppColors.statusDangerDark;
      case StatusLevel.info:
        return AppColors.statusInfoDark;
      case StatusLevel.neutral:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _backgroundColor();
    final txtColor = _textColor();
    final hPad = compact ? 8.0 : 12.0;
    final vPad = compact ? 2.0 : 4.0;

    return Semantics(
      label: label,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: AppRadius.chip,
          border: Border.all(
            color: txtColor.withAlpha(40),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              icon!,
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: AppTextStyles.statusBadge.copyWith(
                color: txtColor,
                fontSize: fontSize ?? 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
