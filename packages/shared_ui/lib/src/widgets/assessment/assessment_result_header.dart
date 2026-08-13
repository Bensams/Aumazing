import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../assessment_result_data.dart';

/// Title block for an assessment result: eyebrow, heading, analysis source
/// and — in review mode — the date the assessment was completed.
///
/// Both presentations use the same heading ("Assessment Summary") and the
/// same source label; only the supporting line differs.
class AssessmentResultHeader extends StatelessWidget {
  const AssessmentResultHeader({
    super.key,
    required this.model,
    required this.presentation,
    this.onBack,
  });

  final AssessmentResultViewModel model;
  final AssessmentResultPresentation presentation;

  /// Review mode only: shows a back affordance beside the heading.
  final VoidCallback? onBack;

  bool get _isCompletion =>
      presentation == AssessmentResultPresentation.completion;

  String get _eyebrow =>
      model.assessmentType == 'post' ? 'POST-ASSESSMENT' : 'PRE-ASSESSMENT';

  String get _supportingLine {
    if (_isCompletion) {
      return '🎉 Great job! Here’s a summary of how your child played the '
          'assessment games, and how we’ll tune their activities.';
    }
    final completedAt = model.completedAt;
    if (completedAt == null) {
      return 'A summary of how your child played the assessment games.';
    }
    return 'Completed ${_formatDate(completedAt)}.';
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = date.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (onBack != null) ...[
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.primaryPurple,
                  tooltip: 'Back',
                  onPressed: onBack,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                _eyebrow,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primaryPurple,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AssessmentSourceTag(source: model.source),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          AssessmentLabels.title,
          style: AppTextStyles.headlineLarge.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _supportingLine,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

/// Quiet inline tag naming the analysis source.
///
/// Shows the same three labels everywhere: AI Analysis, On-Device AI,
/// Rule-Based.
class AssessmentSourceTag extends StatelessWidget {
  const AssessmentSourceTag({super.key, required this.source});

  final AssessmentAnalysisSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: source.isAi ? AppColors.primaryPurple : AppColors.skyBlue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            source.label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
