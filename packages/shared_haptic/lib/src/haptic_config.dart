/// Configuration for haptic feedback behavior.
class HapticConfig {
  /// Whether haptic feedback is enabled globally.
  final bool enabled;

  /// Intensity level: 0.0 (off) to 1.0 (maximum).
  /// Maps to which HapticFeedback methods are used:
  /// - 0.0–0.33: lightImpact only
  /// - 0.34–0.66: mediumImpact
  /// - 0.67–1.0: heavyImpact
  final double intensity;

  const HapticConfig({
    this.enabled = true,
    this.intensity = 0.7,
  });

  static const HapticConfig defaults = HapticConfig();

  HapticConfig copyWith({
    bool? enabled,
    double? intensity,
  }) {
    return HapticConfig(
      enabled: enabled ?? this.enabled,
      intensity: intensity ?? this.intensity,
    );
  }
}
