import 'package:flutter/material.dart';

import '../assessment_result_data.dart';
import 'assessment_section_card.dart';

/// Recommended Settings — the settings finalized with this assessment run.
///
/// Never regenerated from the child's current settings: reopening an older
/// summary shows what was recommended then.
class AssessmentRecommendationsCard extends StatelessWidget {
  const AssessmentRecommendationsCard({
    super.key,
    required this.recommendations,
    this.dense = false,
  });

  final List<ResultRecommendation> recommendations;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AssessmentSectionCard(
      label: AssessmentLabels.recommendedSettings,
      emoji: '💡',
      dense: dense,
      children: assessmentWithDividers([
        for (final recommendation in recommendations)
          AssessmentKeyValueRow(
            icon: recommendation.icon,
            label: recommendation.label,
            value: recommendation.value,
          ),
      ]),
    );
  }
}
