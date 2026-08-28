/// Audio volume and toggle configuration.
///
/// Immutable value object used to pass audio settings to games and services.
class AudioConfig {
  /// Background music volume: 0.0 (muted) to 1.0 (full).
  final double musicVolume;

  /// Sound-effect volume: 0.0 (muted) to 1.0 (full).
  final double sfxVolume;

  /// Whether background music is enabled.
  final bool musicEnabled;

  /// Whether sound effects are enabled.
  final bool sfxEnabled;

  const AudioConfig({
    this.musicVolume = 0.5,
    this.sfxVolume = 0.7,
    this.musicEnabled = true,
    this.sfxEnabled = true,
  });

  static const AudioConfig defaults = AudioConfig();

  AudioConfig copyWith({
    double? musicVolume,
    double? sfxVolume,
    bool? musicEnabled,
    bool? sfxEnabled,
  }) {
    return AudioConfig(
      musicVolume: musicVolume ?? this.musicVolume,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      musicEnabled: musicEnabled ?? this.musicEnabled,
      sfxEnabled: sfxEnabled ?? this.sfxEnabled,
    );
  }

  /// Effective music volume (0 if disabled).
  double get effectiveMusicVolume => musicEnabled ? musicVolume : 0.0;

  /// Effective SFX volume (0 if disabled).
  double get effectiveSfxVolume => sfxEnabled ? sfxVolume : 0.0;
}
