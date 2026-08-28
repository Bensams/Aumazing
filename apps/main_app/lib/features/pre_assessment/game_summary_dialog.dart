import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';

/// Full-screen summary page shown after ALL pre-assessment games complete.
///
/// Displays a combined overview of all games played: correct taps,
/// error taps, off-target taps, time, and a Continue button. Non-dismissible:
/// the parent must press Continue (system back is blocked).
class GameSummaryDialog extends StatelessWidget {
  const GameSummaryDialog({
    super.key,
    required this.results,
    required this.onContinue,
    this.aiResponse,
  });

  final List<AssessmentResult> results;
  final VoidCallback onContinue;

  /// AI prediction data, or null if AI was unavailable (rule-based fallback).
  final AiAssessmentResponse? aiResponse;

  static const _gameNames = {
    'copy_me': 'Copy Me',
    'do_what_i_say': 'Do What I Say',
    'my_turn_your_turn': 'My Turn, Your Turn',
    'match_it': 'Match It',
  };

  static const _gameEmojis = {
    'copy_me': '📋',
    'do_what_i_say': '🗣️',
    'my_turn_your_turn': '🤝',
    'match_it': '🧩',
  };

  int get _totalCorrect => results.fold(0, (sum, r) => sum + r.score);
  int get _totalErrors => results.fold(0, (sum, r) => sum + r.errorCount);
  int get _totalRandomTouches =>
      results.fold(0, (sum, r) => sum + r.randomTouchCount);

  /// Total taps = correct taps + error taps + random/off-target taps.
  /// This matches how game_lab computes totalTaps.
  int get _totalTaps => _totalCorrect + _totalErrors + _totalRandomTouches;

  int get _totalTimeMs =>
      results.fold(0, (sum, r) => sum + r.avgResponseTimeMs * r.totalItems);

  /// Overall accuracy adjusted for errors: score / (score + errorCount).
  /// This penalises errors even when the game retries until correct.
  double get _overallAccuracy {
    final total = _totalCorrect + _totalErrors;
    if (total <= 0) return 0.0;
    return (_totalCorrect / total).clamp(0.0, 1.0);
  }

  String _formatDuration(int ms) {
    final seconds = ms ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${remainingSeconds}s';
    }
    return '${remainingSeconds}s';
  }

  String _performanceLabel() {
    if (_overallAccuracy >= 0.8) return 'Excellent!';
    if (_overallAccuracy >= 0.6) return 'Good Job!';
    if (_overallAccuracy >= 0.4) return 'Nice Try!';
    return 'Keep Practicing!';
  }

  String _performanceEmoji() {
    if (_overallAccuracy >= 0.8) return '🌟';
    if (_overallAccuracy >= 0.6) return '👍';
    if (_overallAccuracy >= 0.4) return '💪';
    return '🤗';
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_overallAccuracy * 100).round();

    // Non-dismissible: the parent must press Continue to proceed.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF8F6FF),
                Color(0xFFFFFFFF),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🎉', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 4),
                      Text(
                        'Pre-Assessment Summary',
                        style: AppTextStyles.headlineSmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      // Performance badge
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_performanceEmoji(),
                              style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 6),
                          Text(
                            _performanceLabel(),
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusPillBadge.fromScore(pct),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tap stats (correct, errors, off-target)
                        _buildTapStats(),
                        const SizedBox(height: 12),

                        // Overall stats (time, total)
                        _buildOverallStats(),
                        const SizedBox(height: 12),

                        // Per-game breakdown
                        _buildGameBreakdown(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: AppPrimaryButton(
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: onContinue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTapStats() {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(200),
        borderRadius: AppRadius.chip,
        border: Border.all(color: AppColors.border.withAlpha(80)),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTapStat(
              '✅',
              'Correct\nTaps',
              '$_totalCorrect',
            ),
          ),
          Container(width: 1, height: 48, color: AppColors.border),
          Expanded(
            child: _buildTapStat(
              '❌',
              'Error\nTaps',
              '$_totalErrors',
            ),
          ),
          Container(width: 1, height: 48, color: AppColors.border),
          Expanded(
            child: _buildTapStat(
              '⚠️',
              'Off-Target\nTaps',
              '$_totalRandomTouches',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTapStat(String emoji, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildOverallStats() {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(200),
        borderRadius: AppRadius.chip,
        border: Border.all(color: AppColors.border.withAlpha(80)),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildMiniStat(
              Icons.timer_rounded,
              'Total Time',
              _formatDuration(_totalTimeMs),
              AppColors.lavender,
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.border),
          Expanded(
            child: _buildMiniStat(
              Icons.touch_app_rounded,
              'Total Taps',
              '$_totalTaps',
              AppColors.primaryPurple,
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.border),
          Expanded(
            child: _buildMiniStat(
              Icons.games_rounded,
              'Games',
              '${results.length}',
              AppColors.butterYellow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(
      IconData icon, String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildGameBreakdown() {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(200),
        borderRadius: AppRadius.chip,
        border: Border.all(color: AppColors.border.withAlpha(80)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('🎮', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text('Game Results',
                  style: AppTextStyles.labelLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          ...results.map((r) => _buildGameRow(r)),
        ],
      ),
    );
  }

  Widget _buildGameRow(AssessmentResult r) {
    // Use adjustedAccuracy: score / (score + errorCount)
    // This properly penalises errors even when the game retries until correct.
    final accuracy = r.adjustedAccuracy;
    final pct = (accuracy * 100).round();
    final emoji = _gameEmojis[r.gameId] ?? '🎮';
    final name = _gameNames[r.gameId] ?? r.gameId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    )),
                Text(
                  '✅ ${r.score}  ❌ ${r.errorCount}  ⚠️ ${r.randomTouchCount}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          StatusPillBadge.fromScore(pct, compact: true),
        ],
      ),
    );
  }
}
