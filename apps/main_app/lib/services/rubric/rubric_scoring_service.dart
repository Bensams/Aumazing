import 'dart:math' as math;

import 'rubric_labels.dart';
import 'rubric_result.dart';
import '../../model/gameplay_session.dart';

/// Stateless service that converts telemetry data into rubric labels.
///
/// This is the core scoring engine for the pre-assessment rubric system.
/// It takes raw [GameplaySession] data and produces categorical labels
/// for each developmental area, which are later used for module
/// recommendations and XGBoost training data.
class RubricScoringService {
  /// Creates a const instance of [RubricScoringService].
  const RubricScoringService();

  // ── Game ID constants ──────────────────────────────────────────────────

  static const _matchIt = 'match_it';
  static const _copyMe = 'copy_me';
  static const _doWhatISay = 'do_what_i_say';
  static const _myTurnYourTurn = 'my_turn_your_turn';

  // ── Thresholds ─────────────────────────────────────────────────────────

  static const _strengthAccuracy = 0.80;
  static const _emergingAccuracy = 0.50;
  static const _strengthCompletionRate = 0.80;
  static const _emergingCompletionRate = 0.50;
  static const _strengthMaxPrompts = 1.0;
  static const _strengthMaxRetries = 2.0;
  static const _promptDependencyThreshold = 0.5;
  static const _strengthTurnTaking = 0.80;
  static const _emergingTurnTaking = 0.50;
  static const _strengthMaxInterruptions = 2;
  static const _needsSupportInterruptions = 5;
  static const _sustainedMaxIdle = 5.0;
  static const _sustainedMaxRandomTouch = 2.0;
  static const _sustainedMinCompletion = 0.80;
  static const _variableMaxIdle = 15.0;
  static const _variableMaxRandomTouch = 5.0;
  static const _variableMinCompletion = 0.50;

  /// Main entry point: takes all game sessions from a pre-assessment
  /// and returns a complete [RubricResult].
  ///
  /// [sessions] — All [GameplaySession] objects from the pre-assessment run.
  /// [sensoryLabel] — Pre-computed sensory preference label (from [SensoryLabelAnalyzer]).
  /// [recommendedModule] — Pre-computed recommendation (from [RecommendationService]).
  /// [overallSummary] — Pre-computed summary text.
  RubricResult scoreAll({
    required List<GameplaySession> sessions,
    required SensoryPreferenceLabel sensoryLabel,
    required String recommendedModule,
    required String overallSummary,
  }) {
    try {
      return RubricResult(
        playSkillsLabel: scorePlaySkills(sessions),
        communicationLabel: scoreCommunication(sessions),
        socialInteractionLabel: scoreSocialInteraction(sessions),
        behaviorAttentionLabel: scoreBehaviorAttention(sessions),
        sensoryPreferenceLabel: sensoryLabel,
        recommendedModule: recommendedModule,
        overallSummary: overallSummary,
      );
    } catch (_) {
      // Return safe defaults on any unexpected error.
      return RubricResult(
        playSkillsLabel: PerformanceLabel.emerging,
        communicationLabel: PerformanceLabel.emerging,
        socialInteractionLabel: PerformanceLabel.emerging,
        behaviorAttentionLabel: AttentionLabel.variableAttention,
        sensoryPreferenceLabel: sensoryLabel,
        recommendedModule: recommendedModule,
        overallSummary: overallSummary,
      );
    }
  }

  /// Score the **Play Skills** area.
  ///
  /// Games: `match_it`, `copy_me`.
  ///
  /// - **Strength**: accuracy ≥ 0.80 AND completion ≥ 0.80 AND prompts ≤ 1 AND retries ≤ 2
  /// - **Emerging**: accuracy ≥ 0.50 OR completion ≥ 0.50
  /// - **Needs Support**: everything else
  PerformanceLabel scorePlaySkills(List<GameplaySession> sessions) {
    try {
      final filtered = _filterByGameIds(sessions, [_matchIt, _copyMe]);
      final valid = _removeZeroTotalItems(filtered);

      if (valid.isEmpty) return PerformanceLabel.emerging;

      final avgAccuracy = _meanAccuracy(valid);
      final avgCompletionRate = _meanCompletionRate(valid);
      final avgPromptCount = _meanDouble(valid, (s) => s.promptCount.toDouble());
      final avgRetryCount = _meanDouble(valid, (s) => s.retryCount.toDouble());

      if (avgAccuracy >= _strengthAccuracy &&
          avgCompletionRate >= _strengthCompletionRate &&
          avgPromptCount <= _strengthMaxPrompts &&
          avgRetryCount <= _strengthMaxRetries) {
        return PerformanceLabel.strength;
      }

      if (avgAccuracy >= _emergingAccuracy ||
          avgCompletionRate >= _emergingCompletionRate) {
        return PerformanceLabel.emerging;
      }

      return PerformanceLabel.needsSupport;
    } catch (_) {
      return PerformanceLabel.emerging;
    }
  }

  /// Score the **Communication** area.
  ///
  /// Games: `copy_me`, `do_what_i_say`.
  ///
  /// - **Strength**: accuracy ≥ 0.80 AND avg prompts ≤ 1
  /// - **Emerging**: accuracy ≥ 0.50 AND < 0.80, OR prompt dependency < 0.5
  /// - **Needs Support**: accuracy < 0.50 OR prompt dependency ≥ 0.5
  PerformanceLabel scoreCommunication(List<GameplaySession> sessions) {
    try {
      final filtered = _filterByGameIds(sessions, [_copyMe, _doWhatISay]);
      final valid = _removeZeroTotalItems(filtered);

      if (valid.isEmpty) return PerformanceLabel.emerging;

      final avgAccuracy = _meanAccuracy(valid);
      final avgPromptCount = _meanDouble(valid, (s) => s.promptCount.toDouble());
      final avgPromptDependency = _meanPromptDependency(valid);

      if (avgAccuracy >= _strengthAccuracy &&
          avgPromptCount <= _strengthMaxPrompts) {
        return PerformanceLabel.strength;
      }

      if (avgAccuracy < _emergingAccuracy ||
          avgPromptDependency >= _promptDependencyThreshold) {
        return PerformanceLabel.needsSupport;
      }

      // Emerging: accuracy >= 0.50 and < 0.80, or responds after prompts
      return PerformanceLabel.emerging;
    } catch (_) {
      return PerformanceLabel.emerging;
    }
  }

  /// Score the **Social Interaction** area.
  ///
  /// Games: `my_turn_your_turn`.
  ///
  /// - **Strength**: turn-taking success ≥ 0.80 AND interruptions ≤ 2
  /// - **Emerging**: turn-taking success ≥ 0.50 AND < 0.80
  /// - **Needs Support**: turn-taking success < 0.50 OR interruptions > 5
  PerformanceLabel scoreSocialInteraction(List<GameplaySession> sessions) {
    try {
      final filtered = _filterByGameIds(sessions, [_myTurnYourTurn]);
      final valid = _removeZeroTotalItems(filtered);

      if (valid.isEmpty) return PerformanceLabel.emerging;

      final avgTurnTaking = _meanTurnTakingSuccessRate(valid);
      final avgInterruptions = _meanInt(valid, (s) => s.interruptionCount ?? 0);

      if (avgTurnTaking >= _strengthTurnTaking &&
          avgInterruptions <= _strengthMaxInterruptions) {
        return PerformanceLabel.strength;
      }

      if (avgTurnTaking < _emergingTurnTaking ||
          avgInterruptions > _needsSupportInterruptions) {
        return PerformanceLabel.needsSupport;
      }

      return PerformanceLabel.emerging;
    } catch (_) {
      return PerformanceLabel.emerging;
    }
  }

  /// Score the **Behavior/Attention** area.
  ///
  /// Uses ALL game sessions.
  ///
  /// - **Sustained Attention**: idle ≤ 5s AND random touch ≤ 2 AND completion ≥ 0.80
  /// - **Variable Attention**: idle ≤ 15s AND random touch ≤ 5 AND completion ≥ 0.50
  /// - **Needs Attention Support**: everything else
  AttentionLabel scoreBehaviorAttention(List<GameplaySession> sessions) {
    try {
      final valid = _removeZeroTotalItems(sessions);

      if (valid.isEmpty) return AttentionLabel.variableAttention;

      final avgIdle = _meanDouble(valid, (s) => s.idleTimeSeconds);
      final avgRandomTouch =
          _meanDouble(valid, (s) => s.randomTouchCount.toDouble());
      final avgCompletionRate = _meanCompletionRate(valid);

      if (avgIdle <= _sustainedMaxIdle &&
          avgRandomTouch <= _sustainedMaxRandomTouch &&
          avgCompletionRate >= _sustainedMinCompletion) {
        return AttentionLabel.sustainedAttention;
      }

      if (avgIdle <= _variableMaxIdle &&
          avgRandomTouch <= _variableMaxRandomTouch &&
          avgCompletionRate >= _variableMinCompletion) {
        return AttentionLabel.variableAttention;
      }

      return AttentionLabel.needsAttentionSupport;
    } catch (_) {
      return AttentionLabel.variableAttention;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /// Filter sessions to only those matching the given game IDs.
  List<GameplaySession> _filterByGameIds(
    List<GameplaySession> sessions,
    List<String> gameIds,
  ) {
    return sessions.where((s) => gameIds.contains(s.gameId)).toList();
  }

  /// Remove sessions where [totalItems] is 0 (cannot compute accuracy).
  List<GameplaySession> _removeZeroTotalItems(List<GameplaySession> sessions) {
    return sessions.where((s) => s.totalItems > 0).toList();
  }

  /// Mean accuracy = mean of (score / totalItems) across sessions.
  double _meanAccuracy(List<GameplaySession> sessions) {
    if (sessions.isEmpty) return 0.0;
    final sum = sessions.fold<double>(
      0.0,
      (acc, s) => acc + (s.score / s.totalItems).clamp(0.0, 1.0),
    );
    return sum / sessions.length;
  }

  /// Mean completion rate using [taskCompletionRate] if available,
  /// else falling back to (score / totalItems).
  double _meanCompletionRate(List<GameplaySession> sessions) {
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
  /// else falling back to accuracy.
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

  /// Generic mean of a double extractor across sessions.
  double _meanDouble(
    List<GameplaySession> sessions,
    double Function(GameplaySession) extractor,
  ) {
    if (sessions.isEmpty) return 0.0;
    final sum = sessions.fold<double>(0.0, (acc, s) => acc + extractor(s));
    return sum / sessions.length;
  }

  /// Generic mean of an int extractor across sessions (returns double).
  double _meanInt(
    List<GameplaySession> sessions,
    int Function(GameplaySession) extractor,
  ) {
    if (sessions.isEmpty) return 0.0;
    final sum = sessions.fold<int>(0, (acc, s) => acc + extractor(s));
    return sum / sessions.length;
  }
}
