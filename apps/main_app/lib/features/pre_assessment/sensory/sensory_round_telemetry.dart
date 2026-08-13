import 'package:game_core/game_core.dart';

import 'sensory_round_config.dart';
import 'sensory_round_metrics.dart';

/// What one game contributed to the sensory experiment.
class SensoryTelemetryCollection {
  const SensoryTelemetryCollection({
    required this.metrics,
    required this.reliable,
  });

  /// One entry per round the game actually reported.
  final List<SensoryRoundMetrics> metrics;

  /// True when every round the game played was measured and mapped to a
  /// known [SensoryRoundConfig].
  ///
  /// False means the recommendation would be guesswork: the game reported no
  /// per-round telemetry at all, or reported rounds the experiment has no
  /// configuration for.
  final bool reliable;

  static const empty = SensoryTelemetryCollection(metrics: [], reliable: false);
}

/// Turns a game's real per-round telemetry into sensory round metrics.
///
/// The previous implementation divided a game's *totals* evenly across the
/// round configurations, which gave every sensory condition an identical
/// score by construction — the comparison could only ever measure rounding
/// noise. Here each [GameRoundMetrics] keeps its own accuracy, errors,
/// response time, touches, idle time, prompts, hints and retries, attributed
/// to the [SensoryRoundConfig] that was active while that round was played.
abstract final class SensoryRoundTelemetry {
  static SensoryTelemetryCollection collect({
    required String gameId,
    required GameSessionMetrics? analytics,
    required List<SensoryRoundConfig> rounds,
  }) {
    final recorded = analytics?.rounds ?? const <GameRoundMetrics>[];
    if (recorded.isEmpty || rounds.isEmpty) {
      return SensoryTelemetryCollection.empty;
    }

    SensoryRoundConfig? configFor(int roundNumber) {
      for (final config in rounds) {
        if (config.roundNumber == roundNumber) return config;
      }
      return null;
    }

    final metrics = <SensoryRoundMetrics>[];
    var reliable = true;

    for (final round in recorded) {
      final config = configFor(round.roundNumber);
      if (config == null) {
        // A round we cannot attribute to a condition — the comparison is
        // no longer complete.
        reliable = false;
        continue;
      }

      final totalMs = round.timeToCompletion * 1000.0;
      final interactions = round.totalInteractions;

      metrics.add(
        SensoryRoundMetrics(
          gameId: gameId,
          roundNumber: round.roundNumber,
          sensoryConfig: config,
          correctCount: round.correctCount,
          wrongCount: round.wrongCount,
          accuracy: round.accuracy,
          totalResponseTimeMs: totalMs.round(),
          avgResponseTimeMs: interactions > 0 ? totalMs / interactions : 0.0,
          tapCount: interactions + round.randomTouchCount,
          idleTimeSeconds: round.idleTimeSeconds.toDouble(),
          randomTouchCount: round.randomTouchCount,
          timeToFirstTouchMs: round.timeToFirstTouch * 1000.0,
          timeToCompletionMs: totalMs,
          hintCount: round.hintCount,
          promptCount: round.promptCount,
          retryCount: round.retryCount,
        ),
      );
    }

    if (metrics.isEmpty) return SensoryTelemetryCollection.empty;
    return SensoryTelemetryCollection(metrics: metrics, reliable: reliable);
  }
}
