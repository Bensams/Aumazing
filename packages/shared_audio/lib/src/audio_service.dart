import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_config.dart';

/// Centralized audio service for music and sound-effect playback.
///
/// Uses [audioplayers] under the hood. Supports looping background music
/// and one-shot sound effects. Both main_app and game_lab share this
/// service via the shared_audio package.
class AudioService {
  AudioConfig _config;

  /// Dedicated player for looping background music.
  final AudioPlayer _musicPlayer = AudioPlayer();

  /// Pool of SFX players (created on demand, reused when possible).
  final List<AudioPlayer> _sfxPlayers = [];

  /// The currently playing music track ID (null if none).
  String? _currentTrack;

  /// Asset prefix for package-based assets.
  /// Flutter resolves package assets at: packages/<pkg_name>/assets/...
  static const String _assetPrefix = 'packages/shared_audio/assets/audio';

  AudioService({AudioConfig? config})
      : _config = config ?? AudioConfig.defaults;

  AudioConfig get config => _config;

  /// Whether music is currently playing.
  bool get isMusicPlaying => _musicPlayer.state == PlayerState.playing;

  // ── Configuration ──────────────────────────────────────────────────

  /// Update the audio configuration (e.g. from a settings screen).
  void updateConfig(AudioConfig config) {
    _config = config;
    debugPrint('[AudioService] Config updated: '
        'music=${_config.effectiveMusicVolume.toStringAsFixed(1)}, '
        'sfx=${_config.effectiveSfxVolume.toStringAsFixed(1)}');

    // Apply volume change immediately to the playing music
    _musicPlayer.setVolume(_config.effectiveMusicVolume);
  }

  // ── Background Music ───────────────────────────────────────────────

  /// Play background music from the shared_audio assets.
  ///
  /// [trackName] is just the filename, e.g. `'bg_music.ogg'`.
  /// The full asset path is resolved automatically via the package prefix.
  ///
  /// Music loops indefinitely until [stopMusic] is called.
  Future<void> playMusic(String trackName) async {
    if (!_config.musicEnabled) {
      debugPrint('[AudioService] Music disabled, skipping: $trackName');
      return;
    }

    // Don't restart the same track
    if (_currentTrack == trackName && isMusicPlaying) {
      debugPrint('[AudioService] Already playing: $trackName');
      return;
    }

    try {
      await _musicPlayer.stop();
      _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.setVolume(_config.effectiveMusicVolume);
      await _musicPlayer.setSource(
        AssetSource('$_assetPrefix/$trackName'),
      );
      await _musicPlayer.resume();
      _currentTrack = trackName;
      debugPrint('[AudioService] ▶ Playing music: $trackName '
          '(vol=${_config.effectiveMusicVolume.toStringAsFixed(1)})');
    } catch (e) {
      debugPrint('[AudioService] ✖ Error playing music "$trackName": $e');
    }
  }

  /// Pause background music (can be resumed with [resumeMusic]).
  Future<void> pauseMusic() async {
    await _musicPlayer.pause();
    debugPrint('[AudioService] ⏸ Music paused');
  }

  /// Resume previously paused music.
  Future<void> resumeMusic() async {
    if (!_config.musicEnabled) return;
    await _musicPlayer.setVolume(_config.effectiveMusicVolume);
    await _musicPlayer.resume();
    debugPrint('[AudioService] ▶ Music resumed');
  }

  /// Stop background music entirely.
  Future<void> stopMusic() async {
    await _musicPlayer.stop();
    _currentTrack = null;
    debugPrint('[AudioService] ⏹ Music stopped');
  }

  // ── Sound Effects ──────────────────────────────────────────────────

  /// Play a one-shot sound effect from the shared_audio assets.
  ///
  /// [sfxName] is just the filename, e.g. `'correct.ogg'`.
  Future<void> playSfx(String sfxName) async {
    if (!_config.sfxEnabled) return;

    try {
      final player = _getAvailableSfxPlayer();
      await player.setVolume(_config.effectiveSfxVolume);
      await player.setSource(
        AssetSource('$_assetPrefix/$sfxName'),
      );
      await player.resume();
      debugPrint('[AudioService] 🔊 SFX: $sfxName');
    } catch (e) {
      debugPrint('[AudioService] ✖ Error playing SFX "$sfxName": $e');
    }
  }

  /// Find or create an available SFX player from the pool.
  AudioPlayer _getAvailableSfxPlayer() {
    // Reuse a player that's finished/stopped
    for (final player in _sfxPlayers) {
      if (player.state == PlayerState.completed ||
          player.state == PlayerState.stopped) {
        return player;
      }
    }
    // Create a new one (pool grows as needed, capped at 8)
    if (_sfxPlayers.length < 8) {
      final player = AudioPlayer();
      _sfxPlayers.add(player);
      return player;
    }
    // Fallback: reuse the oldest
    return _sfxPlayers.first;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────

  /// Release all audio resources. Call when the app/screen is disposed.
  Future<void> dispose() async {
    await _musicPlayer.dispose();
    for (final player in _sfxPlayers) {
      await player.dispose();
    }
    _sfxPlayers.clear();
    _currentTrack = null;
    debugPrint('[AudioService] Disposed');
  }
}
