import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../assessment_result_data.dart';
import 'assessment_section_card.dart';

/// Overall Performance, the raw counts behind it, the analysis confidence
/// and the parent-friendly summary.
///
/// The headline percentage is the item-weighted adjusted accuracy from
/// [AssessmentScoring] — the same number in both presentations, and directly
/// comparable with the per-game percentages in the Game Results card. Raw
/// counts sit beside it, explicitly labelled as counts.
class AssessmentOverviewCard extends StatelessWidget {
  const AssessmentOverviewCard({
    super.key,
    required this.model,
    this.dense = false,
  });

  final AssessmentResultViewModel model;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final percent = model.overallPercent;
    final color = AssessmentPalette.performance(percent);
    final confidencePercent = model.confidencePercent;

    return AssessmentSectionCard(
      label: AssessmentLabels.overallPerformance,
      dense: dense,
      children: [
        Semantics(
          label: '${AssessmentLabels.overallPerformance}: $percent percent, '
              '${AssessmentPalette.performanceLabel(percent)}',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AssessmentPalette.performanceBackground(percent),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withAlpha(40)),
                ),
                child: Text(
                  '$percent%',
                  style: AppTextStyles.headlineSmall.copyWith(color: color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AssessmentPalette.performanceLabel(percent),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Raw counts — never presented as a percentage.
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _CountChip(
              emoji: '✅',
              label: AssessmentLabels.correct,
              value: model.correctCount,
            ),
            _CountChip(
              emoji: '❌',
              label: AssessmentLabels.errors,
              value: model.errorCount,
            ),
            _CountChip(
              emoji: '📝',
              label: AssessmentLabels.totalItems,
              value: model.totalItems,
            ),
          ],
        ),
        if (confidencePercent != null) ...[
          const SizedBox(height: 12),
          _ConfidenceRow(confidence: model.confidence!),
        ],
        if (model.summary.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (model.summaryIsAi) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('✨', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Text(
                        AssessmentLabels.aiSummary,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.primaryPurple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  model.summary,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.emoji,
    required this.label,
    required this.value,
  });

  final String emoji;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            Text(
              '$value',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confidence bar with the same thresholds, colours and rounding in both
/// presentations, plus a plain-language explanation for parents.
class _ConfidenceRow extends StatelessWidget {
  const _ConfidenceRow({required this.confidence});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    final percent = AssessmentScoring.percent(confidence);
    final color = confidence >= 0.8
        ? AppColors.statusSuccessDark
        : confidence >= 0.6
            ? AppColors.statusWarningDark
            : AppColors.statusDangerDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '${AssessmentLabels.confidence}: $percent percent',
          excludeSemantics: true,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AssessmentLabels.confidence,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 72,
                height: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: confidence.clamp(0.0, 1.0),
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
        const SizedBox(height: 4),
        Text(
          'How sure the analysis is about these observations.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.mutedForeground,
          ),
        ),
      ],
    );
  }
}
