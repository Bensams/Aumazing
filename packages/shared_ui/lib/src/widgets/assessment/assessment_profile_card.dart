import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../assessment_result_data.dart';
import 'assessment_section_card.dart';

/// Developmental Profile: one row per area with a 3-segment level meter,
/// plus the sensory observations recorded with the assessment.
class AssessmentProfileCard extends StatelessWidget {
  const AssessmentProfileCard({
    super.key,
    required this.model,
    this.dense = false,
  });

  final AssessmentResultViewModel model;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AssessmentSectionCard(
      label: AssessmentLabels.developmentalProfile,
      emoji: '📋',
      dense: dense,
      children: [
        if (model.profileDisplayName != null &&
            model.profileDisplayName!.isNotEmpty)
          AssessmentKeyValueRow(
            label: 'Profile',
            value: model.profileDisplayName!,
          ),
        ...assessmentWithDividers([
          for (final area in model.areas)
            AssessmentAreaLevelRow(
              label: area.label,
              levelInt: area.levelInt,
              levelName: area.levelName,
            ),
          if (model.sensoryObservations.isNotEmpty)
            AssessmentKeyValueRow(
              label: AssessmentLabels.sensory,
              value: model.sensoryObservations.join(', '),
            ),
        ]),
      ],
    );
  }
}

/// An area name with its level meter and level name.
class AssessmentAreaLevelRow extends StatelessWidget {
  const AssessmentAreaLevelRow({
    super.key,
    required this.label,
    required this.levelInt,
    required this.levelName,
  });

  final String label;
  final int levelInt;
  final String levelName;

  @override
  Widget build(BuildContext context) {
    final color = AssessmentPalette.level(levelInt);
    return Semantics(
      label: '$label: $levelName',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AssessmentLevelMeter(filled: levelInt + 1, color: color),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                levelName,
                textAlign: TextAlign.right,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
