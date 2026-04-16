import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import 'sensory_preferences_screen.dart';

/// Welcome screen for the pre-assessment flow.
///
/// Uses a landscape-friendly two-column layout.
class PreAssessmentIntroScreen extends StatelessWidget {
  const PreAssessmentIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                            _stepRow(Icons.settings_rounded, 'Set up preferences'),
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
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const SensoryPreferencesScreen(),
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

  Widget _stepRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppColors.lavender, size: 18),
        const SizedBox(width: 10),
        Text(text, style: AppTextStyles.bodyMedium),
      ],
    );
  }
}
