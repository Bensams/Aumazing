/// Rubric scoring cutoffs used to assign Strength / Emerging / Needs
/// Support labels.
///
/// The defaults mirror the values validated during rubric design; the
/// administrator can adjust them from the web portal (rubric_thresholds
/// table), and [RubricThresholdService] delivers the current values to
/// the scoring engine.
class RubricThresholds {
  const RubricThresholds({
    this.strengthAccuracy = 0.80,
    this.emergingAccuracy = 0.50,
    this.strengthCompletion = 0.80,
    this.emergingCompletion = 0.50,
    this.strengthMaxPromptDependency = 0.20,
    this.strengthTurnTaking = 0.80,
    this.emergingTurnTaking = 0.50,
    this.sustainedMaxIdleSeconds = 5.0,
    this.variableMaxIdleSeconds = 15.0,
  });

  final double strengthAccuracy;
  final double emergingAccuracy;
  final double strengthCompletion;
  final double emergingCompletion;
  final double strengthMaxPromptDependency;
  final double strengthTurnTaking;
  final double emergingTurnTaking;
  final double sustainedMaxIdleSeconds;
  final double variableMaxIdleSeconds;

  /// The validated defaults (also the offline fallback).
  static const RubricThresholds defaults = RubricThresholds();

  factory RubricThresholds.fromMap(Map<String, dynamic> map) {
    double read(String key, double fallback) =>
        (map[key] as num?)?.toDouble() ?? fallback;
    return RubricThresholds(
      strengthAccuracy: read('strength_accuracy', 0.80),
      emergingAccuracy: read('emerging_accuracy', 0.50),
      strengthCompletion: read('strength_completion', 0.80),
      emergingCompletion: read('emerging_completion', 0.50),
      strengthMaxPromptDependency:
          read('strength_max_prompt_dependency', 0.20),
      strengthTurnTaking: read('strength_turn_taking', 0.80),
      emergingTurnTaking: read('emerging_turn_taking', 0.50),
      sustainedMaxIdleSeconds: read('sustained_max_idle_seconds', 5.0),
      variableMaxIdleSeconds: read('variable_max_idle_seconds', 15.0),
    );
  }

  Map<String, dynamic> toMap() => {
        'strength_accuracy': strengthAccuracy,
        'emerging_accuracy': emergingAccuracy,
        'strength_completion': strengthCompletion,
        'emerging_completion': emergingCompletion,
        'strength_max_prompt_dependency': strengthMaxPromptDependency,
        'strength_turn_taking': strengthTurnTaking,
        'emerging_turn_taking': emergingTurnTaking,
        'sustained_max_idle_seconds': sustainedMaxIdleSeconds,
        'variable_max_idle_seconds': variableMaxIdleSeconds,
      };
}
