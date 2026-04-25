import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_config.dart';

/// Audio context for SFX that doesn't request audio focus (allows mixing with music)
final _sfxAudioContext = AudioContext(
  android: AudioContextAndroid(
    audioFocus: AndroidAudioFocus.none,
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.game,
  ),
  iOS: AudioContextIOS(
    category: AVAudioSessionCategory.playback,
    options: {AVAudioSessionOptions.mixWithOthers},
  ),
);

/// Audio context for background music
final _musicAudioContext = AudioContext(
  android: AudioContextAndroid(
    audioFocus: AndroidAudioFocus.gain,
    contentType: AndroidContentType.music,
    usageType: AndroidUsageType.game,
  ),
  iOS: AudioContextIOS(
    category: AVAudioSessionCategory.playback,
    options: {AVAudioSessionOptions.mixWithOthers},
  ),
);

/// Centralized audio service for music and sound-effect playback.
///
/// Uses [audioplayers] under the hood. Supports looping background music
/// and one-shot sound effects. Both main_app and game_lab share this
/// service via the shared_audio package.
///
/// All playback uses [AssetSource] which works reliably on both Android
/// and iOS. The previous [BytesSource] approach caused Android's
/// MediaPlayer to reset during preparation, producing no sound.
class AudioService {
  AudioConfig _config;

  /// Dedicated player for looping background music.
  late final AudioPlayer _musicPlayer;

  /// Pool of SFX players (created on demand, reused when possible).
  final List<AudioPlayer> _sfxPlayers = [];

  /// The currently playing music track ID (null if none).
  String? _currentTrack;

  /// Asset prefix for package-based assets.
  /// Flutter resolves package assets at: packages/<pkg_name>/assets/...
  /// The audioplayers AudioCache default prefix is 'assets/', but for
  /// package assets we need the full path from the asset bundle root.
  static const String _assetPrefix = 'packages/shared_audio/assets/audio';

  AudioService({AudioConfig? config})
      : _config = config ?? AudioConfig.defaults {
    _musicPlayer = AudioPlayer()..setAudioContext(_musicAudioContext);
    // Override the default 'assets/' prefix so we can supply the full
    // Flutter asset-bundle path for package-based assets.
    _musicPlayer.audioCache = AudioCache(prefix: '');
  }

  AudioConfig get config => _config;

  /// Whether music is currently playing.
  bool get isMusicPlaying => _musicPlayer.state == PlayerState.playing;

  // ── Configuration ──────────────────────────────────────────────────

  /// Update the audio configuration (e.g. from a settings screen).
  void updateConfig(AudioConfig config) {
    _config = config;
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
    if (!_config.musicEnabled) return;

    // Don't restart the same track
    if (_currentTrack == trackName && isMusicPlaying) return;

    final assetPath = '$_assetPrefix/$trackName';

    try {
      await _musicPlayer.stop();
      _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.setVolume(_config.effectiveMusicVolume);
      await _musicPlayer.play(AssetSource(assetPath));
      _currentTrack = trackName;
    } catch (e) {
      debugPrint('[AudioService] ✖ Error playing music "$trackName": $e');
    }
  }

  /// Pause background music (can be resumed with [resumeMusic]).
  Future<void> pauseMusic() async {
    await _musicPlayer.pause();
  }

  /// Resume previously paused music.
  Future<void> resumeMusic() async {
    if (!_config.musicEnabled) return;
    await _musicPlayer.setVolume(_config.effectiveMusicVolume);
    await _musicPlayer.resume();
  }

  /// Stop background music entirely.
  Future<void> stopMusic() async {
    await _musicPlayer.stop();
    _currentTrack = null;
  }

  /// Play a random track from the provided list.
  ///
  /// Useful for shuffling between multiple background music tracks.
  /// Example: `playRandomMusic(['bg_music.ogg', 'bg_music1.ogg'])`
  Future<void> playRandomMusic(List<String> trackNames) async {
    if (trackNames.isEmpty) return;
    final random = Random();
    final selectedTrack = trackNames[random.nextInt(trackNames.length)];
    await playMusic(selectedTrack);
  }

  // ── Sound Effects ──────────────────────────────────────────────────

  /// Play a one-shot sound effect from the shared_audio assets.
  ///
  /// [sfxName] is just the filename, e.g. `'correct.wav'`.
  ///
  /// Uses [AssetSource] for reliable playback on both Android and iOS.
  Future<void> playSfx(String sfxName) async {
    if (!_config.sfxEnabled) return;

    final assetPath = '$_assetPrefix/$sfxName';

    try {
      final player = _getAvailableSfxPlayer();
      await player.setVolume(_config.effectiveSfxVolume);
      await player.play(AssetSource(assetPath));
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
      final player = AudioPlayer()..setAudioContext(_sfxAudioContext);
      // Use empty prefix so we can supply full package asset paths.
      player.audioCache = AudioCache(prefix: '');
      _sfxPlayers.add(player);
      return player;
    }
    // Fallback: reuse the oldest
    return _sfxPlayers.first;
  }

  // ── UI Sound Effects ───────────────────────────────────────────────

  /// Filename of the UI button-tap sound effect.
  static const String _uiTapSfx = 'ui_tap.wav';

  /// Play the soft tap sound for UI button presses.
  ///
  /// This is intended for Flutter widget buttons only (not in-game / Flame).
  Future<void> playButtonTap() => playSfx(_uiTapSfx);

  // ── Game Sound Effects ────────────────────────────────────────────

  // NOTE: Intentionally swapped with _levelCompleteSfx
  /// SFX file for correct answer feedback (3-star sparkle).
  static const String _correctSfx = 'sfx/wrong.wav';

  // NOTE: Intentionally swapped with _levelCompleteSfx
  /// SFX file for wrong answer feedback.
  static const String _wrongSfx = 'sfx/level_complete.wav';

  /// SFX file for in-game taps (distinct from UI button tap).
  static const String _gameTapSfx = 'sfx/game_tap.wav';

  // NOTE: Changed to 3_star.ogg (originally level_complete.wav, swapped with correct, then overridden)
  /// SFX file for level completion (satisfying pop).
  static const String _levelCompleteSfx = 'sfx/3_star.ogg';

  /// SFX file for game completion / celebration.
  static const String _gameCompleteSfx = 'sfx/game_complete.wav';

  /// SFX file for drag start.
  static const String _dragSfx = 'sfx/drag.wav';

  /// SFX file for drop / release.
  static const String _dropSfx = 'sfx/drop.wav';

  // ── Sequence Shimmer Sound Effects ────────────────────────────────

  /// SFX files for sequence position shimmer sounds (Copy Me demo phase).
  static const List<String> _shimmerSfxFiles = [
    'sfx/shimmer_1.wav',
    'sfx/shimmer_2.wav',
    'sfx/shimmer_3.wav',
    'sfx/shimmer_4.wav',
    'sfx/shimmer_5.wav',
  ];

  /// Play a shimmer SFX based on the 0-based sequence position.
  ///
  /// Position 0 → shimmer_1.wav, position 1 → shimmer_2.wav, etc.
  /// If position exceeds 4, wraps around using modulo.
  Future<void> playSequenceShimmerSfx(int sequencePosition) {
    final index = sequencePosition % _shimmerSfxFiles.length;
    return playSfx(_shimmerSfxFiles[index]);
  }

  // ── Reward Sound Effects ──────────────────────────────────────────

  /// SFX file for balloon pop.
  static const String _balloonPopSfx = 'sfx/rewards/balloon_pop.ogg';

  /// SFX file for bubble pop.
  static const String _bubblePopSfx = 'sfx/rewards/bubble.ogg';

  /// SFX file for firework explosion.
  static const String _fireworkPopSfx = 'sfx/rewards/firework_popped.ogg';

  /// SFX file for candy collection.
  static const String _candyPopSfx = 'sfx/rewards/candy_popped.ogg';

  /// Play the "correct answer" sound effect.
  Future<void> playCorrectSfx() => playSfx(_correctSfx);

  /// Play the "wrong answer" sound effect (gentle, non-punishing).
  Future<void> playWrongSfx() => playSfx(_wrongSfx);

  /// Play the in-game tap sound effect.
  ///
  /// This is a different sound from [playButtonTap] and is intended for
  /// in-game interactions (e.g. tapping a card, selecting an option).
  Future<void> playGameTapSfx() => playSfx(_gameTapSfx);

  /// Play the level-complete sound effect.
  Future<void> playLevelCompleteSfx() => playSfx(_levelCompleteSfx);

  /// Play the game-complete / celebration sound effect.
  Future<void> playGameCompleteSfx() => playSfx(_gameCompleteSfx);

  /// Play the drag-start sound effect.
  Future<void> playDragSfx() => playSfx(_dragSfx);

  /// Play the drop / release sound effect.
  Future<void> playDropSfx() => playSfx(_dropSfx);

  /// Play the balloon pop sound effect.
  Future<void> playBalloonPopSfx() => playSfx(_balloonPopSfx);

  /// Play the bubble pop sound effect.
  Future<void> playBubblePopSfx() => playSfx(_bubblePopSfx);

  /// Play the firework explosion sound effect.
  Future<void> playFireworkPopSfx() => playSfx(_fireworkPopSfx);

  /// Play the candy collection sound effect.
  Future<void> playCandyPopSfx() => playSfx(_candyPopSfx);

  // ── Lifecycle ──────────────────────────────────────────────────────

  /// Release all audio resources. Call when the app/screen is disposed.
  Future<void> dispose() async {
    await _musicPlayer.dispose();
    for (final player in _sfxPlayers) {
      await player.dispose();
    }
    _sfxPlayers.clear();
    _currentTrack = null;
  }
}
