import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/scoring_service.dart';
import 'pre_assessment_intro_screen.dart';

/// Assessment Dashboard — shown when the user taps "Assessment" on the
/// home screen after completing the pre-assessment.
///
/// Displays a compact, landscape-friendly summary of the pre-assessment
/// results without requiring scrolling. Includes a "Retake Assessment"
/// option.
class AssessmentDashboardScreen extends StatelessWidget {
  const AssessmentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AssessmentProvider, ChildProvider>(
      builder: (context, assessProv, childProv, _) {
        final results = assessProv.preResults;

        if (results.isEmpty) {
          // Shouldn't happen, but fallback
          return const Scaffold(
            body: Center(child: Text('No assessment data found.')),
          );
        }

        final scorer = const ScoringService();
        final sensorySettings = childProv.sensorySettingsMap;
        final profile = scorer.generateProfile(
          results: results,
          sensorySettings: sensorySettings,
        );

        return _DashboardBody(
          results: results,
          profile: profile,
          onRetake: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => const PreAssessmentIntroScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.results,
    required this.profile,
    required this.onRetake,
  });

  final List<AssessmentResult> results;
  final SupportProfile profile;
  final VoidCallback onRetake;

  int get _totalCorrect => results.fold(0, (sum, r) => sum + r.score);
  int get _totalItems => results.fold(0, (sum, r) => sum + r.totalItems);
  int get _totalErrors => results.fold(0, (sum, r) => sum + r.errorCount);
  int get _overallPct =>
      _totalItems > 0 ? ((_totalCorrect / _totalItems) * 100).round() : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: [
                // ── Top bar ──────────────────────────────────────
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppColors.primaryPurple,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    const Text('📊', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 6),
                    Text(
                      'Assessment Summary',
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.primaryPurple,
                      ),
                    ),
                    const Spacer(),
                    _OverallBadge(pct: _overallPct),
                  ],
                ),
                const SizedBox(height: 6),

                // ── Main content: three columns ──────────────────
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left: Game scores
                      Expanded(
                        flex: 3,
                        child: _buildGameScoresCard(),
                      ),
                      const SizedBox(width: 10),
                      // Center: Profile
                      Expanded(
                        flex: 3,
                        child: _buildProfileCard(),
                      ),
                      const SizedBox(width: 10),
                      // Right: Recommendations + Actions
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            Expanded(child: _buildRecommendationsCard()),
                            const SizedBox(height: 8),
                            _buildActionButtons(context),
                          ],
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

  Widget _buildGameScoresCard() {
    return _Card(
      title: 'Game Results',
      emoji: '🎮',
      children: [
        // Summary stats row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _MiniStat('✅', '$_totalCorrect', AppColors.mint),
            _MiniStat('❌', '$_totalErrors', AppColors.peach),
            _MiniStat(
              '📝',
              '$_totalItems',
              AppColors.lavender,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 6),
        // Per-game rows
        ...results.map((r) => _GameRow(result: r)),
      ],
    );
  }

  Widget _buildProfileCard() {
    return _Card(
      title: 'Developmental Profile',
      emoji: '📋',
      children: [
        _ProfileRow('Communication', profile.communication),
        _ProfileRow('Social Interaction', profile.socialInteraction),
        _ProfileRow('Play Skills', profile.playSkills),
        _ProfileRow('Attention', profile.attention),
        if (profile.sensoryNotes.isNotEmpty)
          _ProfileRow('Sensory', profile.sensoryNotes.join(', ')),
      ],
    );
  }

  Widget _buildRecommendationsCard() {
    return _Card(
      title: 'Recommendations',
      emoji: '💡',
      children: [
        _RecRow(Icons.speed_rounded, 'Difficulty',
            profile.recommendedDifficulty),
        _RecRow(Icons.record_voice_over_rounded, 'Prompts',
            profile.recommendedPromptStyle),
        _RecRow(Icons.timer_rounded, 'Session',
            '${profile.recommendedSessionMinutes} min'),
        _RecRow(Icons.repeat_rounded, 'Repetition',
            '${profile.promptRepetition}x'),
        if (profile.lowStimulationMode)
          _RecRow(Icons.visibility_off_rounded, 'Mode', 'Low-stim'),
        if (profile.turnTakingPractice)
          _RecRow(Icons.people_rounded, 'Practice', 'Turn-taking'),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: OutlinedButton.icon(
              onPressed: onRetake,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                'Retake',
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryPurple,
                side: const BorderSide(color: AppColors.lavender),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.home_rounded, size: 16),
              label: Text(
                'Home',
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Reusable sub-widgets ──────────────────────────────────────────────

class _OverallBadge extends StatelessWidget {
  const _OverallBadge({required this.pct});
  final int pct;

  Color get _color {
    if (pct >= 80) return AppColors.mint;
    if (pct >= 50) return AppColors.butterYellow;
    return AppColors.peach;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withAlpha(40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$pct%',
            style: AppTextStyles.titleMedium.copyWith(color: _color),
          ),
          const SizedBox(width: 4),
          Text(
            'Overall',
            style: AppTextStyles.bodySmall.copyWith(
              color: _color,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.emoji, this.value, this.color);
  final String emoji;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.labelLarge.copyWith(color: color),
        ),
      ],
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.result});
  final AssessmentResult result;

  String get _name {
    switch (result.gameId) {
      case 'copy_me':
        return '🪞 Copy Me';
      case 'do_what_i_say':
        return '🗣️ Do What I Say';
      case 'my_turn_your_turn':
        return '🔄 My Turn, Your Turn';
      case 'match_it':
        return '🧩 Match It';
      default:
        return '🎮 ${result.gameId}';
    }
  }

  Color get _color {
    if (result.accuracy >= 0.8) return AppColors.mint;
    if (result.accuracy >= 0.5) return AppColors.butterYellow;
    return AppColors.peach;
  }

  @override
  Widget build(BuildContext context) {
    final pct = (result.accuracy * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _name,
              style: AppTextStyles.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${result.score}/${result.totalItems}',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: _color.withAlpha(40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$pct%',
              style: AppTextStyles.bodySmall.copyWith(
                color: _color,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow(this.area, this.level);
  final String area;
  final String level;

  Color get _color {
    switch (level) {
      case 'strong':
      case 'good':
      case 'sustained':
        return AppColors.mint;
      case 'developing':
      case 'improving':
      case 'moderate':
        return AppColors.butterYellow;
      default:
        return AppColors.peach;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(area, style: AppTextStyles.bodySmall),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _color.withAlpha(40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              level,
              style: AppTextStyles.bodySmall.copyWith(
                color: _color,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecRow extends StatelessWidget {
  const _RecRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.lavender),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.emoji,
    required this.children,
  });

  final String title;
  final String emoji;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                title,
                style: AppTextStyles.titleMedium.copyWith(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}
