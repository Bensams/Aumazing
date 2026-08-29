import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../assessment_result_data.dart';
import 'assessment_section_card.dart';

/// Recommended Activities — the child's learning path in "My Path" order,
/// with the starting level for each activity.
///
/// With [onOpenPath] the card is also the way *into* that path: reading the
/// list and then hunting for Child Mode → My Path is the errand that quietly
/// does not get run, so the list ends with the door to it. The button is
/// labelled with where it goes and carries a plain instruction to hand the
/// device over, because the screen behind it is the child's, not the parent's.
class AssessmentLearningPathCard extends StatelessWidget {
  const AssessmentLearningPathCard({
    super.key,
    required this.modules,
    this.unavailable = false,
    this.premiumRequired = false,
    this.dense = false,
    this.onOpenPath,
  });

  final List<ResultModule> modules;

  /// True when every recommendation was filtered out (no active games).
  final bool unavailable;

  /// True when a Premium subscription is required to generate the next
  /// personalized module. Distinct from [unavailable] (admin/game issue).
  final bool premiumRequired;

  final bool dense;

  /// Opens the child's My Path view. Null leaves the card read-only, which is
  /// what a host with nowhere to send the child — the game lab, a preview,
  /// a PDF render — should pass.
  final VoidCallback? onOpenPath;

  @override
  Widget build(BuildContext context) {
    return AssessmentSectionCard(
      label: AssessmentLabels.recommendedActivities,
      emoji: '⭐',
      dense: dense,
      children:
          premiumRequired
              ? [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        color: AppColors.primaryPurple,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Premium is required to generate the next '
                          'personalized module. Upgrade to keep building a '
                          'learning path tailored to your child.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ]
              : unavailable
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
              : [
                ...assessmentWithDividers([
                  for (var i = 0; i < modules.length; i++)
                    _ModuleRow(index: i + 1, module: modules[i]),
                ]),
                if (onOpenPath != null && modules.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('open-my-path'),
                      onPressed: onOpenPath,
                      icon: const Icon(Icons.route_rounded, size: 18),
                      label: const Text(AssessmentLabels.goToMyPath),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          kMinInteractiveDimension,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _HandOverNote(),
                ],
              ],
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
      label:
          'Activity $index: ${module.name}, '
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

/// "Hand the device to your child" — the one line a parent needs before they
/// tap into a child-facing screen. Read out as one sentence rather than as an
/// orphaned icon plus text.
class _HandOverNote extends StatelessWidget {
  const _HandOverNote();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AssessmentLabels.handDeviceToChild,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.phone_iphone_rounded,
            size: 16,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AssessmentLabels.handDeviceToChild,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
