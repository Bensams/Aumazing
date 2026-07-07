import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/services/rubric/rubric_labels.dart';
import 'package:aumazing/services/rubric/rubric_scoring_service.dart';
import 'package:aumazing/services/rubric/rubric_thresholds.dart';

GameplaySession _session({
  required String gameId,
  required double accuracy,
  double? completion,
  double promptDependency = 0.0,
  double? turnTaking,
  double idleSeconds = 0.0,
}) {
  const totalItems = 10;
  return GameplaySession(
    id: 'test-$gameId',
    childId: 'child-1',
    gameId: gameId,
    context: 'pre_assessment',
    score: (accuracy * totalItems).round(),
    totalItems: totalItems,
    errorCount: 0,
    totalResponseTimeMs: 5000,
    idleTimeSeconds: idleSeconds,
    taskCompletionRate: completion ?? accuracy,
    promptDependencyScore: promptDependency,
    turnTakingSuccessRate: turnTaking,
    startedAt: DateTime(2026, 7, 4, 10),
    endedAt: DateTime(2026, 7, 4, 10, 5),
  );
}

void main() {
  group('RubricThresholds round-trip', () {
    test('fromMap/toMap preserve values; missing keys fall back', () {
      const original = RubricThresholds(
        strengthAccuracy: 0.9,
        emergingAccuracy: 0.6,
        sustainedMaxIdleSeconds: 3.0,
      );
      final restored = RubricThresholds.fromMap(original.toMap());
      expect(restored.strengthAccuracy, 0.9);
      expect(restored.emergingAccuracy, 0.6);
      expect(restored.sustainedMaxIdleSeconds, 3.0);

      final sparse = RubricThresholds.fromMap(const {});
      expect(sparse.strengthAccuracy, RubricThresholds.defaults.strengthAccuracy);
    });
  });

  group('admin-configured thresholds change scoring labels', () {
    // 70% accuracy sits between the default Emerging (50%) and
    // Strength (80%) cutoffs.
    final playSessions = [
      _session(gameId: 'match_it', accuracy: 0.7),
      _session(gameId: 'copy_me', accuracy: 0.7),
    ];

    test('defaults: 70% accuracy is Emerging', () {
      const scorer = RubricScoringService(thresholds: RubricThresholds());
      expect(scorer.scorePlaySkills(playSessions), PerformanceLabel.emerging);
    });

    test('lowering the Strength cutoff promotes the same child', () {
      const scorer = RubricScoringService(
        thresholds: RubricThresholds(
          strengthAccuracy: 0.65,
          strengthCompletion: 0.65,
        ),
      );
      expect(scorer.scorePlaySkills(playSessions), PerformanceLabel.strength);
    });

    test('raising the Emerging floor demotes the same child', () {
      const scorer = RubricScoringService(
        thresholds: RubricThresholds(
          emergingAccuracy: 0.75,
          emergingCompletion: 0.75,
        ),
      );
      expect(
          scorer.scorePlaySkills(playSessions), PerformanceLabel.needsSupport);
    });

    test('turn-taking cutoffs govern social interaction', () {
      final social = [
        _session(gameId: 'my_turn_your_turn', accuracy: 0.7, turnTaking: 0.7),
      ];
      const defaults = RubricScoringService(thresholds: RubricThresholds());
      expect(defaults.scoreSocialInteraction(social),
          PerformanceLabel.emerging);

      const lenient = RubricScoringService(
        thresholds: RubricThresholds(strengthTurnTaking: 0.65),
      );
      expect(
          lenient.scoreSocialInteraction(social), PerformanceLabel.strength);
    });

    test('idle cutoffs govern the attention label', () {
      final sessions = [
        _session(gameId: 'match_it', accuracy: 0.9, idleSeconds: 8.0),
      ];
      const defaults = RubricScoringService(thresholds: RubricThresholds());
      // 8s idle exceeds the 5s sustained cutoff → Variable.
      expect(defaults.scoreBehaviorAttention(sessions),
          AttentionLabel.variableAttention);

      const relaxed = RubricScoringService(
        thresholds: RubricThresholds(sustainedMaxIdleSeconds: 10.0),
      );
      expect(relaxed.scoreBehaviorAttention(sessions),
          AttentionLabel.sustainedAttention);
    });
  });
}
