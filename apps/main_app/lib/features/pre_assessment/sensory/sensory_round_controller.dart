import 'package:flutter/services.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_audio/shared_audio.dart';

import 'sensory_round_config.dart';

/// Controls sensory settings (music, haptic) per round during pre-assessment.
///
/// Created in the pre-assessment progress screen and passed to game screens.
/// At the start of each round, call [applyRoundConfig] to toggle music and
/// haptic feedback according to the round's [SensoryRoundConfig].
///
/// When the pre-assessment is complete, call [dispose] (or
/// [restoreOriginalSettings]) to return audio/haptic to the parent's
/// original preferences.
class SensoryRoundController {
  final AudioService _audioService;
  final List<SensoryRoundConfig> _rounds;
  final bool _consentGiven;

  // Original settings to restore after pre-assessment
  final AudioConfig _originalAudioConfig;
  final bool _originalVibrationEnabled;

  int _currentRoundIndex = 0;

  SensoryRoundController({
    required AudioService audioService,
    required List<SensoryRoundConfig> rounds,
    required bool consentGiven,
    required AudioConfig originalAudioConfig,
    required bool originalVibrationEnabled,
  })  : _audioService = audioService,
        _rounds = rounds,
        _consentGiven = consentGiven,
        _originalAudioConfig = originalAudioConfig,
        _originalVibrationEnabled = originalVibrationEnabled;

  // ── Getters ─────────────────────────────────────────────────────────────

  /// Whether the parent gave consent for sensory testing.
  bool get consentGiven => _consentGiven;

  /// Current round configuration.
  SensoryRoundConfig get currentConfig => _rounds[_currentRoundIndex];

  /// Current round number (1-based).
  int get currentRoundNumber => _currentRoundIndex + 1;

  /// Total number of rounds.
  int get totalRounds => _rounds.length;

  /// All round configurations (unmodifiable).
  List<SensoryRoundConfig> get rounds => List.unmodifiable(_rounds);

  /// The configuration for a 1-based round number, or null when the game
  /// reported a round the experiment has no configuration for.
  SensoryRoundConfig? configForRound(int roundNumber) {
    for (final config in _rounds) {
      if (config.roundNumber == roundNumber) return config;
    }
    return null;
  }

  /// Stamps each recorded round with the sensory configuration that was
  /// actually active during it.
  ///
  /// Without this the persisted round rows carry the *session's* music and
  /// haptic flags, which are constant across the whole game and therefore
  /// erase the very contrast the experiment measures.
  void stampRoundSensoryState(GameSessionMetrics? analytics) {
    if (analytics == null) return;
    for (final round in analytics.rounds) {
      final config = configForRound(round.roundNumber);
      if (config == null) continue;
      round.musicEnabled = config.musicEnabled;
      round.hapticEnabled = config.hapticEnabled;
    }
  }

  /// The original audio config saved before pre-assessment started.
  AudioConfig get originalAudioConfig => _originalAudioConfig;

  /// The original vibration-enabled flag saved before pre-assessment started.
  bool get originalVibrationEnabled => _originalVibrationEnabled;

  // ── Round control ───────────────────────────────────────────────────────

  /// Apply sensory settings for the given round number (1-based).
  ///
  /// Call this at the start of each round in the game screen. It updates
  /// the [AudioService] config and starts/stops music accordingly.
  Future<void> applyRoundConfig(int roundNumber) async {
    _currentRoundIndex = (roundNumber - 1).clamp(0, _rounds.length - 1);
    final config = currentConfig;

    // Update audio config — keep original volumes and SFX settings,
    // only toggle music enabled/disabled per round.
    _audioService.updateConfig(AudioConfig(
      musicEnabled: config.musicEnabled,
      musicVolume: _originalAudioConfig.musicVolume,
      sfxEnabled: _originalAudioConfig.sfxEnabled,
      sfxVolume: _originalAudioConfig.sfxVolume,
    ));

    // Start or stop music based on config
    if (config.musicEnabled) {
      await _audioService.resumeMusic();
    } else {
      await _audioService.pauseMusic();
    }
  }

  // ── Haptic helpers ──────────────────────────────────────────────────────

  /// Trigger haptic feedback if enabled for the current round.
  ///
  /// Call this on correct answers.
  void triggerHapticOnCorrect() {
    if (currentConfig.hapticEnabled) {
      HapticFeedback.mediumImpact();
    }
  }

  /// Trigger light haptic feedback if enabled for the current round.
  ///
  /// Call this on interactions/taps.
  void triggerHapticOnTap() {
    if (currentConfig.hapticEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Restore original audio settings after pre-assessment completes.
  Future<void> restoreOriginalSettings() async {
    _audioService.updateConfig(_originalAudioConfig);
    if (_originalAudioConfig.musicEnabled) {
      await _audioService.resumeMusic();
    }
  }

  /// Dispose and restore settings.
  Future<void> dispose() async {
    await restoreOriginalSettings();
  }
}
