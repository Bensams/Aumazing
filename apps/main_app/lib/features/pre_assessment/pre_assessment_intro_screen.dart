import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../providers/child_provider.dart';
import '../../services/research_consent_service.dart';
import '../../widgets/mascot.dart';
import 'pre_assessment_progress_screen.dart';
import 'research_consent_dialog.dart';
import 'sensory/sensory.dart';

/// Welcome screen for the pre-assessment flow.
///
/// Two columns side by side when there is width for them (tablets, landscape),
/// stacked and scrollable on a portrait phone.
/// If sensory preferences have already been set, the "Set up preferences"
/// step is shown as completed and tapping "Let's Start!" skips directly
/// to the assessment games.
class PreAssessmentIntroScreen extends StatelessWidget {
  const PreAssessmentIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefsAlreadySet =
        context.watch<ChildProvider>().sensoryPreferencesSet;

    return ParentAdaptiveOrientation(
      child: Scaffold(
        body: Container(
          // Fills the screen: without this the box shrink-wraps the scroll
          // view's content and the gradient stops short of the bottom.
          constraints: const BoxConstraints.expand(),
          decoration: const BoxDecoration(
            gradient: AppGradients.parentLavenderMint,
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= constraints.maxHeight;

                if (!isWide) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: ConstrainedBox(
                      // Centre the content when it is shorter than the
                      // screen, rather than leaving it hanging at the top.
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - AppSpacing.md * 2,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildWelcome(),
                          const SizedBox(height: 24),
                          _buildSteps(context, prefsAlreadySet),
                        ],
                      ),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Center(child: _buildWelcome())),
                      const SizedBox(width: 32),
                      Expanded(
                        child: Center(
                          child: _buildSteps(context, prefsAlreadySet),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Mascot, greeting and the "this is not a diagnosis" note.
  static Widget _buildWelcome() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // BPS greets the child with a wave, then breathes.
        const Mascot(
          height: 110,
          fallback: Text('🌟', style: TextStyle(fontSize: 52)),
          semanticLabel: 'BPS the mascot says hello',
        ),
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
              const Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AppColors.mutedForeground,
              ),
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
    );
  }

  /// The step checklist and the button that starts the run.
  static Widget _buildSteps(BuildContext context, bool prefsAlreadySet) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
              final acknowledged = await _DisclaimerDialog.show(context);
              if (!acknowledged || !context.mounted) return;

              // Beta research consent — asked once per child
              // (and again if the consent text version
              // changes). Optional either way: declining
              // never blocks the assessment.
              final childId = context.read<ChildProvider>().profile?.id;
              if (childId != null) {
                final status = await ResearchConsentService.instance.statusFor(
                  childId,
                );
                if (!context.mounted) return;
                if (!status.answered) {
                  await ResearchConsentDialog.show(context, childId: childId);
                  if (!context.mounted) return;
                }
              }

              // Show sensory consent dialog before starting
              final consent = await SensoryConsentDialog.show(context);
              if (!context.mounted) return;

              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder:
                      (_) => PreAssessmentProgressScreen(
                        sensoryConsentResult: consent,
                      ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static Widget _stepRow(IconData icon, String text, {bool completed = false}) {
    return Row(
      children: [
        Icon(
          icon,
          color: completed ? AppColors.mint : AppColors.lavender,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodyMedium.copyWith(
              color: completed ? AppColors.mint : null,
            ),
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
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.privacy_tip_rounded,
                  color: AppColors.primaryPurple,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Before you begin',
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
                'This assessment is a gamified educational screening aid. It '
                'does NOT diagnose Autism Spectrum Disorder or any medical, '
                'psychological, or developmental condition, and it does not '
                'replace licensed therapists, developmental pediatricians, '
                'psychologists, or SPED teachers.\n\n'
                'Results only guide the learning activities inside this app. '
                'For any concerns about your child\'s development, please '
                'consult a qualified professional.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.mutedForeground,
                ),
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
