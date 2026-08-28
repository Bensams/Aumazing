/// Developmental support profile generated after a pre-assessment.
///
/// Not a clinical diagnosis — a simple, parent-friendly summary of the
/// child's current abilities and recommended settings.
class SupportProfile {
  /// One of 'emerging', 'developing', 'strong' for each area.
  final String communication;
  final String socialInteraction;
  final String playSkills;
  final String attention;

  /// Sensory preference notes, e.g. 'low sound', 'no vibration'.
  final List<String> sensoryNotes;

  /// Recommended difficulty: 'beginner', 'intermediate', 'advanced'.
  final String recommendedDifficulty;

  /// Recommended prompt style: 'visual', 'combined', 'verbal'.
  final String recommendedPromptStyle;

  /// Recommended session length in minutes.
  final int recommendedSessionMinutes;

  /// Whether low-stimulation mode is recommended.
  final bool lowStimulationMode;

  /// Whether extra turn-taking practice is recommended.
  final bool turnTakingPractice;

  /// Recommended prompt repetition: 1–3.
  final int promptRepetition;

  const SupportProfile({
    required this.communication,
    required this.socialInteraction,
    required this.playSkills,
    required this.attention,
    this.sensoryNotes = const [],
    this.recommendedDifficulty = 'beginner',
    this.recommendedPromptStyle = 'combined',
    this.recommendedSessionMinutes = 5,
    this.lowStimulationMode = false,
    this.turnTakingPractice = false,
    this.promptRepetition = 1,
  });

  Map<String, dynamic> toMap() => {
        'communication': communication,
        'social_interaction': socialInteraction,
        'play_skills': playSkills,
        'attention': attention,
        'sensory_notes': sensoryNotes,
        'recommended_difficulty': recommendedDifficulty,
        'recommended_prompt_style': recommendedPromptStyle,
        'recommended_session_minutes': recommendedSessionMinutes,
        'low_stimulation_mode': lowStimulationMode,
        'turn_taking_practice': turnTakingPractice,
        'prompt_repetition': promptRepetition,
      };

  factory SupportProfile.fromMap(Map<String, dynamic> m) => SupportProfile(
        communication: m['communication'] as String? ?? 'emerging',
        socialInteraction: m['social_interaction'] as String? ?? 'emerging',
        playSkills: m['play_skills'] as String? ?? 'emerging',
        attention: m['attention'] as String? ?? 'short attention',
        sensoryNotes: List<String>.from(m['sensory_notes'] ?? []),
        recommendedDifficulty:
            m['recommended_difficulty'] as String? ?? 'beginner',
        recommendedPromptStyle:
            m['recommended_prompt_style'] as String? ?? 'combined',
        recommendedSessionMinutes:
            m['recommended_session_minutes'] as int? ?? 5,
        lowStimulationMode: m['low_stimulation_mode'] as bool? ?? false,
        turnTakingPractice: m['turn_taking_practice'] as bool? ?? false,
        promptRepetition: m['prompt_repetition'] as int? ?? 1,
      );
}
