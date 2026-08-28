import 'rubric_labels.dart';

/// A module recommendation produced by the [RecommendationService].
///
/// Contains the recommended module name, a parent-friendly explanation,
/// and sensory settings to apply during gameplay.
class ModuleRecommendation {
  /// The name of the recommended learning module.
  final String moduleName;

  /// A parent-friendly explanation of why this module was recommended.
  final String explanation;

  /// Sensory settings to apply (e.g. `{'music_enabled': true}`).
  final Map<String, dynamic> sensorySettings;

  /// Creates a const [ModuleRecommendation].
  const ModuleRecommendation({
    required this.moduleName,
    required this.explanation,
    this.sensorySettings = const {},
  });
}

/// Stateless service that maps rubric labels to module recommendations.
///
/// Uses a decision-table approach to select the most appropriate learning
/// module based on the child's rubric scores across all developmental areas.
class RecommendationService {
  /// Creates a const instance of [RecommendationService].
  const RecommendationService();

  // ── Module name constants ──────────────────────────────────────────────

  static const _advancedPractice = 'Advanced Practice Module';
  static const _mixedSupport = 'Mixed Support Module';
  static const _communicationStarter = 'Communication Starter Module';
  static const _turnTakingStarter = 'Turn-taking Starter Module';
  static const _playSkillsStarter = 'Play Skills Starter Module';
  static const _attentionSupport = 'Attention Support Module';
  static const _foundationSkills = 'Foundation Skills Module';

  /// Generate a module recommendation based on rubric labels.
  ///
  /// Evaluates all five rubric areas and selects the most appropriate
  /// learning module using a priority-ordered decision table.
  ModuleRecommendation recommend({
    required PerformanceLabel playSkills,
    required PerformanceLabel communication,
    required PerformanceLabel socialInteraction,
    required AttentionLabel behaviorAttention,
    required SensoryPreferenceLabel sensoryPreference,
  }) {
    final sensorySettings = _sensorySettingsFor(sensoryPreference);
    final needsSupportCount = _countNeedsSupport(
      playSkills: playSkills,
      communication: communication,
      socialInteraction: socialInteraction,
      behaviorAttention: behaviorAttention,
    );

    // 1. All areas are Strength / Sustained Attention.
    if (_allStrength(
      playSkills: playSkills,
      communication: communication,
      socialInteraction: socialInteraction,
      behaviorAttention: behaviorAttention,
    )) {
      return ModuleRecommendation(
        moduleName: _advancedPractice,
        explanation:
            'Your child showed strong performance across all areas. '
            'We recommend advanced activities to keep building skills.',
        sensorySettings: sensorySettings,
      );
    }

    // 2. Three or more areas need support.
    if (needsSupportCount >= 3) {
      return ModuleRecommendation(
        moduleName: _mixedSupport,
        explanation:
            'Your child would benefit from a variety of activities '
            'across multiple areas.',
        sensorySettings: sensorySettings,
      );
    }

    // 3. Communication needs support.
    if (communication == PerformanceLabel.needsSupport) {
      return ModuleRecommendation(
        moduleName: _communicationStarter,
        explanation:
            'We recommend starting with communication activities to '
            'build listening and responding skills.',
        sensorySettings: sensorySettings,
      );
    }

    // 4. Social Interaction needs support.
    if (socialInteraction == PerformanceLabel.needsSupport) {
      return ModuleRecommendation(
        moduleName: _turnTakingStarter,
        explanation:
            'We recommend turn-taking activities to practice social '
            'interaction skills.',
        sensorySettings: sensorySettings,
      );
    }

    // 5. Play Skills needs support.
    if (playSkills == PerformanceLabel.needsSupport) {
      return ModuleRecommendation(
        moduleName: _playSkillsStarter,
        explanation:
            'We recommend play-based activities to build matching and '
            'imitation skills.',
        sensorySettings: sensorySettings,
      );
    }

    // 6. Behavior/Attention needs support.
    if (behaviorAttention == AttentionLabel.needsAttentionSupport) {
      return ModuleRecommendation(
        moduleName: _attentionSupport,
        explanation:
            'We recommend activities designed to build focus and '
            'sustained attention.',
        sensorySettings: sensorySettings,
      );
    }

    // 7. Default — mostly Emerging.
    return ModuleRecommendation(
      moduleName: _foundationSkills,
      explanation:
          'Your child is developing well. We recommend foundation '
          'activities to strengthen emerging skills.',
      sensorySettings: sensorySettings,
    );
  }

  /// Generate a parent-friendly summary of the assessment results.
  ///
  /// Produces a concise, readable paragraph covering all five rubric areas,
  /// the recommended module, and a disclaimer.
  String generateSummary({
    required PerformanceLabel playSkills,
    required PerformanceLabel communication,
    required PerformanceLabel socialInteraction,
    required AttentionLabel behaviorAttention,
    required SensoryPreferenceLabel sensoryPreference,
    required String recommendedModule,
  }) {
    return 'Play Skills: ${playSkills.displayName}. '
        'Communication: ${communication.displayName}. '
        'Social Interaction: ${socialInteraction.displayName}. '
        'Attention: ${behaviorAttention.displayName}. '
        'Sensory: ${sensoryPreference.displayName}. '
        'Recommended: $recommendedModule. '
        'This result is based on game performance only and is not a '
        'medical diagnosis. It is used to recommend suitable learning '
        'activities.';
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /// Returns `true` if all four areas are at their highest level.
  bool _allStrength({
    required PerformanceLabel playSkills,
    required PerformanceLabel communication,
    required PerformanceLabel socialInteraction,
    required AttentionLabel behaviorAttention,
  }) {
    return playSkills == PerformanceLabel.strength &&
        communication == PerformanceLabel.strength &&
        socialInteraction == PerformanceLabel.strength &&
        behaviorAttention == AttentionLabel.sustainedAttention;
  }

  /// Count how many areas are at the "needs support" level.
  int _countNeedsSupport({
    required PerformanceLabel playSkills,
    required PerformanceLabel communication,
    required PerformanceLabel socialInteraction,
    required AttentionLabel behaviorAttention,
  }) {
    int count = 0;
    if (playSkills == PerformanceLabel.needsSupport) count++;
    if (communication == PerformanceLabel.needsSupport) count++;
    if (socialInteraction == PerformanceLabel.needsSupport) count++;
    if (behaviorAttention == AttentionLabel.needsAttentionSupport) count++;
    return count;
  }

  /// Map a [SensoryPreferenceLabel] to the corresponding sensory settings.
  Map<String, dynamic> _sensorySettingsFor(SensoryPreferenceLabel label) {
    switch (label) {
      case SensoryPreferenceLabel.musicHelps:
        return {'music_enabled': true, 'music_volume': 0.5};
      case SensoryPreferenceLabel.hapticHelps:
        return {'haptic_enabled': true};
      case SensoryPreferenceLabel.musicAndHapticHelp:
        return {
          'music_enabled': true,
          'music_volume': 0.5,
          'haptic_enabled': true,
        };
      case SensoryPreferenceLabel.avoidMusic:
        return {'music_enabled': false};
      case SensoryPreferenceLabel.avoidHaptic:
        return {'haptic_enabled': false};
      case SensoryPreferenceLabel.noSensorySupportNeeded:
        return {};
    }
  }
}
