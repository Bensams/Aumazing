import '../model/ai_assessment_response.dart';
import '../model/support_profile.dart';
import 'rubric/rubric.dart';

/// Builds the [SupportProfile] that is finalized with an assessment run.
///
/// The Developmental Profile labels (communication, social interaction, play
/// skills, attention, sensory) always come from the [RubricResult] produced
/// by [RubricScoringService], so rubric scoring stays the single source of
/// truth for the profile.
///
/// Recommendations come from the AI response when one is available and from
/// the rubric labels otherwise. The result is stored with the run — the
/// review screen reads it back rather than recomputing it, so changing the
/// child's sensory settings later cannot rewrite a past assessment.
abstract final class SupportProfileBuilder {
  static SupportProfile build({
    required RubricResult? rubric,
    required AiAssessmentResponse? aiResponse,
  }) {
    final String communication;
    final String socialInteraction;
    final String playSkills;
    final String attention;
    final List<String> sensoryNotes;

    if (rubric != null) {
      communication = mapPerformanceLabel(rubric.communicationLabel);
      socialInteraction = mapPerformanceLabel(rubric.socialInteractionLabel);
      playSkills = mapPerformanceLabel(rubric.playSkillsLabel);
      attention = mapAttentionLabel(rubric.behaviorAttentionLabel);
      sensoryNotes = [rubric.sensoryPreferenceLabel.displayName];
    } else {
      // Rubric not available — neutral defaults.
      communication = 'emerging';
      socialInteraction = 'emerging';
      playSkills = 'emerging';
      attention = 'moderate';
      sensoryNotes = const [];
    }

    if (aiResponse != null) {
      final predicted = aiResponse.predictedProfile;
      final support = aiResponse.supportLevel;
      return SupportProfile(
        communication: communication,
        socialInteraction: socialInteraction,
        playSkills: playSkills,
        attention: attention,
        sensoryNotes: sensoryNotes,
        recommendedDifficulty:
            support == 'high'
                ? 'beginner'
                : support == 'moderate'
                ? 'intermediate'
                : 'advanced',
        recommendedPromptStyle:
            support == 'high'
                ? 'visual'
                : support == 'moderate'
                ? 'combined'
                : 'verbal',
        recommendedSessionMinutes:
            support == 'high'
                ? 3
                : support == 'moderate'
                ? 5
                : 7,
        lowStimulationMode: predicted == 'attention_support',
        turnTakingPractice: predicted == 'social_support',
        promptRepetition:
            support == 'high'
                ? 3
                : support == 'moderate'
                ? 2
                : 1,
      );
    }

    // Fallback: derive recommendations from the rubric labels.
    final emergingCount =
        [
          communication,
          socialInteraction,
          playSkills,
        ].where((l) => l == 'emerging').length;
    final strongCount =
        [
          communication,
          socialInteraction,
          playSkills,
        ].where((l) => l == 'strong').length;

    final String difficulty;
    if (strongCount >= 2) {
      difficulty = 'advanced';
    } else if (emergingCount >= 2) {
      difficulty = 'beginner';
    } else {
      difficulty = 'intermediate';
    }

    return SupportProfile(
      communication: communication,
      socialInteraction: socialInteraction,
      playSkills: playSkills,
      attention: attention,
      sensoryNotes: sensoryNotes,
      recommendedDifficulty: difficulty,
      recommendedPromptStyle: 'combined',
      recommendedSessionMinutes: attention == 'short attention' ? 3 : 5,
      lowStimulationMode: attention == 'short attention',
      turnTakingPractice: socialInteraction == 'emerging',
      promptRepetition:
          emergingCount >= 2
              ? 3
              : emergingCount >= 1
              ? 2
              : 1,
    );
  }

  /// Maps a [PerformanceLabel] to the string used by [SupportProfile].
  static String mapPerformanceLabel(PerformanceLabel label) {
    switch (label) {
      case PerformanceLabel.strength:
        return 'strong';
      case PerformanceLabel.emerging:
        return 'good';
      case PerformanceLabel.needsSupport:
        return 'emerging';
    }
  }

  /// Maps an [AttentionLabel] to the string used by [SupportProfile].
  static String mapAttentionLabel(AttentionLabel label) {
    switch (label) {
      case AttentionLabel.sustainedAttention:
        return 'sustained';
      case AttentionLabel.variableAttention:
        return 'moderate';
      case AttentionLabel.needsAttentionSupport:
        return 'short attention';
    }
  }
}
