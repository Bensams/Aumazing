import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../assessment_result_data.dart';

/// A small muted info affordance that explains a metric in parent-friendly
/// words (AUM-319).
///
/// Tapping opens a bottom sheet listing one or more (term, explanation)
/// pairs. The visual language is copied from [AssessmentDisclaimer]: an
/// [Icons.info_outline_rounded] icon in the muted foreground colour, so the
/// affordance is discoverable without competing with the numbers. The
/// wording lives in [AssessmentLabels] so every surface that shows the same
/// metric explains it the same way.
class MetricInfoIcon extends StatelessWidget {
  const MetricInfoIcon({
    super.key,
    required this.title,
    required this.explanations,
  });

  /// Short heading shown at the top of the explanation sheet.
  final String title;

  /// (term, explanation) pairs, shown in the given order.
  final List<(String, String)> explanations;

  void _show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              for (final (term, explanation) in explanations) ...[
                Text(
                  term,
                  style: AppTextStyles.labelLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  explanation,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _show(context),
      tooltip: AssessmentLabels.metricInfoTooltip,
      icon: const Icon(
        Icons.info_outline_rounded,
        size: 15,
        color: AppColors.mutedForeground,
      ),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    );
  }
}
