import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/area_level.dart';

/// Parent-facing post-assessment results: overall improvement plus a
/// per-area comparison of the AI levels before and after the learning
/// modules. A fresh learning path (from the new levels) is ready when
/// the parent continues.
class PostAssessmentResultScreen extends StatelessWidget {
  const PostAssessmentResultScreen({
    super.key,
    required this.improvement,
    required this.preAreaLevels,
    required this.postAreaLevels,
  });

  /// Output of AssessmentService.compareAssessments.
  final Map<String, dynamic> improvement;

  /// Area levels from the pre-assessment (the baseline).
  final Map<String, AreaLevel> preAreaLevels;

  /// Area levels from the post-assessment (the new prediction).
  final Map<String, AreaLevel> postAreaLevels;

  static const _areaTitles = {
    'communication': 'Communication',
    'social': 'Social Interaction',
    'play': 'Play Skills',
    'attention': 'Attention & Focus',
  };

  bool get _hasData => improvement['has_data'] == true;

  double get _accuracyDelta =>
      (improvement['accuracy_improvement'] as num?)?.toDouble() ?? 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('🎓', style: const TextStyle(fontSize: 48), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Post-Assessment Complete!',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headlineLarge.copyWith(
                        color: AppColors.primaryPurple,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (_hasData) _buildOverallCard(),
                    const SizedBox(height: AppSpacing.md),
                    if (postAreaLevels.isNotEmpty) _buildAreaComparisonCard(),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Row(
                        children: [
                          const Icon(Icons.route_rounded,
                              color: AppColors.primaryPurple),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'A new learning path has been prepared from '
                              'these results.',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppPrimaryButton(
                      label: 'Continue',
                      icon: Icons.check_rounded,
                      onPressed: () => Navigator.of(context)
                          .popUntil((route) => route.isFirst),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverallCard() {
    final accuracyPct = (_accuracyDelta * 100).round();
    final improved = accuracyPct > 0;
    final same = accuracyPct == 0;
    final timeDelta =
        (improvement['response_time_improvement'] as num?)?.toDouble() ?? 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overall Progress',
              style: AppTextStyles.titleMedium
                  .copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                improved
                    ? Icons.trending_up_rounded
                    : same
                        ? Icons.trending_flat_rounded
                        : Icons.trending_down_rounded,
                color: improved || same
                    ? AppColors.statusSuccessDark
                    : AppColors.mutedForeground,
                size: 32,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  improved
                      ? 'Accuracy improved by $accuracyPct percentage points '
                          'since the pre-assessment.'
                      : same
                          ? 'Accuracy held steady since the pre-assessment.'
                          : 'Accuracy changed by $accuracyPct percentage '
                              'points — every child progresses at their own '
                              'pace.',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          if (timeDelta.abs() >= 100) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              timeDelta > 0
                  ? 'Responses are ${(timeDelta / 1000).toStringAsFixed(1)}s '
                      'faster on average.'
                  : 'Responses take a little longer — often a sign of more '
                      'careful choices.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAreaComparisonCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Skill Areas: Before → After',
              style: AppTextStyles.titleMedium
                  .copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          for (final area in _areaTitles.keys)
            if (postAreaLevels.containsKey(area))
              _AreaRow(
                title: _areaTitles[area]!,
                pre: preAreaLevels[area],
                post: postAreaLevels[area]!,
              ),
        ],
      ),
    );
  }
}

class _AreaRow extends StatelessWidget {
  const _AreaRow({required this.title, required this.pre, required this.post});

  final String title;
  final AreaLevel? pre;
  final AreaLevel post;

  @override
  Widget build(BuildContext context) {
    final preInt = pre?.levelInt;
    final delta = preInt == null ? 0 : post.levelInt - preInt;
    final (icon, color) = delta > 0
        ? (Icons.arrow_upward_rounded, AppColors.statusSuccessDark)
        : delta < 0
            ? (Icons.arrow_downward_rounded, AppColors.mutedForeground)
            : (Icons.arrow_forward_rounded, AppColors.primaryPurple);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(title,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimary)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              pre?.levelName ?? '—',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.mutedForeground),
            ),
          ),
          Icon(icon, size: 18, color: color),
          Expanded(
            flex: 2,
            child: Text(
              post.levelName,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
