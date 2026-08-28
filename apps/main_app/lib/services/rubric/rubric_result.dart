import 'rubric_labels.dart';

/// Holds the rubric-based scoring result for a pre-assessment session.
class RubricResult {
  final PerformanceLabel playSkillsLabel;
  final PerformanceLabel communicationLabel;
  final PerformanceLabel socialInteractionLabel;
  final AttentionLabel behaviorAttentionLabel;
  final SensoryPreferenceLabel sensoryPreferenceLabel;
  final String recommendedModule;
  final String overallSummary;
  final String modelSource; // 'rubric_based'
  final bool xgboostReady;

  const RubricResult({
    required this.playSkillsLabel,
    required this.communicationLabel,
    required this.socialInteractionLabel,
    required this.behaviorAttentionLabel,
    required this.sensoryPreferenceLabel,
    required this.recommendedModule,
    required this.overallSummary,
    this.modelSource = 'rubric_based',
    this.xgboostReady = true,
  });

  /// Convert to map for database storage.
  Map<String, dynamic> toMap() => {
        'play_skills_label': playSkillsLabel.displayName,
        'communication_label': communicationLabel.displayName,
        'social_interaction_label': socialInteractionLabel.displayName,
        'behavior_attention_label': behaviorAttentionLabel.displayName,
        'sensory_preference_label': sensoryPreferenceLabel.displayName,
        'recommended_module': recommendedModule,
        'overall_summary': overallSummary,
        'model_source': modelSource,
        'xgboost_ready': xgboostReady ? 1 : 0,
      };

  /// Create from database map.
  factory RubricResult.fromMap(Map<String, dynamic> map) {
    return RubricResult(
      playSkillsLabel: PerformanceLabel.values.firstWhere(
        (e) => e.displayName == map['play_skills_label'],
        orElse: () => PerformanceLabel.emerging,
      ),
      communicationLabel: PerformanceLabel.values.firstWhere(
        (e) => e.displayName == map['communication_label'],
        orElse: () => PerformanceLabel.emerging,
      ),
      socialInteractionLabel: PerformanceLabel.values.firstWhere(
        (e) => e.displayName == map['social_interaction_label'],
        orElse: () => PerformanceLabel.emerging,
      ),
      behaviorAttentionLabel: AttentionLabel.values.firstWhere(
        (e) => e.displayName == map['behavior_attention_label'],
        orElse: () => AttentionLabel.variableAttention,
      ),
      sensoryPreferenceLabel: SensoryPreferenceLabel.values.firstWhere(
        (e) => e.displayName == map['sensory_preference_label'],
        orElse: () => SensoryPreferenceLabel.noSensorySupportNeeded,
      ),
      recommendedModule: map['recommended_module'] as String? ?? '',
      overallSummary: map['overall_summary'] as String? ?? '',
      modelSource: map['model_source'] as String? ?? 'rubric_based',
      xgboostReady: (map['xgboost_ready'] as int?) == 1,
    );
  }
}
