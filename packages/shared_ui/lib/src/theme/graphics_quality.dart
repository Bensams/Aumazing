/// Graphics quality / performance tier, controlling how much visual work the
/// app does. Lower tiers reduce GPU/video load — easing device heat and
/// sensory intensity for children sensitive to motion or warmth.
///
/// - [high]   — full visuals: looping video backgrounds + full reward effects.
/// - [medium] — static (gradient) backgrounds, full reward effects.
/// - [low]    — static backgrounds + minimal motion / fewer reward particles.
enum GraphicsQuality {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High');

  const GraphicsQuality(this.slug, this.label);

  final String slug;
  final String label;

  static GraphicsQuality fromSlug(String? slug) {
    if (slug == null) return GraphicsQuality.high;
    return GraphicsQuality.values.firstWhere(
      (q) => q.slug == slug,
      orElse: () => GraphicsQuality.high,
    );
  }

  /// Video backgrounds only play on [high]; lower tiers use a static gradient.
  bool get useStaticBackground => this != GraphicsQuality.high;

  /// On [low], motion/particle effects are minimised.
  bool get reducedMotion => this == GraphicsQuality.low;

  /// Multiplier applied to reward particle counts (fewer on lower tiers).
  double get effectScale {
    switch (this) {
      case GraphicsQuality.low:
        return 0.4;
      case GraphicsQuality.medium:
        return 0.7;
      case GraphicsQuality.high:
        return 1.0;
    }
  }
}
