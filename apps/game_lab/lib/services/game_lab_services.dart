import 'package:flutter/foundation.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';

/// Lightweight service locator for Game Lab.
///
/// Holds singleton instances of [AudioService], [VoiceOverService], and
/// [HapticService] so they are shared across all screens instead of being
/// recreated per screen. This mirrors how main_app provides these services
/// via Provider, but uses a simpler pattern suitable for a testing sandbox.
class GameLabServices {
  GameLabServices._();

  static final GameLabServices instance = GameLabServices._();

  late AudioService audioService;
  late VoiceOverService voiceOverService;
  late HapticService hapticService;

  /// Whether haptic/vibration feedback is enabled.
  bool get hapticEnabled => hapticService.config.enabled;
  set hapticEnabled(bool value) {
    hapticService.updateConfig(hapticService.config.copyWith(enabled: value));
  }

  /// Track the last played SFX name for debug display.
  String lastPlayedSfx = '';

  /// Track the last played VO cue name for debug display.
  String lastPlayedVo = '';

  /// Whether services have been initialized.
  bool _initialized = false;

  /// Initialize audio services with the given config.
  ///
  /// Safe to call multiple times — subsequent calls update the config
  /// without recreating the services.
  void initialize({AudioConfig? audioConfig, double voVolume = 1.0, bool voEnabled = true}) {
    if (!_initialized) {
      audioService = AudioService(config: audioConfig ?? AudioConfig.defaults);
      voiceOverService = VoiceOverService(
        volume: voVolume,
        enabled: voEnabled,
      );
      hapticService = HapticService(config: HapticConfig.defaults);
      _initialized = true;
      debugPrint('[GameLabServices] Initialized');
    }
  }

  /// Update audio config on the existing service (e.g. from settings changes).
  void updateAudioConfig(AudioConfig config) {
    if (_initialized) {
      audioService.updateConfig(config);
    }
  }

  /// Update haptic config on the existing service.
  void updateHapticConfig(HapticConfig config) {
    hapticService.updateConfig(config);
  }

  /// Update voice-over settings.
  void updateVoiceOverSettings({double? volume, bool? enabled}) {
    if (!_initialized) return;
    if (volume != null) voiceOverService.setVolume(volume);
    if (enabled != null) voiceOverService.setEnabled(enabled);
  }

  /// Dispose all services. Call when the app is shutting down.
  Future<void> dispose() async {
    if (_initialized) {
      await audioService.dispose();
      await voiceOverService.dispose();
      _initialized = false;
      debugPrint('[GameLabServices] Disposed');
    }
  }
}
