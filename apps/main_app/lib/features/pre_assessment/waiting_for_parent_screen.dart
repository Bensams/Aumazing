import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import 'game_summary_dialog.dart';
import 'pre_assessment_result_screen.dart';

/// Screen shown to the child after all pre-assessment games are complete.
///
/// Displays a friendly "waiting" message while the parent reviews the results.
/// The parent must tap a verification button (parent gate) to proceed
/// to the full results screen.
class WaitingForParentScreen extends StatelessWidget {
  const WaitingForParentScreen({
    super.key,
    required this.results,
    required this.profile,
  });

  final List<AssessmentResult> results;
  final SupportProfile profile;

  void _showParentVerification(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const ParentVerificationDialog(),
    ).then((verified) {
      if (verified == true && context.mounted) {
        _showSummaryDialog(context);
      }
    });
  }

  void _showSummaryDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => GameSummaryDialog(
        results: results,
        onContinue: () {
          Navigator.of(dialogContext).pop();
          // Navigate to the full results screen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => PreAssessmentResultScreen(
                profile: profile,
                results: results,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Celebration icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.lavenderLight.withAlpha(150),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('🎉', style: TextStyle(fontSize: 40)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Great Job!',
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: AppColors.primaryPurple,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),

                  Text(
                    'You finished all the games!',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // Waiting message for child
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.white.withAlpha(200),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('⏳', style: TextStyle(fontSize: 28)),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Please give the device to your parent.',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.foreground,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'They will review your results.',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Parent verification button
                  SizedBox(
                    width: 220,
                    child: AppPrimaryButton(
                      label: 'I\'m the Parent',
                      icon: Icons.verified_user_rounded,
                      onPressed: () => _showParentVerification(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Parents: Tap above to view results',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.mutedForeground,
                      fontStyle: FontStyle.italic,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
