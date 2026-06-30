import 'dart:math' as math;

import '../model/gameplay_session.dart';

/// Transforms raw [GameplaySession] records into the 12 XGBoost features the
/// on-device model expects.
///
/// This is an exact Dart port of `ai_assessment/app/feature_aggregator.py` so
/// on-device inference produces the same feature vector as the cloud service.
/// Keep the two in sync if either changes.
class OnDeviceFeatureAggregator {
  const OnDeviceFeatureAggregator();

  /// Default feature values used when no session data is available
  /// (mirrors DEFAULT_FEATURES in the Python aggregator).
  static const Map<String, double> defaultFeatures = {
    'overall_accuracy': 0.5,
    'overall_avg_response_time': 4.0,
    'overall_task_completion_rate': 0.5,
    'overall_retry_count': 3.0,
    'overall_hint_count': 5.0,
    'overall_prompt_dependency_score': 0.3,
    'overall_idle_time_seconds': 15.0,
    'overall_invalid_touch_count': 5.0,
    'copy_me_accuracy': 0.5,
    'match_it_accuracy': 0.5,
    'my_turn_your_turn_accuracy': 0.5,
    'do_what_i_say_accuracy': 0.5,
  };

  double _mean(List<double> values) =>
      values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;

  /// Adjusted accuracy for one session: score / (score + errors).
  double _sessionAccuracy(GameplaySession s) {
    final denominator = s.score + s.errorCount;
    if (denominator <= 0) return 0.0;
    return s.score / denominator;
  }

  double _perGameAccuracy(
    List<GameplaySession> sessions,
    String gameId, [
    double fallback = 0.5,
  ]) {
    final accuracies = sessions
        .where((s) => s.gameId == gameId)
        .map(_sessionAccuracy)
        .toList();
    return accuracies.isEmpty ? fallback : _mean(accuracies);
  }

  /// Returns the 12 features keyed by name (canonical order is applied later by
  /// the inference service using the model's `feature_names.json`).
  Map<String, double> aggregate(List<GameplaySession> sessions) {
    if (sessions.isEmpty) return Map.of(defaultFeatures);

    final n = sessions.length;

    final overallAccuracy = _mean(sessions.map(_sessionAccuracy).toList());

    final responseTimes = <double>[];
    for (final s in sessions) {
      if (s.totalItems > 0) {
        responseTimes.add((s.totalResponseTimeMs / 1000.0) / s.totalItems);
      }
    }
    final overallAvgResponseTime =
        responseTimes.isEmpty ? 4.0 : _mean(responseTimes);

    final completed = sessions.where((s) => s.score > 0).length;
    final overallTaskCompletionRate = completed / n;

    final overallRetryCount =
        _mean(sessions.map((s) => s.retryCount.toDouble()).toList());
    final overallHintCount =
        _mean(sessions.map((s) => s.hintCount.toDouble()).toList());

    final overallPromptDependencyScore = _mean(sessions
        .map((s) => s.hintCount / math.max(s.totalItems, 1))
        .toList());

    final overallIdleTimeSeconds =
        _mean(sessions.map((s) => s.idleTimeSeconds).toList());
    final overallInvalidTouchCount =
        _mean(sessions.map((s) => s.randomTouchCount.toDouble()).toList());

    return {
      'overall_accuracy': overallAccuracy,
      'overall_avg_response_time': overallAvgResponseTime,
      'overall_task_completion_rate': overallTaskCompletionRate,
      'overall_retry_count': overallRetryCount,
      'overall_hint_count': overallHintCount,
      'overall_prompt_dependency_score': overallPromptDependencyScore,
      'overall_idle_time_seconds': overallIdleTimeSeconds,
      'overall_invalid_touch_count': overallInvalidTouchCount,
      'copy_me_accuracy': _perGameAccuracy(sessions, 'copy_me'),
      'match_it_accuracy': _perGameAccuracy(sessions, 'match_it'),
      'my_turn_your_turn_accuracy':
          _perGameAccuracy(sessions, 'my_turn_your_turn'),
      'do_what_i_say_accuracy': _perGameAccuracy(sessions, 'do_what_i_say'),
    };
  }
}
