import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../assessment_result_data.dart';
import 'assessment_section_card.dart';

/// Recommended Activities — the child's learning path in "My Path" order,
/// with the starting level for each activity.
class AssessmentLearningPathCard extends StatelessWidget {
  const AssessmentLearningPathCard({
    super.key,
    required this.modules,
    this.unavailable = false,
    this.dense = false,
  });

  final List<ResultModule> modules;

  /// True when every recommendation was filtered out (no active games).
  final bool unavailable;

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AssessmentSectionCard(
      label: AssessmentLabels.recommendedActivities,
      emoji: '⭐',
      dense: dense,
      children: unavailable
          ? [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No activities available right now — please contact your '
                  'administrator.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.statusWarningDark,
                  ),
                ),
              ),
            ]
          : assessmentWithDividers([
              for (var i = 0; i < modules.length; i++)
                _ModuleRow(index: i + 1, module: modules[i]),
            ]),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.index, required this.module});

  final int index;
  final ResultModule module;

  @override
  Widget build(BuildContext context) {
    final reason = module.reason;
    return Semantics(
      label: 'Activity $index: ${module.name}, '
          'level ${module.startingLevel}'
          '${reason == null ? '' : '. $reason'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '$index',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    module.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Level ${module.startingLevel}',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            // Why this activity comes next, in a parent's words (AUM-161).
            // Indented under the name so the list still scans as a sequence.
            if (reason != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 22, right: 10),
                child: Text(
                  reason,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
