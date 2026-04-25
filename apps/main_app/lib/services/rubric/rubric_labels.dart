/// Performance labels for Play Skills, Communication, Social Interaction.
enum PerformanceLabel {
  strength('Strength'),
  emerging('Emerging'),
  needsSupport('Needs Support');

  const PerformanceLabel(this.displayName);
  final String displayName;
}

/// Behavior/Attention labels.
enum AttentionLabel {
  sustainedAttention('Sustained Attention'),
  variableAttention('Variable Attention'),
  needsAttentionSupport('Needs Attention Support');

  const AttentionLabel(this.displayName);
  final String displayName;
}

/// Sensory Preference labels.
enum SensoryPreferenceLabel {
  musicHelps('Music Helps'),
  hapticHelps('Haptic Helps'),
  musicAndHapticHelp('Music and Haptic Help'),
  noSensorySupportNeeded('No Sensory Support Needed'),
  avoidMusic('Avoid Music'),
  avoidHaptic('Avoid Haptic');

  const SensoryPreferenceLabel(this.displayName);
  final String displayName;
}
