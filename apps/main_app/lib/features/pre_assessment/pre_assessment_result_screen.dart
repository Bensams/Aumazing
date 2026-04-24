import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';

/// Displays the pre-assessment results with a developmental profile
/// and recommended settings.
///
/// Designed to fit on a single screen without scrolling, using a
/// landscape-friendly two-column layout. When AI data is available,
/// an AI Insights section is shown prominently.
class PreAssessmentResultScreen extends StatefulWidget {
  const PreAssessmentResultScreen({
    super.key,
    required this.profile,
    required this.results,
    this.aiResponse,
  });

  final SupportProfile profile;
  final List<AssessmentResult> results;

  /// AI prediction data, or null if AI was unavailable (rule-based fallback).
  final AiAssessmentResponse? aiResponse;

  @override
  State<PreAssessmentResultScreen> createState() =>
      _PreAssessmentResultScreenState();
}

class _PreAssessmentResultScreenState extends State<PreAssessmentResultScreen> {
  bool _showCelebration = true;

  @override
  void initState() {
    super.initState();
    debugPrint('[PreAssessmentResult] AI data received: '
        '${widget.aiResponse != null ? widget.aiResponse.toString() : "null (rule-based)"}');
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) setState(() => _showCelebration = false);
    });
  }

  SupportProfile get profile => widget.profile;
  List<AssessmentResult> get results => widget.results;
  AiAssessmentResponse? get aiResponse => widget.aiResponse;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration:
                const BoxDecoration(gradient: AppGradients.parentLavenderMint),
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  children: [
                    // ── Header row ──────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🎉', style: TextStyle(fontSize: 28)),
                        const SizedBox(width: 8),
                        Text(
                          'Assessment Complete!',
                          style: AppTextStyles.headlineMedium.copyWith(
                            color: AppColors.primaryPurple,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildSourceBadge(),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Here\'s what we observed during the games.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Main content: two columns ──────────────────
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left column: AI Insights (or Profile) + Game Scores
                          Expanded(
                            child: Column(
                              children: [
                                if (aiResponse != null) ...[
                                  Expanded(
                                    flex: 4,
                                    child: _buildAiInsightsCard(),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    flex: 2,
                                    child: _buildGameScoresCard(),
                                  ),
                                ] else ...[
                                  Expanded(
                                    flex: 3,
                                    child: _buildProfileCard(),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    flex: 2,
                                    child: _buildGameScoresCard(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Right column: Profile (when AI) or Recommendations + Disclaimer + Button
                          Expanded(
                            child: Column(
                              children: [
                                if (aiResponse != null) ...[
                                  Expanded(
                                    flex: 2,
                                    child: _buildProfileCard(),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    flex: 3,
                                    child: _buildRecommendationsCard(),
                                  ),
                                ] else ...[
                                  Expanded(
                                    flex: 3,
                                    child: _buildRecommendationsCard(),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                _buildDisclaimer(),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: double.infinity,
                                  child: AppPrimaryButton(
                                    label: 'Continue to Home',
                                    icon: Icons.home_rounded,
                                    onPressed: () {
                                      Navigator.of(context)
                                          .popUntil((route) => route.isFirst);
                                    },
                                  ),
                                ),
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
          if (_showCelebration)
            const GameCelebrationOverlay(
              emoji: '🏆',
              message: 'You Did It!',
              subMessage: 'Amazing job finishing all the games!',
              isBigCelebration: true,
            ),
        ],
      ),
    );
  }

  /// Badge showing whether results are AI-powered or rule-based.
  Widget _buildSourceBadge() {
    final isAi = aiResponse != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isAi
            ? AppColors.mint.withAlpha(40)
            : AppColors.butterYellow.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAi
              ? AppColors.mint.withAlpha(100)
              : AppColors.butterYellow.withAlpha(100),
        ),
      ),
      child: Text(
        isAi ? '🤖 AI-Powered' : '📊 Rule-Based',
        style: AppTextStyles.bodySmall.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isAi ? AppColors.mint : AppColors.butterYellow,
        ),
      ),
    );
  }

  /// AI Insights card — shown when AI prediction data is available.
  Widget _buildAiInsightsCard() {
    final ai = aiResponse!;
    return _card(
      title: 'AI Insights',
      emoji: '🤖',
      children: [
        // AI Profile
        _aiRow(
          Icons.psychology_rounded,
          'AI Profile',
          ai.profileDisplayName,
        ),
        const SizedBox(height: 4),

        // Confidence with visual bar
        _buildConfidenceRow(ai.confidence),
        const SizedBox(height: 4),

        // Support Level
        _aiRow(
          Icons.support_rounded,
          'Support Level',
          _supportLevelDisplay(ai.supportLevel),
        ),
        const SizedBox(height: 6),

        // Summary text
        if (ai.summary.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.lavenderLight.withAlpha(60),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              ai.summary,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 11,
                color: AppColors.foreground,
                height: 1.3,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 6),
        ],

        // Recommended Activities
        if (ai.moduleDetails.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 13, color: AppColors.lavender),
              const SizedBox(width: 4),
              Text(
                'Recommended Activities',
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...ai.moduleDetails.map((mod) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    const SizedBox(width: 17),
                    Icon(Icons.play_circle_outline_rounded,
                        size: 12, color: AppColors.mint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        mod.name,
                        style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.lavenderLight.withAlpha(80),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Level ${mod.startingLevel}',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryPurple,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ] else if (ai.recommendedModules.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 13, color: AppColors.lavender),
              const SizedBox(width: 4),
              Text(
                'Recommended Activities',
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...ai.recommendedModules.map((name) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    const SizedBox(width: 17),
                    Icon(Icons.play_circle_outline_rounded,
                        size: 12, color: AppColors.mint),
                    const SizedBox(width: 4),
                    Text(
                      name,
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              )),
        ],
      ],
    );
  }

  /// Confidence row with a visual progress bar.
  Widget _buildConfidenceRow(double confidence) {
    final pct = (confidence * 100).round();
    final color = confidence >= 0.8
        ? AppColors.mint
        : confidence >= 0.6
            ? AppColors.butterYellow
            : AppColors.peach;

    return Row(
      children: [
        Icon(Icons.verified_rounded, size: 14, color: AppColors.lavender),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Confidence',
            style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
          ),
        ),
        SizedBox(
          width: 60,
          height: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: confidence,
              backgroundColor: AppColors.border.withAlpha(60),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$pct%',
          style: AppTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _aiRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
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

  String _supportLevelDisplay(String level) {
    switch (level) {
      case 'high':
        return 'High Support';
      case 'moderate':
        return 'Moderate Support';
      case 'low':
        return 'Low Support';
      default:
        return level;
    }
  }

  Widget _buildProfileCard() {
    return _card(
      title: 'Developmental Profile',
      emoji: '📊',
      children: [
        _profileRow('Communication', profile.communication),
        _profileRow('Social Interaction', profile.socialInteraction),
        _profileRow('Play Skills', profile.playSkills),
        _profileRow('Attention', profile.attention),
        if (profile.sensoryNotes.isNotEmpty)
          _profileRow('Sensory', profile.sensoryNotes.join(', ')),
      ],
    );
  }

  Widget _buildRecommendationsCard() {
    return _card(
      title: 'Recommendations',
      emoji: '💡',
      children: [
        _recRow(Icons.speed_rounded, 'Difficulty',
            profile.recommendedDifficulty),
        _recRow(Icons.record_voice_over_rounded, 'Prompt Style',
            profile.recommendedPromptStyle),
        _recRow(Icons.timer_rounded, 'Session Length',
            '${profile.recommendedSessionMinutes} min'),
        _recRow(Icons.repeat_rounded, 'Prompt Repetition',
            '${profile.promptRepetition}x'),
        if (profile.lowStimulationMode)
          _recRow(Icons.visibility_off_rounded, 'Mode',
              'Low-stimulation'),
        if (profile.turnTakingPractice)
          _recRow(Icons.people_rounded, 'Practice',
              'Extra turn-taking'),
      ],
    );
  }

  Widget _buildGameScoresCard() {
    return _card(
      title: 'Game Scores',
      emoji: '🎮',
      children: results.map((r) {
        final pct = (r.accuracy * 100).round();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Text(
                _gameEmoji(r.gameId),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _gameName(r.gameId),
                  style: AppTextStyles.bodySmall,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _scoreColor(r.accuracy).withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$pct%',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: _scoreColor(r.accuracy),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDisclaimer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.butterLight.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '⚠️ Not a clinical diagnosis. Observations help customize learning.',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.mutedForeground,
          fontSize: 10,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _card({
    required String title,
    required String emoji,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                title,
                style: AppTextStyles.titleMedium.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _profileRow(String area, String level) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(area, style: AppTextStyles.bodySmall),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _levelColor(level).withAlpha(40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              level,
              style: AppTextStyles.bodySmall.copyWith(
                color: _levelColor(level),
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recRow(IconData icon, String label, String value) {
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

  Color _levelColor(String level) {
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

  Color _scoreColor(double accuracy) {
    if (accuracy >= 0.8) return AppColors.mint;
    if (accuracy >= 0.5) return AppColors.butterYellow;
    return AppColors.peach;
  }

  String _gameName(String gameId) {
    switch (gameId) {
      case 'copy_me':
        return 'Copy Me';
      case 'do_what_i_say':
        return 'Do What I Say';
      case 'my_turn_your_turn':
        return 'My Turn, Your Turn';
      case 'match_it':
        return 'Match It';
      default:
        return gameId;
    }
  }

  String _gameEmoji(String gameId) {
    switch (gameId) {
      case 'copy_me':
        return '🪞';
      case 'do_what_i_say':
        return '🗣️';
      case 'my_turn_your_turn':
        return '🔄';
      case 'match_it':
        return '🧩';
      default:
        return '🎮';
    }
  }
}
