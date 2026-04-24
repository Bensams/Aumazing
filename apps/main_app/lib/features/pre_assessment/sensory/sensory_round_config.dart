/// Purpose/type of each sensory round during pre-assessment.
enum SensoryRoundPurpose {
  musicOnly, // Round 1: BG music ON, haptic OFF
  hapticOnly, // Round 2: BG music OFF, haptic ON
  baseline, // Round 3: Both OFF (baseline)
  combined, // Round 4: Both ON
  attention, // Round 5: Attention/behavior observation
}

/// Immutable configuration for a single sensory round.
///
/// Each round in the pre-assessment toggles background music and haptic
/// feedback to discover the child's optimal sensory preferences.
class SensoryRoundConfig {
  /// Round number (1-5).
  final int roundNumber;

  /// Whether background music is enabled for this round.
  final bool musicEnabled;

  /// Whether haptic feedback is enabled for this round.
  final bool hapticEnabled;

  /// The purpose/type of this round.
  final SensoryRoundPurpose purpose;

  /// Human-readable label for display.
  final String label;

  const SensoryRoundConfig({
    required this.roundNumber,
    required this.musicEnabled,
    required this.hapticEnabled,
    required this.purpose,
    required this.label,
  });

  // ── Predefined round configurations ───────────────────────────────────

  static const round1 = SensoryRoundConfig(
    roundNumber: 1,
    musicEnabled: true,
    hapticEnabled: false,
    purpose: SensoryRoundPurpose.musicOnly,
    label: 'Music Only',
  );

  static const round2 = SensoryRoundConfig(
    roundNumber: 2,
    musicEnabled: false,
    hapticEnabled: true,
    purpose: SensoryRoundPurpose.hapticOnly,
    label: 'Haptic Only',
  );

  static const round3 = SensoryRoundConfig(
    roundNumber: 3,
    musicEnabled: false,
    hapticEnabled: false,
    purpose: SensoryRoundPurpose.baseline,
    label: 'Baseline',
  );

  static const round4 = SensoryRoundConfig(
    roundNumber: 4,
    musicEnabled: true,
    hapticEnabled: true,
    purpose: SensoryRoundPurpose.combined,
    label: 'Combined',
  );

  static const round5 = SensoryRoundConfig(
    roundNumber: 5,
    musicEnabled: false, // OFF for pure attention observation
    hapticEnabled: false, // OFF for pure attention observation
    purpose: SensoryRoundPurpose.attention,
    label: 'Attention',
  );

  /// The standard 5-round pre-assessment sequence.
  static const List<SensoryRoundConfig> preAssessmentRounds = [
    round1,
    round2,
    round3,
    round4,
    round5,
  ];

  /// Create a "parent-declined" config that uses the parent's current
  /// settings for all rounds (no sensory toggling).
  static List<SensoryRoundConfig> parentDeclinedRounds({
    required bool musicEnabled,
    required bool hapticEnabled,
  }) {
    return List.generate(
      5,
      (i) => SensoryRoundConfig(
        roundNumber: i + 1,
        musicEnabled: musicEnabled,
        hapticEnabled: hapticEnabled,
        purpose: i == 4
            ? SensoryRoundPurpose.attention
            : SensoryRoundPurpose.baseline,
        label: 'Parent Settings',
      ),
    );
  }

  // ── Serialization ─────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'round_number': roundNumber,
        'music_enabled': musicEnabled ? 1 : 0,
        'haptic_enabled': hapticEnabled ? 1 : 0,
        'purpose': purpose.name,
        'label': label,
      };

  factory SensoryRoundConfig.fromMap(Map<String, dynamic> map) =>
      SensoryRoundConfig(
        roundNumber: map['round_number'] as int,
        musicEnabled: (map['music_enabled'] as int) == 1,
        hapticEnabled: (map['haptic_enabled'] as int) == 1,
        purpose: SensoryRoundPurpose.values.firstWhere(
          (e) => e.name == map['purpose'],
          orElse: () => SensoryRoundPurpose.baseline,
        ),
        label: map['label'] as String,
      );
}
