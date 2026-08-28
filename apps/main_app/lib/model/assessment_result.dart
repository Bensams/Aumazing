/// The result of a single mini-game within a pre- or post-assessment.
class AssessmentResult {
  final String id;
  final String childId;

  /// The assessment run this result belongs to.
  final String? assessmentRunId;

  /// 'pre' or 'post'
  final String type;

  /// Game identifier: 'match_it', 'copy_me', 'do_what_i_say', 'my_turn_your_turn'
  final String gameId;

  final int score;
  final int totalItems;
  final int errorCount;

  /// Number of random/off-target touches (taps on non-interactive areas).
  final int randomTouchCount;

  /// Average response time in milliseconds across all items.
  final int avgResponseTimeMs;

  final DateTime completedAt;

  /// Optional bag of extra metrics (e.g. per-item breakdown).
  final Map<String, dynamic> rawMetrics;

  // ── Rubric scoring fields ────────────────────────────────────────────

  /// Rubric label for play skills: Strength, Emerging, or Needs Support.
  final String? playSkillsLabel;

  /// Rubric label for communication: Strength, Emerging, or Needs Support.
  final String? communicationLabel;

  /// Rubric label for social interaction: Strength, Emerging, or Needs Support.
  final String? socialInteractionLabel;

  /// Rubric label for behavior/attention.
  final String? behaviorAttentionLabel;

  /// Rubric label for sensory preference.
  final String? sensoryPreferenceLabel;

  /// Recommended module based on rubric scoring.
  final String? recommendedModule;

  /// Overall summary text from rubric scoring.
  final String? overallSummary;

  /// Source of assessment labels.
  ///
  /// - `'rubric_based'` — scored by the local rubric engine only.
  /// - `'xgboost'`      — scored/confirmed by the AI Assessment API (XGBoost model).
  final String? modelSource;

  /// Whether this row can be used for XGBoost training.
  final bool? xgboostReady;

  const AssessmentResult({
    required this.id,
    required this.childId,
    this.assessmentRunId,
    required this.type,
    required this.gameId,
    required this.score,
    required this.totalItems,
    required this.errorCount,
    this.randomTouchCount = 0,
    required this.avgResponseTimeMs,
    required this.completedAt,
    this.rawMetrics = const {},
    this.playSkillsLabel,
    this.communicationLabel,
    this.socialInteractionLabel,
    this.behaviorAttentionLabel,
    this.sensoryPreferenceLabel,
    this.recommendedModule,
    this.overallSummary,
    this.modelSource,
    this.xgboostReady,
  });

  double get accuracy =>
      totalItems > 0 ? (score / totalItems).clamp(0.0, 1.0) : 0.0;

  /// Accuracy adjusted for errors.
  ///
  /// Uses the formula `score / (score + errorCount)` so that errors
  /// penalise the result even when the game retries until correct
  /// (which makes [accuracy] always 1.0).
  ///
  /// Falls back to [accuracy] when there are no errors, and returns
  /// 0.0 when both score and errorCount are zero.
  double get adjustedAccuracy {
    final total = score + errorCount;
    if (total <= 0) return 0.0;
    return (score / total).clamp(0.0, 1.0);
  }

  /// Whether this result was assessed by the AI (XGBoost) model — either the
  /// cloud API (`'xgboost'`) or the on-device ONNX model (`'xgboost_onnx'`).
  bool get isAiAssessed =>
      modelSource == 'xgboost' || modelSource == 'xgboost_onnx';

  /// Whether this result was assessed by the on-device ONNX model.
  bool get isOnDeviceAssessed => modelSource == 'xgboost_onnx';

  /// Create a copy with updated rubric scoring fields.
  AssessmentResult copyWithRubric({
    String? playSkillsLabel,
    String? communicationLabel,
    String? socialInteractionLabel,
    String? behaviorAttentionLabel,
    String? sensoryPreferenceLabel,
    String? recommendedModule,
    String? overallSummary,
    String? modelSource,
    bool? xgboostReady,
  }) {
    return AssessmentResult(
      id: id,
      childId: childId,
      assessmentRunId: assessmentRunId,
      type: type,
      gameId: gameId,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      randomTouchCount: randomTouchCount,
      avgResponseTimeMs: avgResponseTimeMs,
      completedAt: completedAt,
      rawMetrics: rawMetrics,
      playSkillsLabel: playSkillsLabel ?? this.playSkillsLabel,
      communicationLabel: communicationLabel ?? this.communicationLabel,
      socialInteractionLabel: socialInteractionLabel ?? this.socialInteractionLabel,
      behaviorAttentionLabel: behaviorAttentionLabel ?? this.behaviorAttentionLabel,
      sensoryPreferenceLabel: sensoryPreferenceLabel ?? this.sensoryPreferenceLabel,
      recommendedModule: recommendedModule ?? this.recommendedModule,
      overallSummary: overallSummary ?? this.overallSummary,
      modelSource: modelSource ?? this.modelSource,
      xgboostReady: xgboostReady ?? this.xgboostReady,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'child_id': childId,
        'assessment_run_id': assessmentRunId,
        'type': type,
        'game_id': gameId,
        'score': score,
        'total_items': totalItems,
        'error_count': errorCount,
        'random_touch_count': randomTouchCount,
        'avg_response_time_ms': avgResponseTimeMs,
        'completed_at': completedAt.toIso8601String(),
        'raw_metrics': rawMetrics.toString(),
        'play_skills_label': playSkillsLabel,
        'communication_label': communicationLabel,
        'social_interaction_label': socialInteractionLabel,
        'behavior_attention_label': behaviorAttentionLabel,
        'sensory_preference_label': sensoryPreferenceLabel,
        'recommended_module': recommendedModule,
        'overall_summary': overallSummary,
        'model_source': modelSource,
        'xgboost_ready': xgboostReady == null
            ? null
            : (xgboostReady! ? 1 : 0),
      };

  factory AssessmentResult.fromMap(Map<String, dynamic> map) =>
      AssessmentResult(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        assessmentRunId: map['assessment_run_id'] as String?,
        type: map['type'] as String,
        gameId: map['game_id'] as String,
        score: map['score'] as int,
        totalItems: map['total_items'] as int,
        errorCount: map['error_count'] as int,
        randomTouchCount: (map['random_touch_count'] as int?) ?? 0,
        avgResponseTimeMs: map['avg_response_time_ms'] as int,
        completedAt: DateTime.parse(map['completed_at'] as String),
        playSkillsLabel: map['play_skills_label'] as String?,
        communicationLabel: map['communication_label'] as String?,
        socialInteractionLabel: map['social_interaction_label'] as String?,
        behaviorAttentionLabel: map['behavior_attention_label'] as String?,
        sensoryPreferenceLabel: map['sensory_preference_label'] as String?,
        recommendedModule: map['recommended_module'] as String?,
        overallSummary: map['overall_summary'] as String?,
        modelSource: map['model_source'] as String?,
        xgboostReady: map['xgboost_ready'] == null
            ? null
            : (map['xgboost_ready'] as int) == 1,
      );

  factory AssessmentResult.fromSupabase(Map<String, dynamic> map) =>
      AssessmentResult(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        assessmentRunId: map['assessment_run_id'] as String?,
        type: map['type'] as String,
        gameId: map['game_id'] as String,
        score: map['score'] as int,
        totalItems: map['total_items'] as int,
        errorCount: map['error_count'] as int,
        randomTouchCount: (map['random_touch_count'] as int?) ?? 0,
        avgResponseTimeMs: map['avg_response_time_ms'] as int,
        completedAt: DateTime.parse(map['completed_at'] as String),
        rawMetrics: (map['raw_metrics'] as Map<String, dynamic>?) ?? {},
        playSkillsLabel: map['play_skills_label'] as String?,
        communicationLabel: map['communication_label'] as String?,
        socialInteractionLabel: map['social_interaction_label'] as String?,
        behaviorAttentionLabel: map['behavior_attention_label'] as String?,
        sensoryPreferenceLabel: map['sensory_preference_label'] as String?,
        recommendedModule: map['recommended_module'] as String?,
        overallSummary: map['overall_summary'] as String?,
        modelSource: map['model_source'] as String?,
        xgboostReady: map['xgboost_ready'] as bool?,
      );

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'child_id': childId,
        'assessment_run_id': assessmentRunId,
        'type': type,
        'game_id': gameId,
        'score': score,
        'total_items': totalItems,
        'error_count': errorCount,
        'random_touch_count': randomTouchCount,
        'avg_response_time_ms': avgResponseTimeMs,
        'completed_at': completedAt.toIso8601String(),
        'raw_metrics': rawMetrics,
        'play_skills_label': playSkillsLabel,
        'communication_label': communicationLabel,
        'social_interaction_label': socialInteractionLabel,
        'behavior_attention_label': behaviorAttentionLabel,
        'sensory_preference_label': sensoryPreferenceLabel,
        'recommended_module': recommendedModule,
        'overall_summary': overallSummary,
        'model_source': modelSource,
        'xgboost_ready': xgboostReady,
      };
}
