import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../services/assessment_completeness.dart';
import '../services/assessment_service.dart';

/// What the supervising adult chose to do with an interrupted run.
enum ResumeAssessmentChoice { resume, startOver }

/// Offers an interrupted assessment back to the supervising adult (AUM-154).
///
/// Shown before the flow starts, because picking a run up and starting a new
/// one are different actions on different runs — once a new run is minted the
/// old one has already been closed.
///
/// The wording follows [AssessmentCompleteness.incompleteMessage]: it names
/// how far the child got and what is left. An assessment that stopped early
/// is an ordinary thing to come back to, not a failure to report, and the
/// parent is never told they did something wrong.
abstract final class ResumeAssessmentDialog {
  /// The parent's decision. Defaults to resuming when the dialog is somehow
  /// dismissed without an answer: keeping the child's play is the choice that
  /// can still be undone, discarding it is not.
  static Future<ResumeAssessmentChoice> show(
    BuildContext context, {
    required OpenAssessmentRun run,
  }) async {
    final choice = await showDialog<ResumeAssessmentChoice>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.play_circle_outline_rounded,
                  color: AppColors.primaryPurple,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pick up where you left off?',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Text(
                progressMessage(run),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.mutedForeground,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    () => Navigator.of(
                      dialogContext,
                    ).pop(ResumeAssessmentChoice.startOver),
                child: const Text(startOverLabel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                ),
                onPressed:
                    () => Navigator.of(
                      dialogContext,
                    ).pop(ResumeAssessmentChoice.resume),
                child: const Text(continueLabel),
              ),
            ],
          ),
    );
    return choice ?? ResumeAssessmentChoice.resume;
  }

  static const continueLabel = 'Continue';
  static const startOverLabel = 'Start over';

  /// Tells the parent how far the child got and what continuing means.
  static String progressMessage(OpenAssessmentRun run) {
    final done = AssessmentCompleteness.playedCount(run.sessions);
    final total = AssessmentCompleteness.requiredGameIds.length;
    final left = AssessmentCompleteness.missingGames(run.sessions).length;
    final activities = left == 1 ? 'activity' : 'activities';
    return 'This assessment covered $done of $total activities last time. '
        'You can continue with the $left $activities that are left, or '
        'start again from the first activity.';
  }
}
