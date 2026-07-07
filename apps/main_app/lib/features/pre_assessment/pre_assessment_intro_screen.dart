import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../providers/child_provider.dart';
import '../../services/research_consent_service.dart';
import 'pre_assessment_progress_screen.dart';
import 'research_consent_dialog.dart';
import 'sensory/sensory.dart';

/// Welcome screen for the pre-assessment flow.
///
/// Uses a landscape-friendly two-column layout.
/// If sensory preferences have already been set, the "Set up preferences"
/// step is shown as completed and tapping "Let's Start!" skips directly
/// to the assessment games.
class PreAssessmentIntroScreen extends StatelessWidget {
  const PreAssessmentIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefsAlreadySet = context.watch<ChildProvider>().sensoryPreferencesSet;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            child: Row(
              children: [
                // ── Left column: welcome text ──
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🌟', style: TextStyle(fontSize: 52)),
                      const SizedBox(height: 8),
                      Text(
                        'Let\'s Get to Know You!',
                        style: AppTextStyles.headlineLarge.copyWith(
                          color: AppColors.primaryPurple,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We\'ll play a few short games together.\n'
                        'There are no wrong answers — just have fun!',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This will take about 5–10 minutes.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Disclaimer note (System Limitations FR: the app
                      // does not diagnose and does not replace clinicians).
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.white.withAlpha(150),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 16, color: AppColors.mutedForeground),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'This activity is an educational screening '
                                'aid — not a medical diagnosis, and not a '
                                'substitute for licensed therapists, '
                                'developmental pediatricians, or SPED '
                                'professionals.',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.mutedForeground,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 32),

                // ── Right column: steps + button ──
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.white.withAlpha(180),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _stepRow(
                              prefsAlreadySet
                                  ? Icons.check_circle_rounded
                                  : Icons.settings_rounded,
                              'Set up preferences',
                              completed: prefsAlreadySet,
                            ),
                            const SizedBox(height: 6),
                            _stepRow(Icons.content_copy_rounded, 'Copy Me'),
                            const SizedBox(height: 6),
                            _stepRow(Icons.record_voice_over_rounded, 'Do What I Say'),
                            const SizedBox(height: 6),
                            _stepRow(Icons.people_rounded, 'My Turn, Your Turn'),
                            const SizedBox(height: 6),
                            _stepRow(Icons.extension_rounded, 'Match It'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: 220,
                        child: AppPrimaryButton(
                          label: 'Let\'s Start!',
                          icon: Icons.play_arrow_rounded,
                          onPressed: () async {
                            // Parent must acknowledge the disclaimer before
                            // any assessment runs (backlog: disclaimer +
                            // parent consent note).
                            final acknowledged =
                                await _DisclaimerDialog.show(context);
                            if (!acknowledged || !context.mounted) return;

                            // Beta research consent — asked once per child
                            // (and again if the consent text version
                            // changes). Optional either way: declining
                            // never blocks the assessment.
                            final childId =
                                context.read<ChildProvider>().profile?.id;
                            if (childId != null) {
                              final status = await ResearchConsentService
                                  .instance
                                  .statusFor(childId);
                              if (!context.mounted) return;
                              if (!status.answered) {
                                await ResearchConsentDialog.show(context,
                                    childId: childId);
                                if (!context.mounted) return;
                              }
                            }

                            // Show sensory consent dialog before starting
                            final consent =
                                await SensoryConsentDialog.show(context);
                            if (!context.mounted) return;

                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => PreAssessmentProgressScreen(
                                  sensoryConsentResult: consent,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _stepRow(IconData icon, String text,
      {bool completed = false}) {
    return Row(
      children: [
        Icon(
          icon,
          color: completed ? AppColors.mint : AppColors.lavender,
          size: 18,
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: AppTextStyles.bodyMedium.copyWith(
            color: completed ? AppColors.mint : null,
          ),
        ),
        if (completed) ...[
          const SizedBox(width: 6),
          Text(
            '(saved)',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }
}

/// Parent acknowledgment shown before every assessment run: the app is an
/// educational screening aid, never a diagnosis (System Limitations FRs).
class _DisclaimerDialog {
  _DisclaimerDialog._();

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.privacy_tip_rounded,
                color: AppColors.primaryPurple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Before you begin',
                style: AppTextStyles.titleLarge
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            'This assessment is a gamified educational screening aid. It '
            'does NOT diagnose Autism Spectrum Disorder or any medical, '
            'psychological, or developmental condition, and it does not '
            'replace licensed therapists, developmental pediatricians, '
            'psychologists, or SPED teachers.\n\n'
            'Results only guide the learning activities inside this app. '
            'For any concerns about your child\'s development, please '
            'consult a qualified professional.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.mutedForeground),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
