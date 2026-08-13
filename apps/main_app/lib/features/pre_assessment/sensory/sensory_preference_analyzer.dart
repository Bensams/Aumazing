import 'sensory_round_config.dart';
import 'sensory_round_metrics.dart';
import 'attention_metrics.dart';

/// Confidence level of the preference analysis.
enum ConfidenceLevel { low, medium, high }

/// Result of sensory preference analysis across all pre-assessment rounds.
class SensoryPreferenceResult {
  /// Whether background music is recommended.
  final bool recommendedMusicEnabled;

  /// Whether haptic feedback is recommended.
  final bool recommendedHapticEnabled;

  /// The sensory configuration that scored highest.
  final SensoryRoundPurpose bestConfig;

  /// How confident the analysis is in its recommendation.
  final ConfidenceLevel confidence;

  /// Composite scores for each sensory configuration.
  final Map<SensoryRoundPurpose, double> configScores;

  /// Attention metrics from Round 5 (if available).
  final AttentionMetrics? attentionSummary;

  /// When the analysis was performed.
  final DateTime analyzedAt;

  /// Whether the recommendation can be acted on.
  ///
  /// False when the per-round telemetry behind it was missing or could not
  /// be attributed to the sensory conditions — a recommendation derived from
  /// that would be a guess dressed up as a measurement, so it is surfaced as
  /// unavailable (and always at [ConfidenceLevel.low]) instead.
  final bool available;

  const SensoryPreferenceResult({
    required this.recommendedMusicEnabled,
    required this.recommendedHapticEnabled,
    required this.bestConfig,
    required this.confidence,
    required this.configScores,
    this.attentionSummary,
    required this.analyzedAt,
    this.available = true,
  });

  Map<String, dynamic> toMap() => {
        'recommended_music_enabled': recommendedMusicEnabled ? 1 : 0,
        'recommended_haptic_enabled': recommendedHapticEnabled ? 1 : 0,
        'best_config': bestConfig.name,
        'confidence': confidence.name,
        'available': available ? 1 : 0,
        'config_scores':
            configScores.map((k, v) => MapEntry(k.name, v)),
        'attention_summary': attentionSummary?.toMap(),
        'analyzed_at': analyzedAt.toIso8601String(),
      };
}

/// Analyzes sensory round metrics to determine optimal sensory preferences.
///
/// Uses a composite scoring model:
/// - Accuracy: 40%
/// - Response time: 25%
/// - Engagement: 20%
/// - Consistency (low assistance): 15%
///
/// Rounds 1-4 are compared to find the best sensory configuration.
/// Round 5 (attention) is analyzed separately for behavioral insights.
class SensoryPreferenceAnalyzer {
  static const _accuracyWeight = 0.40;
  static const _responseTimeWeight = 0.25;
  static const _engagementWeight = 0.20;
  static const _consistencyWeight = 0.15;

  /// Analyze all round metrics across all games to determine the best
  /// sensory configuration.
  ///
  /// [allMetrics] should contain metrics from all 4 games x 5 rounds
  /// (up to 20 entries). Rounds are grouped by [SensoryRoundPurpose]
  /// and scored using the composite model.
  ///
  /// Pass `telemetryReliable: false` when the per-round measurements behind
  /// [allMetrics] were incomplete: the result is then marked unavailable and
  /// pinned to [ConfidenceLevel.low] rather than presented as a finding.
  SensoryPreferenceResult analyze(
    List<SensoryRoundMetrics> allMetrics, {
    bool telemetryReliable = true,
  }) {
    if (allMetrics.isEmpty) {
      return SensoryPreferenceResult(
        recommendedMusicEnabled: false,
        recommendedHapticEnabled: false,
        bestConfig: SensoryRoundPurpose.baseline,
        confidence: ConfidenceLevel.low,
        configScores: const {},
        analyzedAt: DateTime.now(),
        available: false,
      );
    }
    // Group metrics by sensory purpose (excluding attention round)
    final grouped = <SensoryRoundPurpose, List<SensoryRoundMetrics>>{};
    final attentionRounds = <SensoryRoundMetrics>[];

    for (final m in allMetrics) {
      if (m.sensoryConfig.purpose == SensoryRoundPurpose.attention) {
        attentionRounds.add(m);
      } else {
        grouped
            .putIfAbsent(m.sensoryConfig.purpose, () => [])
            .add(m);
      }
    }

    // Calculate composite score for each config
    final scores = <SensoryRoundPurpose, double>{};
    for (final entry in grouped.entries) {
      scores[entry.key] = _calculateCompositeScore(entry.value);
    }

    // Find best config
    SensoryRoundPurpose bestConfig = SensoryRoundPurpose.baseline;
    double bestScore = -1;
    for (final entry in scores.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestConfig = entry.key;
      }
    }

    // Determine recommended settings from best config
    bool recMusic = false;
    bool recHaptic = false;
    switch (bestConfig) {
      case SensoryRoundPurpose.musicOnly:
        recMusic = true;
        recHaptic = false;
      case SensoryRoundPurpose.hapticOnly:
        recMusic = false;
        recHaptic = true;
      case SensoryRoundPurpose.combined:
        recMusic = true;
        recHaptic = true;
      case SensoryRoundPurpose.baseline:
        recMusic = false;
        recHaptic = false;
      case SensoryRoundPurpose.attention:
        // Fallback — should not be the "best" config
        recMusic = true;
        recHaptic = true;
    }

    // Calculate confidence
    final confidence = telemetryReliable
        ? _calculateConfidence(scores, bestConfig)
        : ConfidenceLevel.low;

    // Analyze attention metrics from round 5
    AttentionMetrics? attentionSummary;
    if (attentionRounds.isNotEmpty) {
      attentionSummary = _analyzeAttention(attentionRounds);
    }

    return SensoryPreferenceResult(
      recommendedMusicEnabled: recMusic,
      recommendedHapticEnabled: recHaptic,
      bestConfig: bestConfig,
      confidence: confidence,
      configScores: scores,
      attentionSummary: attentionSummary,
      analyzedAt: DateTime.now(),
      available: telemetryReliable && scores.isNotEmpty,
    );
  }

  /// Calculate a composite score for a set of metrics sharing the same
  /// sensory configuration.
  double _calculateCompositeScore(List<SensoryRoundMetrics> metrics) {
    if (metrics.isEmpty) return 0.0;

    // Average accuracy across games for this config
    final avgAccuracy =
        metrics.map((m) => m.accuracy).reduce((a, b) => a + b) /
            metrics.length;

    // Normalize response time (lower is better, cap at 10000ms)
    final avgResponseTime =
        metrics.map((m) => m.avgResponseTimeMs).reduce((a, b) => a + b) /
            metrics.length;
    final responseTimeScore =
        (1.0 - (avgResponseTime / 10000.0)).clamp(0.0, 1.0);

    // Engagement score (less idle time + fewer random touches = better)
    final avgIdleTime =
        metrics.map((m) => m.idleTimeSeconds).reduce((a, b) => a + b) /
            metrics.length;
    final avgRandomTouches = metrics
            .map((m) => m.randomTouchCount.toDouble())
            .reduce((a, b) => a + b) /
        metrics.length;
    final engagementScore =
        ((1.0 - (avgIdleTime / 30.0)) * 0.7 +
                (1.0 - (avgRandomTouches / 10.0)) * 0.3)
            .clamp(0.0, 1.0);

    // Consistency score (less need for hints/prompts/retries = better)
    final avgAssistance = metrics
            .map((m) =>
                (m.hintCount + m.promptCount + m.retryCount).toDouble())
            .reduce((a, b) => a + b) /
        metrics.length;
    final consistencyScore =
        (1.0 - (avgAssistance / 10.0)).clamp(0.0, 1.0);

    return (avgAccuracy * _accuracyWeight) +
        (responseTimeScore * _responseTimeWeight) +
        (engagementScore * _engagementWeight) +
        (consistencyScore * _consistencyWeight);
  }

  /// Determine confidence based on the margin between the best score
  /// and the average of other scores.
  ConfidenceLevel _calculateConfidence(
    Map<SensoryRoundPurpose, double> scores,
    SensoryRoundPurpose best,
  ) {
    if (scores.length < 2) return ConfidenceLevel.low;

    final bestScore = scores[best] ?? 0.0;
    final otherScores = scores.entries
        .where((e) => e.key != best)
        .map((e) => e.value)
        .toList();
    final avgOther =
        otherScores.reduce((a, b) => a + b) / otherScores.length;

    final margin = bestScore - avgOther;
    if (margin > 0.15) return ConfidenceLevel.high;
    if (margin > 0.05) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }

  /// Aggregate attention metrics from Round 5 across all games.
  AttentionMetrics _analyzeAttention(
    List<SensoryRoundMetrics> attentionRounds,
  ) {
    final count = attentionRounds.length;

    final avgIdleTime =
        attentionRounds.map((m) => m.idleTimeSeconds).reduce((a, b) => a + b) /
            count;
    final avgRandomTouches =
        (attentionRounds.map((m) => m.randomTouchCount).reduce((a, b) => a + b) /
                count)
            .round();
    final avgFirstTouch = attentionRounds
            .map((m) => m.timeToFirstTouchMs)
            .reduce((a, b) => a + b) /
        count;
    final avgCompletion = attentionRounds
            .map((m) => m.timeToCompletionMs)
            .reduce((a, b) => a + b) /
        count;
    final avgCorrect =
        (attentionRounds.map((m) => m.correctCount).reduce((a, b) => a + b) /
                count)
            .round();
    final avgWrong =
        (attentionRounds.map((m) => m.wrongCount).reduce((a, b) => a + b) /
                count)
            .round();
    final avgResponseTime = attentionRounds
            .map((m) => m.avgResponseTimeMs)
            .reduce((a, b) => a + b) /
        count;
    final totalItems = avgCorrect + avgWrong;

    return AttentionMetrics.fromRoundData(
      totalRoundTimeSeconds: avgCompletion / 1000.0,
      idleTimeSeconds: avgIdleTime,
      randomTouchCount: avgRandomTouches,
      timeToFirstTouchMs: avgFirstTouch,
      timeToCompletionMs: avgCompletion,
      correctCount: avgCorrect,
      wrongCount: avgWrong,
      totalItems: totalItems > 0 ? totalItems : 1,
      avgResponseTimeMs: avgResponseTime,
    );
  }
}
