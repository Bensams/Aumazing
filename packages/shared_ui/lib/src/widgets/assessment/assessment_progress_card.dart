import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../assessment_result_data.dart';
import 'assessment_section_card.dart';

/// Run-wide accuracy and response-time change between pre and post runs.
class AssessmentOverallProgressCard extends StatelessWidget {
  const AssessmentOverallProgressCard({
    super.key,
    required this.progress,
    this.dense = false,
  });

  final ResultOverallProgress progress;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final accuracyPct = (progress.accuracyDelta * 100).round();
    final improved = accuracyPct > 0;
    final steady = accuracyPct == 0;
    final timeDelta = progress.responseTimeDeltaMs;

    return AssessmentSectionCard(
      label: AssessmentLabels.overallProgress,
      emoji: '📊',
      dense: dense,
      children: [
        Row(
          children: [
            Icon(
              improved
                  ? Icons.trending_up_rounded
                  : steady
                  ? Icons.trending_flat_rounded
                  : Icons.trending_down_rounded,
              color:
                  improved || steady
                      ? AppColors.statusSuccessDark
                      : AppColors.mutedForeground,
              size: 32,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                improved
                    ? 'Accuracy improved by $accuracyPct percentage points '
                        'since the pre-assessment.'
                    : steady
                    ? 'Accuracy held steady since the pre-assessment.'
                    : 'Accuracy changed by $accuracyPct percentage points — '
                        'every child progresses at their own pace.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        if (timeDelta.abs() >= 100)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              timeDelta > 0
                  ? 'Responses are ${(timeDelta / 1000).toStringAsFixed(1)}s '
                      'faster on average.'
                  : 'Responses take a little longer — often a sign of more '
                      'careful choices.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }
}

/// Progress Since the First Assessment — a before-and-after view of each
/// developmental area across two comparable runs (AUM-161).
///
/// Wording rules this card exists to enforce:
/// * it reports how *skills in activities* moved, never a condition;
/// * "held steady" is stated neutrally — no growth is not a failure, and a
///   parent must never read a flat result as a warning;
/// * a drop is phrased as needing more practice, not as regression or loss.
class AssessmentProgressCard extends StatelessWidget {
  const AssessmentProgressCard({
    super.key,
    required this.progress,
    this.dense = false,
  });

  final ResultProgress progress;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AssessmentSectionCard(
      label: AssessmentLabels.progressSinceFirst,
      emoji: '📈',
      dense: dense,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            progress.headline,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...assessmentWithDividers([
          for (final area in progress.areas) _AreaChangeRow(area: area),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'This compares how your child did in the activities on two '
            'different days. It describes practice, not a diagnosis.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
        ),
      ],
    );
  }
}

class _AreaChangeRow extends StatelessWidget {
  const _AreaChangeRow({required this.area});

  final ResultProgressArea area;

  /// Neutral for steady, warm for growth, gently practical for a drop.
  String get _change {
    if (area.improved) return 'Moved up';
    if (area.steady) return 'Held steady';
    return 'More practice here';
  }

  Color get _changeColor {
    if (area.improved) return AppColors.statusSuccessDark;
    if (area.steady) return AppColors.textSecondary;
    return AppColors.statusWarningDark;
  }

  IconData get _icon {
    if (area.improved) return Icons.trending_up_rounded;
    if (area.steady) return Icons.trending_flat_rounded;
    return Icons.trending_down_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${area.label}: was ${area.beforeLevelName}, '
          'now ${area.afterLevelName}. $_change.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(_icon, size: 18, color: _changeColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    area.label,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${area.beforeLevelName} → ${area.afterLevelName}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _change,
              textAlign: TextAlign.end,
              style: AppTextStyles.labelSmall.copyWith(
                color: _changeColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
