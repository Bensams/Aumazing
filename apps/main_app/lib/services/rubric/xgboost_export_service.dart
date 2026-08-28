import 'dart:math' as math;

import '../../model/gameplay_session.dart';
import 'rubric_result.dart';

/// Stateless service that generates XGBoost-ready training data rows.
///
/// Converts raw [GameplaySession] telemetry and [RubricResult] labels into
/// flat feature maps suitable for machine-learning model training. Each row
/// contains 20 input features and 6 target columns.
class XGBoostExportService {
  /// Creates a const instance of [XGBoostExportService].
  const XGBoostExportService();

  // ── Game ID constants ──────────────────────────────────────────────────

  static const _matchIt = 'match_it';
  static const _copyMe = 'copy_me';
  static const _doWhatISay = 'do_what_i_say';
  static const _myTurnYourTurn = 'my_turn_your_turn';

  /// Generate a single XGBoost-ready row from sessions and rubric result.
  ///
  /// Returns a [Map] with 20 feature columns (inputs) and 6 target columns
  /// (labels). All numeric values default to `0.0` when data is unavailable.
  ///
  /// [childId] — Unique identifier for the child.
  /// [sessions] — All [GameplaySession] objects from the assessment.
  /// [rubricResult] — The scored [RubricResult] for this assessment.
  Map<String, dynamic> generateRow({
    required String childId,
    required List<GameplaySession> sessions,
    required RubricResult rubricResult,
  }) {
    try {
      final valid = sessions.where((s) => s.totalItems > 0).toList();

      final matchItSessions = _filterByGameId(valid, _matchIt);
      final copySessions = _filterByGameId(valid, _copyMe);
      final doWhatISaySessions = _filterByGameId(valid, _doWhatISay);
      final myTurnSessions = _filterByGameId(valid, _myTurnYourTurn);

      return {
        // ── Input features (20) ────────────────────────────────────────
        'child_id': childId,
        'overall_accuracy': _meanAccuracy(valid),
        'overall_avg_response_time':
            _meanDouble(valid, (s) => s.avgResponseTime),
        'overall_task_completion_rate': _meanTaskCompletionRate(valid),
        'overall_retry_count':
            _meanDouble(valid, (s) => s.retryCount.toDouble()),
        'overall_hint_count':
            _meanDouble(valid, (s) => s.hintCount.toDouble()),
        'overall_prompt_count':
            _meanDouble(valid, (s) => s.promptCount.toDouble()),
        'overall_prompt_dependency_score': _meanPromptDependency(valid),
        'overall_idle_time_seconds':
            _meanDouble(valid, (s) => s.idleTimeSeconds),
        'overall_random_touch_count':
            _meanDouble(valid, (s) => s.randomTouchCount.toDouble()),
        'overall_turn_taking_success_rate':
            _meanTurnTakingSuccessRate(myTurnSessions),
        'overall_interruption_count':
            _meanDouble(valid, (s) => (s.interruptionCount ?? 0).toDouble()),
        'match_it_accuracy': _meanAccuracy(matchItSessions),
        'copy_me_accuracy': _meanAccuracy(copySessions),
        'do_what_i_say_accuracy': _meanAccuracy(doWhatISaySessions),
        'my_turn_your_turn_accuracy': _meanAccuracy(myTurnSessions),
        'match_it_avg_response_time':
            _meanDouble(matchItSessions, (s) => s.avgResponseTime),
        'copy_me_avg_response_time':
            _meanDouble(copySessions, (s) => s.avgResponseTime),
        'do_what_i_say_avg_response_time':
            _meanDouble(doWhatISaySessions, (s) => s.avgResponseTime),
        'my_turn_your_turn_avg_response_time':
            _meanDouble(myTurnSessions, (s) => s.avgResponseTime),

        // ── Target columns (6) ─────────────────────────────────────────
        'play_skills_label': rubricResult.playSkillsLabel.displayName,
        'communication_label': rubricResult.communicationLabel.displayName,
        'social_interaction_label':
            rubricResult.socialInteractionLabel.displayName,
        'behavior_attention_label':
            rubricResult.behaviorAttentionLabel.displayName,
        'sensory_preference_label':
            rubricResult.sensoryPreferenceLabel.displayName,
        'recommended_module': rubricResult.recommendedModule,
      };
    } catch (_) {
      // Return a row with safe defaults on any unexpected error.
      return _safeDefaultRow(childId, rubricResult);
    }
  }

  /// Generate multiple rows for batch export.
  ///
  /// [assessments] — A list of records, each containing a child ID,
  /// their gameplay sessions, and the corresponding rubric result.
  List<Map<String, dynamic>> generateBatch({
    required List<({String childId, List<GameplaySession> sessions, RubricResult result})>
        assessments,
  }) {
    return assessments
        .map((a) => generateRow(
              childId: a.childId,
              sessions: a.sessions,
              rubricResult: a.result,
            ))
        .toList();
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /// Filter sessions to a single game ID.
  List<GameplaySession> _filterByGameId(
    List<GameplaySession> sessions,
    String gameId,
  ) {
    return sessions.where((s) => s.gameId == gameId).toList();
  }

  /// Mean accuracy = mean of (score / totalItems) across sessions.
  /// Returns `0.0` if the list is empty.
  double _meanAccuracy(List<GameplaySession> sessions) {
    if (sessions.isEmpty) return 0.0;
    final sum = sessions.fold<double>(
      0.0,
      (acc, s) => acc + (s.score / s.totalItems).clamp(0.0, 1.0),
    );
    return sum / sessions.length;
  }

  /// Generic mean of a double extractor across sessions.
  /// Returns `0.0` if the list is empty.
  double _meanDouble(
    List<GameplaySession> sessions,
    double Function(GameplaySession) extractor,
  ) {
    if (sessions.isEmpty) return 0.0;
    final sum = sessions.fold<double>(0.0, (acc, s) => acc + extractor(s));
    return sum / sessions.length;
  }

  /// Mean task completion rate using [taskCompletionRate] if available,
  /// else falling back to count(score > 0) / total sessions.
  double _meanTaskCompletionRate(List<GameplaySession> sessions) {
    if (sessions.isEmpty) return 0.0;
    final sum = sessions.fold<double>(
      0.0,
      (acc, s) =>
          acc +
          (s.taskCompletionRate ?? (s.score / s.totalItems).clamp(0.0, 1.0)),
    );
    return sum / sessions.length;
  }

  /// Mean prompt dependency using [promptDependencyScore] if available,
  /// else falling back to (promptCount / max(totalItems, 1)).
  double _meanPromptDependency(List<GameplaySession> sessions) {
    if (sessions.isEmpty) return 0.0;
    final sum = sessions.fold<double>(
      0.0,
      (acc, s) =>
          acc +
          (s.promptDependencyScore ??
              (s.promptCount / math.max(s.totalItems, 1))),
    );
    return sum / sessions.length;
  }

  /// Mean turn-taking success rate using [turnTakingSuccessRate] if available,
  /// else falling back to accuracy. Returns `0.0` if no sessions.
  double _meanTurnTakingSuccessRate(List<GameplaySession> sessions) {
    if (sessions.isEmpty) return 0.0;
    final sum = sessions.fold<double>(
      0.0,
      (acc, s) =>
          acc +
          (s.turnTakingSuccessRate ??
              (s.score / s.totalItems).clamp(0.0, 1.0)),
    );
    return sum / sessions.length;
  }

  /// Produce a row with all-zero features and the rubric labels.
  Map<String, dynamic> _safeDefaultRow(
    String childId,
    RubricResult rubricResult,
  ) {
    return {
      'child_id': childId,
      'overall_accuracy': 0.0,
      'overall_avg_response_time': 0.0,
      'overall_task_completion_rate': 0.0,
      'overall_retry_count': 0.0,
      'overall_hint_count': 0.0,
      'overall_prompt_count': 0.0,
      'overall_prompt_dependency_score': 0.0,
      'overall_idle_time_seconds': 0.0,
      'overall_random_touch_count': 0.0,
      'overall_turn_taking_success_rate': 0.0,
      'overall_interruption_count': 0.0,
      'match_it_accuracy': 0.0,
      'copy_me_accuracy': 0.0,
      'do_what_i_say_accuracy': 0.0,
      'my_turn_your_turn_accuracy': 0.0,
      'match_it_avg_response_time': 0.0,
      'copy_me_avg_response_time': 0.0,
      'do_what_i_say_avg_response_time': 0.0,
      'my_turn_your_turn_avg_response_time': 0.0,
      'play_skills_label': rubricResult.playSkillsLabel.displayName,
      'communication_label': rubricResult.communicationLabel.displayName,
      'social_interaction_label':
          rubricResult.socialInteractionLabel.displayName,
      'behavior_attention_label':
          rubricResult.behaviorAttentionLabel.displayName,
      'sensory_preference_label':
          rubricResult.sensoryPreferenceLabel.displayName,
      'recommended_module': rubricResult.recommendedModule,
    };
  }
}
