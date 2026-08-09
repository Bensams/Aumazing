import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_primary_button.dart';
import 'assessment_result_data.dart';
import 'game_celebration_overlay.dart';

/// Shared layout widget for the pre-assessment result screen.
///
/// Used by both `main_app` (with live data) and `game_lab` (with mock data).
/// All data is passed in via plain data classes from [assessment_result_data.dart].
///
/// Responsive: single column below 720 px of available width, two balanced
/// columns above it (tablets / landscape).
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
  static const double _twoColumnBreakpoint = 720;

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
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= _twoColumnBreakpoint;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWide ? 920 : 560),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 20,
                        vertical: isWide ? 28 : 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(),
                          SizedBox(height: isWide ? 28 : 20),
                          if (isWide)
                            _buildTwoColumnBody()
                          else
                            _buildSingleColumnBody(),
                          const SizedBox(height: 20),
                          _buildDisclaimer(),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.center,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: SizedBox(
                                width: double.infinity,
                                child: AppPrimaryButton(
                                  label: 'Continue to Home',
                                  icon: Icons.arrow_forward_rounded,
                                  onPressed: widget.onContinue,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
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

  // ── Header ───────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'PRE-ASSESSMENT',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primaryPurple,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            _buildSourceTag(),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Here’s what we observed',
          style: AppTextStyles.headlineLarge.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'A summary of how your child played the assessment games.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.mutedForeground,
          ),
        ),
      ],
    );
  }

  /// Quiet inline tag naming the analysis source instead of a loud badge.
  Widget _buildSourceTag() {
    final label = _isAi ? 'AI analysis' : 'Rule-based';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _isAi ? AppColors.primaryPurple : AppColors.skyBlue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Column arrangements ──────────────────────────────────────────────

  List<Widget> _leftCards() => [
        if (_isAi) _buildAiInsightsCard() else _buildProfileCard(),
        _buildGameScoresCard(),
      ];

  List<Widget> _rightCards() => [
        if (_isAi) _buildProfileCard(),
        _buildRecommendationsCard(),
      ];

  Widget _buildSingleColumnBody() {
    final cards = [..._leftCards(), ..._rightCards()];
    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          cards[i],
        ],
      ],
    );
  }

  Widget _buildTwoColumnBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _stacked(_leftCards())),
        const SizedBox(width: 16),
        Expanded(child: _stacked(_rightCards())),
      ],
    );
  }

  Widget _stacked(List<Widget> cards) {
    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          cards[i],
        ],
      ],
    );
  }

  // ── AI Insights card ─────────────────────────────────────────────────

  Widget _buildAiInsightsCard() {
    final ai = widget.aiData!;
    return _sectionCard(
      label: 'AI Insights',
      children: [
        if (ai.hasAreaLevels)
          ..._withDividers([
            for (final area in ai.areaLevels)
              _levelRow(area.label, area.levelInt, area.levelName),
          ])
        else
          _keyValueRow('AI Profile', ai.profileDisplayName ?? ''),
        const SizedBox(height: 14),
        _buildConfidenceRow(ai.confidence),
        if (!ai.hasAreaLevels && ai.supportLevel != null) ...[
          const SizedBox(height: 10),
          _keyValueRow('Support level', _supportLevelDisplay(ai.supportLevel!)),
        ],
        if (ai.summary.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              ai.summary,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
        ..._buildActivitiesSection(ai),
      ],
    );
  }

  List<Widget> _buildActivitiesSection(ResultAiData ai) {
    if (ai.allFilteredOut) {
      return [
        const SizedBox(height: 14),
        Text(
          'No activities available right now — please contact your '
          'administrator.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.statusWarningDark,
          ),
        ),
      ];
    }

    final hasModules = ai.modules.isNotEmpty;
    final hasNames = ai.recommendedModuleNames.isNotEmpty;
    if (!hasModules && !hasNames) return const [];

    return [
      const SizedBox(height: 16),
      _subLabel('Recommended activities'),
      const SizedBox(height: 6),
      if (hasModules)
        ..._withDividers([
          for (var i = 0; i < ai.modules.length; i++)
            _moduleRow(i + 1, ai.modules[i].name,
                'Level ${ai.modules[i].startingLevel}'),
        ])
      else
        ..._withDividers([
          for (var i = 0; i < ai.recommendedModuleNames.length; i++)
            _moduleRow(i + 1, ai.recommendedModuleNames[i], null),
        ]),
    ];
  }

  Widget _moduleRow(int index, String name, String? levelLabel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$index',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (levelLabel != null)
            Text(
              levelLabel,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 0.2,
              ),
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
        Expanded(
          child: Text(
            'Confidence',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        SizedBox(
          width: 96,
          height: 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: confidence,
              backgroundColor: AppColors.muted,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 38,
          child: Text(
            '$pct%',
            textAlign: TextAlign.right,
            style: AppTextStyles.titleMedium.copyWith(color: color),
          ),
        ),
      ],
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
    return _sectionCard(
      label: 'Developmental Profile',
      children: _withDividers([
        for (final r in widget.profileRows) _profileRow(r.area, r.level),
      ]),
    );
  }

  Widget _profileRow(String area, String level) {
    final levelInt = _levelIntFromLabel(level);
    if (levelInt != null) return _levelRow(area, levelInt, level);

    // Free-form values (e.g. sensory notes) render as plain text.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              area,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              level,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Recommendations card ─────────────────────────────────────────────

  Widget _buildRecommendationsCard() {
    return _sectionCard(
      label: 'Recommended Settings',
      children: _withDividers([
        for (final r in widget.recommendations)
          _recRow(r.icon, r.label, r.value),
      ]),
    );
  }

  Widget _recRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.lavenderLight,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.primaryPurple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Game Scores card ─────────────────────────────────────────────────

  Widget _buildGameScoresCard() {
    return _sectionCard(
      label: 'Game Scores',
      children: _withDividers([
        for (final g in widget.gameScores) _gameScoreRow(g),
      ]),
    );
  }

  Widget _gameScoreRow(ResultGameScore g) {
    final pct = (g.accuracy * 100).round();
    final color = pct >= 80
        ? AppColors.statusSuccessDark
        : pct >= 50
            ? AppColors.statusWarningDark
            : AppColors.statusDangerDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              g.name,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 96,
            height: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: g.accuracy,
                backgroundColor: AppColors.muted,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 38,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: AppTextStyles.titleMedium.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  // ── Disclaimer ───────────────────────────────────────────────────────

  Widget _buildDisclaimer() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded,
            size: 15, color: AppColors.mutedForeground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Not a clinical diagnosis. These observations are only used to '
            'customize your child’s learning activities.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared building blocks ───────────────────────────────────────────

  /// A row showing an area name with a 3-segment level meter and level name.
  Widget _levelRow(String label, int levelInt, String levelName) {
    final color = _levelColor(levelInt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          _LevelMeter(filled: levelInt + 1, color: color),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: Text(
              levelName,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyMedium.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _levelColor(int levelInt) {
    switch (levelInt) {
      case 0:
        return AppColors.statusWarningDark;
      case 2:
        return AppColors.statusSuccessDark;
      default:
        return AppColors.statusInfoDark;
    }
  }

  /// Maps a free-form level label to an ordinal, or null when unknown.
  int? _levelIntFromLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('strength') || l.contains('strong')) return 2;
    if (l.contains('emerging') || l.contains('developing') ||
        l.contains('moderate')) {
      return 1;
    }
    if (l.contains('support') || l.contains('delayed')) return 0;
    return null;
  }

  Widget _keyValueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _subLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.mutedForeground,
        letterSpacing: 1.0,
        fontSize: 11,
      ),
    );
  }

  /// Interleaves hairline dividers between rows.
  List<Widget> _withDividers(List<Widget> rows) {
    return [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const Divider(height: 1, thickness: 1, color: AppColors.border),
        rows[i],
      ],
    ];
  }

  /// Flat white card with a hairline border and an uppercase section label.
  Widget _sectionCard({
    required String label,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel(label),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// Three small rounded segments; [filled] of them are tinted with [color].
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.filled, required this.color});

  final int filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
            child: Container(
              width: 14,
              height: 5,
              decoration: BoxDecoration(
                color: i < filled ? color : AppColors.muted,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}
