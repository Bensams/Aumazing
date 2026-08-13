import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Flat white card with a hairline border and an uppercase section label.
///
/// Every result section uses this shell so the completion and review modes
/// share one visual system; [dense] only tightens the padding, it never
/// removes or hides content.
class AssessmentSectionCard extends StatelessWidget {
  const AssessmentSectionCard({
    super.key,
    required this.label,
    required this.children,
    this.emoji,
    this.trailing,
    this.dense = false,
  });

  final String label;
  final List<Widget> children;
  final String? emoji;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: dense
          ? const EdgeInsets.fromLTRB(14, 12, 14, 10)
          : const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (emoji != null) ...[
                Text(emoji!, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
              ],
              Expanded(child: AssessmentSubLabel(label)),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// Uppercase micro-label used for section titles and sub-headings.
class AssessmentSubLabel extends StatelessWidget {
  const AssessmentSubLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.mutedForeground,
        letterSpacing: 1.0,
        fontSize: 11,
      ),
    );
  }
}

/// Interleaves hairline dividers between [rows].
List<Widget> assessmentWithDividers(List<Widget> rows) => [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0)
          const Divider(height: 1, thickness: 1, color: AppColors.border),
        rows[i],
      ],
    ];

/// Three small rounded segments; [filled] of them are tinted with [color].
class AssessmentLevelMeter extends StatelessWidget {
  const AssessmentLevelMeter({
    super.key,
    required this.filled,
    required this.color,
  });

  final int filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
            child: Container(
              width: 14,
              height: 5,
              decoration: BoxDecoration(
                color: i < filled ? color : AppColors.muted,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}

/// Performance colours and level colours — one mapping for every surface.
abstract final class AssessmentPalette {
  /// Colour for a 0–100 performance percentage.
  static Color performance(int percent) {
    if (percent >= 80) return AppColors.statusSuccessDark;
    if (percent >= 50) return AppColors.statusWarningDark;
    return AppColors.statusDangerDark;
  }

  /// Background tint for a 0–100 performance percentage.
  static Color performanceBackground(int percent) {
    if (percent >= 80) return AppColors.statusSuccessBg;
    if (percent >= 50) return AppColors.statusWarningBg;
    return AppColors.statusDangerBg;
  }

  /// Parent-facing word for a 0–100 performance percentage.
  static String performanceLabel(int percent) {
    if (percent >= 80) return 'Strong';
    if (percent >= 50) return 'Steady';
    return 'Needs practice';
  }

  /// Colour for a developmental level ordinal (0–2).
  static Color level(int levelInt) {
    switch (levelInt) {
      case 0:
        return AppColors.statusWarningDark;
      case 2:
        return AppColors.statusSuccessDark;
      default:
        return AppColors.statusInfoDark;
    }
  }

  /// Maps a free-form level label to an ordinal, or null when unknown.
  static int? levelIntFromLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('strength') || l.contains('strong')) return 2;
    if (l.contains('emerging') ||
        l.contains('developing') ||
        l.contains('good') ||
        l.contains('moderate')) {
      return 1;
    }
    if (l.contains('support') || l.contains('delayed')) return 0;
    return null;
  }
}

/// A label/value row that wraps instead of truncating at large text scales.
class AssessmentKeyValueRow extends StatelessWidget {
  const AssessmentKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.lavenderLight,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: AppColors.primaryPurple),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyMedium.copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row showing a label, a slim progress bar and its percentage.
class AssessmentMeterRow extends StatelessWidget {
  const AssessmentMeterRow({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.secondaryLabel,
    this.semanticsLabel,
  });

  /// 0.0–1.0.
  final double value;
  final String label;
  final Color color;

  /// Optional raw-count caption shown under the label.
  final String? secondaryLabel;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final percent = (value.clamp(0.0, 1.0) * 100).round();
    return Semantics(
      label: semanticsLabel ?? '$label, $percent percent',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (secondaryLabel != null)
                    Text(
                      secondaryLabel!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              height: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  backgroundColor: AppColors.muted,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$percent%',
              textAlign: TextAlign.right,
              style: AppTextStyles.titleMedium.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
