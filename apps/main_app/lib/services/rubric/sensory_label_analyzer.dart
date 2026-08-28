import 'rubric_labels.dart';
import '../../features/pre_assessment/sensory/sensory_round_metrics.dart';
import '../../features/pre_assessment/sensory/sensory_round_config.dart';

/// Analyzes sensory round metrics to determine the child's sensory preference.
///
/// Compares performance across different sensory conditions (music only,
/// haptic only, combined, baseline) to identify which modalities help,
/// hinder, or have no effect on the child's task performance.
class SensoryLabelAnalyzer {
  /// Creates a const instance of [SensoryLabelAnalyzer].
  const SensoryLabelAnalyzer();

  /// Improvement threshold — a condition must improve performance by at
  /// least this amount relative to baseline to be considered helpful.
  static const _improvementThreshold = 0.10;

  /// Decline threshold — a condition must decrease performance by at
  /// least this amount relative to baseline to be flagged as harmful.
  static const _declineThreshold = -0.10;

  /// Maximum response time (ms) used for normalization (5 seconds).
  static const _maxResponseTimeMs = 5000.0;

  /// Analyze sensory round metrics and return a [SensoryPreferenceLabel].
  ///
  /// [metrics] — List of [SensoryRoundMetrics] from the sensory experiment.
  /// Each metric has a [SensoryRoundConfig] with a `purpose` field
  /// ([SensoryRoundPurpose.musicOnly], [SensoryRoundPurpose.hapticOnly],
  /// [SensoryRoundPurpose.baseline], [SensoryRoundPurpose.combined],
  /// [SensoryRoundPurpose.attention]).
  ///
  /// Returns [SensoryPreferenceLabel.noSensorySupportNeeded] if the metrics
  /// list is empty or no baseline is found.
  SensoryPreferenceLabel analyze(List<SensoryRoundMetrics> metrics) {
    try {
      if (metrics.isEmpty) {
        return SensoryPreferenceLabel.noSensorySupportNeeded;
      }

      final baseline = _findByPurpose(metrics, SensoryRoundPurpose.baseline);
      if (baseline == null) {
        return SensoryPreferenceLabel.noSensorySupportNeeded;
      }

      final musicOnly =
          _findByPurpose(metrics, SensoryRoundPurpose.musicOnly);
      final hapticOnly =
          _findByPurpose(metrics, SensoryRoundPurpose.hapticOnly);
      final combined =
          _findByPurpose(metrics, SensoryRoundPurpose.combined);

      final baselineScore = _performanceScore(baseline);
      final musicScore =
          musicOnly != null ? _performanceScore(musicOnly) : baselineScore;
      final hapticScore =
          hapticOnly != null ? _performanceScore(hapticOnly) : baselineScore;
      final combinedScore =
          combined != null ? _performanceScore(combined) : baselineScore;

      final musicDelta = musicScore - baselineScore;
      final hapticDelta = hapticScore - baselineScore;
      final combinedDelta = combinedScore - baselineScore;

      // Check combined first — both modalities together help.
      if (combinedDelta >= _improvementThreshold &&
          musicDelta >= _improvementThreshold &&
          hapticDelta >= _improvementThreshold) {
        return SensoryPreferenceLabel.musicAndHapticHelp;
      }

      // Music helps but haptic does not.
      if (musicDelta >= _improvementThreshold &&
          hapticDelta < _improvementThreshold) {
        return SensoryPreferenceLabel.musicHelps;
      }

      // Haptic helps but music does not.
      if (hapticDelta >= _improvementThreshold &&
          musicDelta < _improvementThreshold) {
        return SensoryPreferenceLabel.hapticHelps;
      }

      // Music actively hurts performance.
      if (musicDelta <= _declineThreshold) {
        return SensoryPreferenceLabel.avoidMusic;
      }

      // Haptic actively hurts performance.
      if (hapticDelta <= _declineThreshold) {
        return SensoryPreferenceLabel.avoidHaptic;
      }

      return SensoryPreferenceLabel.noSensorySupportNeeded;
    } catch (_) {
      return SensoryPreferenceLabel.noSensorySupportNeeded;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /// Find the first metric matching the given [purpose], or `null`.
  SensoryRoundMetrics? _findByPurpose(
    List<SensoryRoundMetrics> metrics,
    SensoryRoundPurpose purpose,
  ) {
    for (final m in metrics) {
      if (m.sensoryConfig.purpose == purpose) return m;
    }
    return null;
  }

  /// Calculate a composite performance score for a single round.
  ///
  /// `performanceScore = accuracy * 0.6 + (1.0 - normalizedResponseTime) * 0.4`
  ///
  /// Where `normalizedResponseTime = min(avgResponseTimeMs / 5000.0, 1.0)`.
  /// If [avgResponseTimeMs] is 0, uses accuracy alone.
  double _performanceScore(SensoryRoundMetrics metric) {
    final accuracy = metric.accuracy.clamp(0.0, 1.0);

    if (metric.avgResponseTimeMs <= 0) {
      return accuracy;
    }

    final normalizedResponseTime =
        (metric.avgResponseTimeMs / _maxResponseTimeMs).clamp(0.0, 1.0);
    return accuracy * 0.6 + (1.0 - normalizedResponseTime) * 0.4;
  }
}
