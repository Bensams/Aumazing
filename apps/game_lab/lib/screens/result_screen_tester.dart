import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Standalone visual test harness for the PreAssessmentResultScreen layout.
///
/// Duplicates the exact layout from main_app's PreAssessmentResultScreen
/// with hardcoded mock data so the UI can be tested in game_lab without
/// needing Supabase, AI API, or main_app model imports.
class ResultScreenTester extends StatefulWidget {
  const ResultScreenTester({super.key});

  @override
  State<ResultScreenTester> createState() => _ResultScreenTesterState();
}

class _ResultScreenTesterState extends State<ResultScreenTester> {
  bool _showCelebration = true;
  bool _showAi = true; // Toggle between AI and rule-based views

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) setState(() => _showCelebration = false);
    });
  }

  // ── Mock data ──────────────────────────────────────────────────────────

  static const _mockAreaLevels = [
    _MockAreaLevel('Communication', 'Emerging', 1, 0.99),
    _MockAreaLevel('Social Interaction', 'Needs Support', 0, 1.00),
    _MockAreaLevel('Play Skills', 'Emerging', 1, 1.00),
    _MockAreaLevel('Attention', 'Strength', 2, 0.98),
  ];

  static const _mockGameScores = [
    _MockGameScore('copy_me', 'Copy Me', '🪞', 0.29),
    _MockGameScore('do_what_i_say', 'Do What I Say', '🗣️', 0.28),
    _MockGameScore('my_turn_your_turn', 'My Turn, Your Turn', '🔄', 0.50),
    _MockGameScore('match_it', 'Match It', '🧩', 0.65),
  ];

  static const _mockModules = [
    _MockModule('Copy Me', 1),
    _MockModule('Do What I Say', 1),
    _MockModule('My Turn, Your Turn', 2),
    _MockModule('Match It', 2),
  ];

  static const _mockConfidence = 0.94;
  static const _mockSummary =
      'Communication and social interaction need support. '
      'Play skills are emerging. Attention is a strength.';

  // ── Profile mock data ──────────────────────────────────────────────────
  static const _profileCommunication = 'Emerging';
  static const _profileSocial = 'Needs Support';
  static const _profilePlay = 'Emerging';
  static const _profileAttention = 'Strong';
  static const _recDifficulty = 'beginner';
  static const _recPromptStyle = 'combined';
  static const _recSessionMinutes = 5;
  static const _recPromptRepetition = 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
                gradient: AppGradients.parentLavenderMint),
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
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildSourceBadge(),
                        const SizedBox(width: 12),
                        // Toggle button for testing
                        SizedBox(
                          height: 28,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _showAi = !_showAi),
                            icon: Icon(
                              _showAi ? Icons.smart_toy : Icons.rule,
                              size: 14,
                            ),
                            label: Text(
                              _showAi ? 'Switch to Rule' : 'Switch to AI',
                              style: const TextStyle(fontSize: 10),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                              side: BorderSide(
                                  color: AppColors.lavender, width: 1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Here\'s what we observed during the games.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Main content: two columns ──────────────────
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left column
                          Expanded(
                            child: Column(
                              children: [
                                if (_showAi) ...[
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
                          // Right column
                          Expanded(
                            child: Column(
                              children: [
                                if (_showAi) ...[
                                  Expanded(
                                    child: _buildProfileCard(),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
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
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
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

  Widget _buildSourceBadge() {
    if (_showAi) {
      return const StatusPillBadge(
        label: 'AI-Powered',
        level: StatusLevel.info,
        icon: Text('🤖'),
      );
    } else {
      return const StatusPillBadge(
        label: 'Rule-Based',
        level: StatusLevel.warning,
        icon: Text('📊'),
      );
    }
  }

  Widget _buildAiInsightsCard() {
    return _card(
      title: 'AI Insights',
      emoji: '🤖',
      children: [
        _buildAreaLevelsSection(),
        const SizedBox(height: 4),
        _buildConfidenceRow(_mockConfidence),
        const SizedBox(height: 2),
        // Summary
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.statusInfoBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _mockSummary,
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 6),
        // Recommended Activities
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
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ..._mockModules.map((mod) => Padding(
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
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  StatusPillBadge(
                    label: 'Level ${mod.startingLevel}',
                    level: StatusLevel.info,
                    compact: true,
                    fontSize: 10,
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildAreaLevelsSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.psychology_rounded,
                size: 14, color: AppColors.lavender),
            const SizedBox(width: 6),
            Text(
              'Per-Area Levels',
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        for (final area in _mockAreaLevels) _buildAreaLevelRow(area),
      ],
    );
  }

  Widget _buildAreaLevelRow(_MockAreaLevel area) {
    final StatusLevel pillLevel;
    switch (area.levelInt) {
      case 0:
        pillLevel = StatusLevel.warning;
        break;
      case 1:
        pillLevel = StatusLevel.info;
        break;
      case 2:
        pillLevel = StatusLevel.success;
        break;
      default:
        pillLevel = StatusLevel.info;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              area.label,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          StatusPillBadge(
            label: area.levelName,
            level: pillLevel,
            compact: true,
            fontSize: 10,
          ),
          const SizedBox(width: 4),
          Text(
            '${(area.confidence * 100).round()}%',
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceRow(double confidence) {
    final pct = (confidence * 100).round();
    final color = confidence >= 0.8
        ? AppColors.statusSuccessDark
        : confidence >= 0.6
            ? AppColors.statusWarningDark
            : AppColors.statusDangerDark;

    return Row(
      children: [
        Icon(Icons.verified_rounded, size: 14, color: AppColors.lavender),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Confidence',
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
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
        StatusPillBadge.fromScore(pct, compact: true),
      ],
    );
  }

  Widget _buildProfileCard() {
    return _card(
      title: 'Developmental Profile',
      emoji: '📊',
      children: [
        _profileRow('Communication', _profileCommunication),
        _profileRow('Social Interaction', _profileSocial),
        _profileRow('Play Skills', _profilePlay),
        _profileRow('Attention', _profileAttention),
      ],
    );
  }

  Widget _buildRecommendationsCard() {
    return _card(
      title: 'Recommendations',
      emoji: '💡',
      children: [
        _recRow(Icons.speed_rounded, 'Difficulty', _recDifficulty),
        _recRow(Icons.record_voice_over_rounded, 'Prompt Style',
            _recPromptStyle),
        _recRow(Icons.timer_rounded, 'Session Length',
            '$_recSessionMinutes min'),
        _recRow(Icons.repeat_rounded, 'Prompt Repetition',
            '${_recPromptRepetition}x'),
        _recRow(Icons.people_rounded, 'Practice', 'Extra turn-taking'),
      ],
    );
  }

  Widget _buildGameScoresCard() {
    return _card(
      title: 'Game Scores',
      emoji: '🎮',
      children: _mockGameScores.map((g) {
        final pct = (g.accuracy * 100).round();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Text(g.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  g.name,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              StatusPillBadge.fromScore(pct, compact: true),
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
        color: AppColors.statusWarningBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '⚠️ Not a clinical diagnosis. Observations help customize learning.',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.statusWarningDark,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.card,
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                title,
                style: AppTextStyles.titleMedium.copyWith(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
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
            child: Text(
              area,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          StatusPillBadge.fromLabel(level, compact: true),
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
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mock data classes ──────────────────────────────────────────────────────

class _MockAreaLevel {
  final String label;
  final String levelName;
  final int levelInt;
  final double confidence;

  const _MockAreaLevel(this.label, this.levelName, this.levelInt, this.confidence);
}

class _MockGameScore {
  final String gameId;
  final String name;
  final String emoji;
  final double accuracy;

  const _MockGameScore(this.gameId, this.name, this.emoji, this.accuracy);
}

class _MockModule {
  final String name;
  final int startingLevel;

  const _MockModule(this.name, this.startingLevel);
}
