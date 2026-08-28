import 'sensory_round_config.dart';

/// Metrics for a single round with sensory context.
///
/// Captures both performance and engagement data alongside the sensory
/// configuration that was active during the round, enabling the
/// [SensoryPreferenceAnalyzer] to compare outcomes across different
/// music/haptic combinations.
class SensoryRoundMetrics {
  /// Identifier of the game played (e.g. 'copy_me', 'match_it').
  final String gameId;

  /// Round number within the game (1-5).
  final int roundNumber;

  /// The sensory configuration that was active during this round.
  final SensoryRoundConfig sensoryConfig;

  // ── Performance metrics ───────────────────────────────────────────────

  /// Number of correct answers.
  final int correctCount;

  /// Number of wrong answers.
  final int wrongCount;

  /// Accuracy ratio (0.0 - 1.0).
  final double accuracy;

  /// Total response time across all items in milliseconds.
  final int totalResponseTimeMs;

  /// Average response time per item in milliseconds.
  final double avgResponseTimeMs;

  // ── Engagement metrics ────────────────────────────────────────────────

  /// Total number of taps/interactions.
  final int tapCount;

  /// Total idle time in seconds (periods with no interaction).
  final double idleTimeSeconds;

  /// Number of random/off-target touches.
  final int randomTouchCount;

  // ── Timing ────────────────────────────────────────────────────────────

  /// Time from round start to first touch in milliseconds.
  final double timeToFirstTouchMs;

  /// Time from round start to completion in milliseconds.
  final double timeToCompletionMs;

  // ── Assistance ────────────────────────────────────────────────────────

  /// Number of hints shown.
  final int hintCount;

  /// Number of prompts/nudges given.
  final int promptCount;

  /// Number of retries.
  final int retryCount;

  const SensoryRoundMetrics({
    required this.gameId,
    required this.roundNumber,
    required this.sensoryConfig,
    required this.correctCount,
    required this.wrongCount,
    required this.accuracy,
    required this.totalResponseTimeMs,
    required this.avgResponseTimeMs,
    required this.tapCount,
    required this.idleTimeSeconds,
    required this.randomTouchCount,
    required this.timeToFirstTouchMs,
    required this.timeToCompletionMs,
    required this.hintCount,
    required this.promptCount,
    required this.retryCount,
  });

  // ── Serialization ─────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'game_id': gameId,
        'round_number': roundNumber,
        'music_enabled': sensoryConfig.musicEnabled ? 1 : 0,
        'haptic_enabled': sensoryConfig.hapticEnabled ? 1 : 0,
        'sensory_purpose': sensoryConfig.purpose.name,
        'correct_count': correctCount,
        'wrong_count': wrongCount,
        'accuracy': accuracy,
        'total_response_time_ms': totalResponseTimeMs,
        'avg_response_time_ms': avgResponseTimeMs,
        'tap_count': tapCount,
        'idle_time_seconds': idleTimeSeconds,
        'random_touch_count': randomTouchCount,
        'time_to_first_touch_ms': timeToFirstTouchMs,
        'time_to_completion_ms': timeToCompletionMs,
        'hint_count': hintCount,
        'prompt_count': promptCount,
        'retry_count': retryCount,
      };

  factory SensoryRoundMetrics.fromMap(Map<String, dynamic> map) =>
      SensoryRoundMetrics(
        gameId: map['game_id'] as String,
        roundNumber: map['round_number'] as int,
        sensoryConfig: SensoryRoundConfig(
          roundNumber: map['round_number'] as int,
          musicEnabled: (map['music_enabled'] as int) == 1,
          hapticEnabled: (map['haptic_enabled'] as int) == 1,
          purpose: SensoryRoundPurpose.values.firstWhere(
            (e) => e.name == map['sensory_purpose'],
            orElse: () => SensoryRoundPurpose.baseline,
          ),
          label: map['sensory_purpose'] as String,
        ),
        correctCount: map['correct_count'] as int,
        wrongCount: map['wrong_count'] as int,
        accuracy: (map['accuracy'] as num).toDouble(),
        totalResponseTimeMs: map['total_response_time_ms'] as int,
        avgResponseTimeMs: (map['avg_response_time_ms'] as num).toDouble(),
        tapCount: map['tap_count'] as int,
        idleTimeSeconds: (map['idle_time_seconds'] as num).toDouble(),
        randomTouchCount: map['random_touch_count'] as int,
        timeToFirstTouchMs:
            (map['time_to_first_touch_ms'] as num).toDouble(),
        timeToCompletionMs:
            (map['time_to_completion_ms'] as num).toDouble(),
        hintCount: map['hint_count'] as int,
        promptCount: map['prompt_count'] as int,
        retryCount: map['retry_count'] as int,
      );
}
