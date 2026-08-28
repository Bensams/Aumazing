import 'package:flutter/material.dart';

import '../app_primary_button.dart';
import '../app_secondary_button.dart';
import '../assessment_result_data.dart';

/// The purpose-specific actions for each presentation.
///
/// Completion mode offers a single primary "Continue to Home" — retaking is
/// deliberately absent right after the child has finished. Review mode adds
/// "Retake Assessment" beside the way back.
class AssessmentResultActions extends StatelessWidget {
  const AssessmentResultActions({
    super.key,
    required this.presentation,
    this.onContinue,
    this.onRetake,
    this.onBack,
    this.backLabel = AssessmentLabels.backToDashboard,
  });

  final AssessmentResultPresentation presentation;

  /// Completion mode: "Continue to Home".
  final VoidCallback? onContinue;

  /// Review mode: "Retake Assessment".
  final VoidCallback? onRetake;

  /// Review mode: back to the dashboard / home.
  final VoidCallback? onBack;

  final String backLabel;

  @override
  Widget build(BuildContext context) {
    if (presentation == AssessmentResultPresentation.completion) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AppPrimaryButton(
            label: AssessmentLabels.continueToHome,
            icon: Icons.arrow_forward_rounded,
            onPressed: onContinue,
          ),
        ),
      );
    }

    final retake = AppSecondaryButton(
      label: AssessmentLabels.retakeAssessment,
      icon: Icons.refresh_rounded,
      onPressed: onRetake,
    );
    final back = AppPrimaryButton(
      label: backLabel,
      icon: Icons.home_rounded,
      onPressed: onBack,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Side by side only when both labels comfortably fit; otherwise
        // stack so neither action is truncated at large text scales.
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final fits = constraints.maxWidth >= 420 * scale;
        if (!fits) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              retake,
              const SizedBox(height: 10),
              back,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: retake),
            const SizedBox(width: 12),
            Expanded(child: back),
          ],
        );
      },
    );
  }
}
