import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import 'app_primary_button.dart';
import 'assessment_result_data.dart';
import 'game_celebration_overlay.dart';
import 'status_pill_badge.dart';

/// Shared layout widget for the pre-assessment result screen.
///
/// Used by both `main_app` (with live data) and `game_lab` (with mock data).
/// All data is passed in via plain data classes from [assessment_result_data.dart].
class AssessmentResultLayout extends StatefulWidget {
  const AssessmentResultLayout({
    super.key,
    required this.profileRows,
    required this.recommendations,
    required this.gameScores,
    required this.onContinue,
    this.aiData,
    this.showCelebration = true,
    this.celebrationDuration = const Duration(milliseconds: 3000),
  });

  /// Rows for the Developmental Profile card.
  final List<ResultProfileRow> profileRows;

  /// Rows for the Recommendations card.
  final List<ResultRecommendation> recommendations;

  /// Game score entries for the Game Scores card.
  final List<ResultGameScore> gameScores;

  /// Called when the user taps "Continue to Home".
  final VoidCallback onContinue;

  /// AI prediction data. When null, the rule-based layout is shown.
  final ResultAiData? aiData;

  /// Whether to show the celebration overlay on mount.
  final bool showCelebration;

  /// How long the celebration overlay stays visible.
  final Duration celebrationDuration;

  @override
  State<AssessmentResultLayout> createState() => _AssessmentResultLayoutState();
}

class _AssessmentResultLayoutState extends State<AssessmentResultLayout> {
  bool _showCelebration = true;

  bool get _isAi => widget.aiData != null;

  @override
  void initState() {
    super.initState();
    _showCelebration = widget.showCelebration;
    if (_showCelebration) {
      Future.delayed(widget.celebrationDuration, () {
        if (mounted) setState(() => _showCelebration = false);
      });
    }
  }

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
                            color: AppColors.textPrimary,
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
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Main content: two scrollable columns ─────────
                    Expanded(
                      child: SingleChildScrollView(
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left column
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isAi) ...[
                                      _buildAiInsightsCard(),
                                      const SizedBox(height: 8),
                                      _buildGameScoresCard(),
                                    ] else ...[
                                      _buildProfileCard(),
                                      const SizedBox(height: 8),
                                      _buildGameScoresCard(),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Right column
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isAi) ...[
                                      _buildProfileCard(),
                                      const SizedBox(height: 8),
                                      _buildRecommendationsCard(),
                                    ] else ...[
                                      _buildRecommendationsCard(),
                                    ],
                                    const SizedBox(height: 6),
                                    _buildDisclaimer(),
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      width: double.infinity,
                                      child: AppPrimaryButton(
                                        label: 'Continue to Home',
                                        icon: Icons.home_rounded,
                                        onPressed: widget.onContinue,
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

  // ── Source badge ──────────────────────────────────────────────────────

  Widget _buildSourceBadge() {
    if (_isAi) {
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

  // ── AI Insights card ─────────────────────────────────────────────────

  Widget _buildAiInsightsCard() {
    final ai = widget.aiData!;
    return _card(
      title: 'AI Insights',
      emoji: '🤖',
      children: [
        if (ai.hasAreaLevels) ...[
          _buildAreaLevelsSection(ai),
          const SizedBox(height: 4),
        ] else ...[
          _aiRow(
            Icons.psychology_rounded,
            'AI Profile',
            ai.profileDisplayName ?? '',
          ),
          const SizedBox(height: 4),
        ],

        // Confidence
        _buildConfidenceRow(ai.confidence),
        const SizedBox(height: 4),

        // Support level (legacy, only when no per-area levels)
        if (!ai.hasAreaLevels && ai.supportLevel != null) ...[
          _aiRow(
            Icons.support_rounded,
            'Support Level',
            _supportLevelDisplay(ai.supportLevel!),
          ),
          const SizedBox(height: 6),
        ] else
          const SizedBox(height: 2),

        // Summary
        if (ai.summary.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.statusInfoBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              ai.summary,
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
        ],

        // Recommended Activities
        ..._buildActivitiesSection(ai),
      ],
    );
  }

  List<Widget> _buildActivitiesSection(ResultAiData ai) {
    if (ai.allFilteredOut) {
      return [
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.statusWarningBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'No activities available right now — please contact your administrator.',
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 11,
              color: AppColors.statusWarningDark,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }

    final widgets = <Widget>[];

    if (ai.modules.isNotEmpty) {
      widgets.addAll([
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
        ...ai.modules.map((mod) => Padding(
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
      ]);
    } else if (ai.recommendedModuleNames.isNotEmpty) {
      widgets.addAll([
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
        ...ai.recommendedModuleNames.map((name) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  const SizedBox(width: 17),
                  Icon(Icons.play_circle_outline_rounded,
                      size: 12, color: AppColors.mint),
                  const SizedBox(width: 4),
                  Text(
                    name,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )),
      ]);
    }

    return widgets;
  }

  // ── Per-area levels ──────────────────────────────────────────────────

  Widget _buildAreaLevelsSection(ResultAiData ai) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.psychology_rounded, size: 14, color: AppColors.lavender),
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
        for (final area in ai.areaLevels) _buildAreaLevelRow(area),
      ],
    );
  }

  Widget _buildAreaLevelRow(ResultAreaLevel area) {
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
        ],
      ),
    );
  }

  // ── Confidence row ───────────────────────────────────────────────────

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

  // ── Helper rows ──────────────────────────────────────────────────────

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

  // ── Profile card ─────────────────────────────────────────────────────

  Widget _buildProfileCard() {
    return _card(
      title: 'Developmental Profile',
      emoji: '📊',
      children: widget.profileRows
          .map((r) => _profileRow(r.area, r.level))
          .toList(),
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

  // ── Recommendations card ─────────────────────────────────────────────

  Widget _buildRecommendationsCard() {
    return _card(
      title: 'Recommendations',
      emoji: '💡',
      children: widget.recommendations
          .map((r) => _recRow(r.icon, r.label, r.value))
          .toList(),
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

  // ── Game Scores card ─────────────────────────────────────────────────

  Widget _buildGameScoresCard() {
    return _card(
      title: 'Game Scores',
      emoji: '🎮',
      children: widget.gameScores.map((g) {
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

  // ── Disclaimer ───────────────────────────────────────────────────────

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

  // ── Reusable card container ──────────────────────────────────────────

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
        mainAxisSize: MainAxisSize.min,
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
          ...children,
        ],
      ),
    );
  }
}
