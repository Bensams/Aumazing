import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';

/// Summary dialog shown after ALL pre-assessment games complete.
///
/// Displays a combined overview of all games played: correct taps,
/// error taps, failure taps, time, and a Continue button.
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

  Color _scoreColor(double accuracy) {
    if (accuracy >= 0.8) return AppColors.mint;
    if (accuracy >= 0.5) return AppColors.butterYellow;
    return AppColors.peach;
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

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 540),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF8F6FF),
              Color(0xFFFFFFFF),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryPurple.withAlpha(30),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fixed header
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
                      color: AppColors.primaryPurple,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // Performance badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _scoreColor(_overallAccuracy).withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_performanceEmoji(),
                            style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 6),
                        Text(
                          '${_performanceLabel()} ($pct%)',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: _scoreColor(_overallAccuracy),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),

            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tap stats (correct, errors, failures)
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

            // Fixed footer
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
    );
  }

  Widget _buildTapStats() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(200),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withAlpha(80)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTapStat(
              '✅',
              'Correct\nTaps',
              '$_totalCorrect',
              AppColors.mint,
            ),
          ),
          Container(width: 1, height: 48, color: AppColors.border),
          Expanded(
            child: _buildTapStat(
              '❌',
              'Error\nTaps',
              '$_totalErrors',
              _totalErrors == 0 ? AppColors.mint : AppColors.peach,
            ),
          ),
          Container(width: 1, height: 48, color: AppColors.border),
          Expanded(
            child: _buildTapStat(
              '⚠️',
              'Off-Target\nTaps',
              '$_totalRandomTouches',
              _totalRandomTouches == 0
                  ? AppColors.mint
                  : AppColors.butterYellow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTapStat(
      String emoji, String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.mutedForeground,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildOverallStats() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(200),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withAlpha(80)),
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
          ),
        ),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.mutedForeground,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildGameBreakdown() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(200),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withAlpha(80)),
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
                  style: AppTextStyles.labelLarge
                      .copyWith(fontWeight: FontWeight.w600)),
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
                    style: AppTextStyles.bodySmall
                        .copyWith(fontWeight: FontWeight.w600)),
                Text(
                  '✅ ${r.score}  ❌ ${r.errorCount}  ⚠️ ${r.randomTouchCount}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.mutedForeground,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: _scoreColor(accuracy).withAlpha(35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$pct%',
              style: AppTextStyles.labelLarge.copyWith(
                color: _scoreColor(accuracy),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
