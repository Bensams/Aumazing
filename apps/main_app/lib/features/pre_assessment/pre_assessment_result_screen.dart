import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';

/// Displays the pre-assessment results with a developmental profile
/// and recommended settings.
class PreAssessmentResultScreen extends StatefulWidget {
  const PreAssessmentResultScreen({
    super.key,
    required this.profile,
    required this.results,
  });

  final SupportProfile profile;
  final List<AssessmentResult> results;

  @override
  State<PreAssessmentResultScreen> createState() =>
      _PreAssessmentResultScreenState();
}

class _PreAssessmentResultScreenState extends State<PreAssessmentResultScreen> {
  bool _showCelebration = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) setState(() => _showCelebration = false);
    });
  }

  SupportProfile get profile => widget.profile;
  List<AssessmentResult> get results => widget.results;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration:
                const BoxDecoration(gradient: AppGradients.parentLavenderMint),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  child: Column(
                    children: [
                      const Text('🎉', style: TextStyle(fontSize: 56)),
                      const SizedBox(height: 8),

                      Text(
                        'Assessment Complete!',
                        style: AppTextStyles.headlineLarge.copyWith(
                          color: AppColors.primaryPurple,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Here\'s what we observed during the games.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      _buildProfileCard(),
                      const SizedBox(height: 16),
                      _buildRecommendationsCard(),
                      const SizedBox(height: 16),
                      _buildGameScoresCard(),
                      const SizedBox(height: 24),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.butterLight.withAlpha(120),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '⚠️ This is not a clinical diagnosis. These observations '
                          'are meant to help customize the learning experience.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.mutedForeground,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: 260,
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
            '${profile.recommendedSessionMinutes} minutes'),
        _recRow(Icons.repeat_rounded, 'Prompt Repetition',
            '${profile.promptRepetition}x'),
        if (profile.lowStimulationMode)
          _recRow(Icons.visibility_off_rounded, 'Mode',
              'Low-stimulation recommended'),
        if (profile.turnTakingPractice)
          _recRow(Icons.people_rounded, 'Practice',
              'Extra turn-taking recommended'),
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
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _gameName(r.gameId),
                  style: AppTextStyles.bodyMedium,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _scoreColor(r.accuracy).withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$pct%',
                  style: AppTextStyles.titleMedium.copyWith(
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

  Widget _card({
    required String title,
    required String emoji,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(200),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.titleLarge),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _profileRow(String area, String level) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(area, style: AppTextStyles.bodyMedium),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: _levelColor(level).withAlpha(40),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              level,
              style: AppTextStyles.bodySmall.copyWith(
                color: _levelColor(level),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.lavender),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: AppTextStyles.bodySmall),
          ),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
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
}
