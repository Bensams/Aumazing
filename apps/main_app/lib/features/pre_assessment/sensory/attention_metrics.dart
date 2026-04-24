/// Attention level classification derived from Round 5 observation data.
enum AttentionLevel { short, moderate, sustained }

/// Behavioral indicators tracked during Round 5 (attention round).
///
/// Round 5 uses the recommended sensory config (both music and haptic ON)
/// and focuses on measuring the child's attention and engagement patterns
/// rather than comparing sensory preferences.
class AttentionMetrics {
  /// Total time the child was actively engaged (seconds).
  final double focusDurationSeconds;

  /// Number of idle periods longer than 3 seconds.
  final int attentionBreaks;

  /// Time from instruction shown to first response (ms).
  final double instructionResponseTimeMs;

  /// Number of taps before the stimulus was shown.
  final int prematureTaps;

  /// Ratio of active time to total round time (0.0 - 1.0).
  final double onTaskRatio;

  /// Response consistency (0.0 - 1.0, where 1.0 = highly consistent).
  final double responseConsistency;

  /// Classified attention level.
  final AttentionLevel attentionLevel;

  const AttentionMetrics({
    required this.focusDurationSeconds,
    required this.attentionBreaks,
    required this.instructionResponseTimeMs,
    required this.prematureTaps,
    required this.onTaskRatio,
    required this.responseConsistency,
    required this.attentionLevel,
  });

  /// Derive attention metrics from raw round data.
  ///
  /// This factory computes engagement ratios, estimates attention breaks,
  /// and classifies the overall attention level.
  factory AttentionMetrics.fromRoundData({
    required double totalRoundTimeSeconds,
    required double idleTimeSeconds,
    required int randomTouchCount,
    required double timeToFirstTouchMs,
    required double timeToCompletionMs,
    required int correctCount,
    required int wrongCount,
    required int totalItems,
    required double avgResponseTimeMs,
  }) {
    final activeTime = totalRoundTimeSeconds - idleTimeSeconds;
    final onTaskRatio = totalRoundTimeSeconds > 0
        ? (activeTime / totalRoundTimeSeconds).clamp(0.0, 1.0)
        : 0.0;

    // Estimate attention breaks (idle periods > 3s)
    final estimatedBreaks = (idleTimeSeconds / 3.0).floor();

    // Response consistency: lower avg response time = more consistent.
    // Normalize to 0-1 where 1 = consistent (cap at 5000ms).
    final consistency = avgResponseTimeMs > 0
        ? (1.0 - (avgResponseTimeMs / 5000.0)).clamp(0.0, 1.0)
        : 0.0;

    // Classify attention level
    AttentionLevel level;
    if (onTaskRatio >= 0.8 && estimatedBreaks <= 1) {
      level = AttentionLevel.sustained;
    } else if (onTaskRatio >= 0.5 && estimatedBreaks <= 3) {
      level = AttentionLevel.moderate;
    } else {
      level = AttentionLevel.short;
    }

    return AttentionMetrics(
      focusDurationSeconds: activeTime,
      attentionBreaks: estimatedBreaks,
      instructionResponseTimeMs: timeToFirstTouchMs,
      prematureTaps: randomTouchCount,
      onTaskRatio: onTaskRatio,
      responseConsistency: consistency,
      attentionLevel: level,
    );
  }

  // ── Serialization ─────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'focus_duration_seconds': focusDurationSeconds,
        'attention_breaks': attentionBreaks,
        'instruction_response_time_ms': instructionResponseTimeMs,
        'premature_taps': prematureTaps,
        'on_task_ratio': onTaskRatio,
        'response_consistency': responseConsistency,
        'attention_level': attentionLevel.name,
      };

  factory AttentionMetrics.fromMap(Map<String, dynamic> map) =>
      AttentionMetrics(
        focusDurationSeconds:
            (map['focus_duration_seconds'] as num).toDouble(),
        attentionBreaks: map['attention_breaks'] as int,
        instructionResponseTimeMs:
            (map['instruction_response_time_ms'] as num).toDouble(),
        prematureTaps: map['premature_taps'] as int,
        onTaskRatio: (map['on_task_ratio'] as num).toDouble(),
        responseConsistency:
            (map['response_consistency'] as num).toDouble(),
        attentionLevel: AttentionLevel.values.firstWhere(
          (e) => e.name == map['attention_level'],
          orElse: () => AttentionLevel.short,
        ),
      );
}
