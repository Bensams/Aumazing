import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../providers/assessment_provider.dart';
import '../../../services/rubric/rubric_labels.dart';
import '../../../services/rubric/rubric_result.dart';

/// Parent-facing screen that displays rubric scoring results after a child
/// completes the pre-assessment games.
///
/// Reads [RubricResult] from [AssessmentProvider.rubricResult] and presents
/// five assessment area cards, a recommended module highlight, a disclaimer,
/// and a "Continue" button.
class PreAssessmentResultsScreen extends StatelessWidget {
  const PreAssessmentResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssessmentProvider>();
    final rubric = provider.rubricResult;

    return Scaffold(
      body: AppGradientBackground(
        gradient: AppGradients.parentLavenderMint,
        child: SafeArea(
          child: Column(
            children: [
              ParentModeTopBar(
                title: 'Assessment Results',
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: rubric == null
                    ? _buildNoResults()
                    : _buildResults(context, rubric),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── No results / loading state ──────────────────────────────────────

  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: AppSpacing.paddingLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📋', style: TextStyle(fontSize: 48)),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No assessment results yet.',
              style: AppTextStyles.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Complete the pre-assessment games to see your child\'s results here.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Main results content ────────────────────────────────────────────

  Widget _buildResults(BuildContext context, RubricResult rubric) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _ResultHeader(),
          const SizedBox(height: AppSpacing.md),

          // 5 Assessment Area Cards
          _AssessmentAreaCard(
            emoji: '🎮',
            areaName: 'Play Skills',
            labelText: rubric.playSkillsLabel.displayName,
            labelColor: _performanceColor(rubric.playSkillsLabel),
          ),
          const SizedBox(height: AppSpacing.xs),
          _AssessmentAreaCard(
            emoji: '💬',
            areaName: 'Communication',
            labelText: rubric.communicationLabel.displayName,
            labelColor: _performanceColor(rubric.communicationLabel),
          ),
          const SizedBox(height: AppSpacing.xs),
          _AssessmentAreaCard(
            emoji: '🤝',
            areaName: 'Social Interaction',
            labelText: rubric.socialInteractionLabel.displayName,
            labelColor: _performanceColor(rubric.socialInteractionLabel),
          ),
          const SizedBox(height: AppSpacing.xs),
          _AssessmentAreaCard(
            emoji: '🧠',
            areaName: 'Behavior & Attention',
            labelText: rubric.behaviorAttentionLabel.displayName,
            labelColor: _attentionColor(rubric.behaviorAttentionLabel),
          ),
          const SizedBox(height: AppSpacing.xs),
          _AssessmentAreaCard(
            emoji: '🎵',
            areaName: 'Sensory Preference',
            labelText: rubric.sensoryPreferenceLabel.displayName,
            labelColor: _sensoryColor(),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Recommended Module Card
          _RecommendedModuleCard(rubric: rubric),
          const SizedBox(height: AppSpacing.md),

          // Parent-friendly explanation
          Text(
            'Based on how your child played the games, we\'ve identified '
            'areas of strength and areas where extra support may help. '
            'The recommended module is tailored to your child\'s needs.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.mutedForeground,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),

          // Disclaimer
          const _DisclaimerText(),
          const SizedBox(height: AppSpacing.lg),

          // Continue button
          AppPrimaryButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  // ── Color helpers ───────────────────────────────────────────────────

  static Color _performanceColor(PerformanceLabel label) {
    switch (label) {
      case PerformanceLabel.strength:
        return AppColors.mint;
      case PerformanceLabel.emerging:
        return AppColors.butterYellow;
      case PerformanceLabel.needsSupport:
        return AppColors.peach;
    }
  }

  static Color _attentionColor(AttentionLabel label) {
    switch (label) {
      case AttentionLabel.sustainedAttention:
        return AppColors.mint;
      case AttentionLabel.variableAttention:
        return AppColors.butterYellow;
      case AttentionLabel.needsAttentionSupport:
        return AppColors.peach;
    }
  }

  static Color _sensoryColor() => AppColors.skyBlue;
}

// ════════════════════════════════════════════════════════════════════════
// Private widgets
// ════════════════════════════════════════════════════════════════════════

/// Title header with emoji and subtitle.
class _ResultHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 28)),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Great Job!',
              style: AppTextStyles.headlineLarge.copyWith(
                color: AppColors.primaryPurple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Here\'s what we observed during the games.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.mutedForeground,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// A compact horizontal card showing one assessment area result.
///
/// Layout: [emoji] [area name] ─── [label chip]
class _AssessmentAreaCard extends StatelessWidget {
  const _AssessmentAreaCard({
    required this.emoji,
    required this.areaName,
    required this.labelText,
    required this.labelColor,
  });

  final String emoji;
  final String areaName;
  final String labelText;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              areaName,
              style: AppTextStyles.titleMedium,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: labelColor.withAlpha(50),
              borderRadius: AppRadius.chip,
              border: Border.all(
                color: labelColor.withAlpha(120),
                width: 1,
              ),
            ),
            child: Text(
              labelText,
              style: AppTextStyles.labelSmall.copyWith(
                color: labelColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Highlighted card showing the recommended module and summary.
class _RecommendedModuleCard extends StatelessWidget {
  const _RecommendedModuleCard({required this.rubric});

  final RubricResult rubric;

  @override
  Widget build(BuildContext context) {
    final summary = rubric.overallSummary.length > 200
        ? '${rubric.overallSummary.substring(0, 200)}…'
        : rubric.overallSummary;

    return AppCard(
      color: AppColors.lavenderLight,
      padding: AppSpacing.paddingLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⭐', style: TextStyle(fontSize: 20)),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Recommended Module',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primaryPurple,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            rubric.recommendedModule,
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.primaryPurple,
            ),
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              summary,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.foreground,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Disclaimer text that must always be visible.
class _DisclaimerText extends StatelessWidget {
  const _DisclaimerText();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.butterLight.withAlpha(150),
        borderRadius: AppRadius.chip,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ℹ️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'This result is based on game performance only and is not a '
              'medical diagnosis. It is used to recommend suitable learning '
              'activities.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.mutedForeground,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
