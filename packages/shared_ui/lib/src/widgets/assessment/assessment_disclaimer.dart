import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../assessment_result_data.dart';

/// The non-diagnosis disclaimer. Same wording and treatment everywhere an
/// assessment result is shown.
class AssessmentDisclaimer extends StatelessWidget {
  const AssessmentDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 15,
          color: AppColors.mutedForeground,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AssessmentLabels.disclaimer,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
        ),
      ],
    );
  }
}
