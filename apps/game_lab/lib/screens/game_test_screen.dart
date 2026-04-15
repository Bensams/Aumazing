import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';

/// Generic game runner screen for Game Lab.
///
/// Hosts any Flame game from the registry, wraps it with the same
/// [ChildModeTopBar] and [VoiceOverPromptBubble] that main_app uses,
/// and adds a debug overlay (FPS, score, game state).
///
/// Automatically starts background music when the game launches
/// and stops it when leaving the screen.
class GameTestScreen extends StatefulWidget {
  const GameTestScreen({
    super.key,
    required this.entry,
    required this.config,
  });

  final GameEntry entry;
  final GameConfig config;

  @override
  State<GameTestScreen> createState() => _GameTestScreenState();
}

class _GameTestScreenState extends State<GameTestScreen>
    with WidgetsBindingObserver {
  late FlameGame _game;
  late AudioService _audioService;
  int _currentStep = 0;
  bool _gameComplete = false;
  int _score = 0;
  int _totalItems = 0;
  int _errors = 0;
  bool _showDebug = true;
  bool _musicMuted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Initialize audio with config volumes
    _audioService = AudioService(
      config: AudioConfig(
        musicVolume: widget.config.bgMusicVolume,
        sfxVolume: widget.config.sfxVolume,
        musicEnabled: widget.config.bgMusicVolume > 0,
        sfxEnabled: widget.config.sfxVolume > 0,
      ),
    );

    _createGame();

    // Start background music after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _audioService.playMusic('bg_music.ogg');
    });
  }

  void _createGame() {
    setState(() {
      _currentStep = 0;
      _gameComplete = false;
      _score = 0;
      _totalItems = 0;
      _errors = 0;
    });

    _game = widget.entry.create(
      config: widget.config,
      onStepChanged: (step) => setState(() => _currentStep = step),
      onGameComplete: ({
        required int score,
        required int totalItems,
        required int errorCount,
        required int totalResponseTimeMs,
      }) {
        setState(() {
          _gameComplete = true;
          _score = score;
          _totalItems = totalItems;
          _errors = errorCount;
        });
        // Play a completion SFX
        _audioService.playSfx('complete.ogg');
      },
    );
  }

  /// Pause music when the app goes to background, resume when it returns.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _audioService.pauseMusic();
    } else if (state == AppLifecycleState.resumed) {
      _audioService.resumeMusic();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioService.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _toggleMusic() {
    setState(() => _musicMuted = !_musicMuted);
    if (_musicMuted) {
      _audioService.pauseMusic();
    } else {
      _audioService.resumeMusic();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.entry.gradientColors,
          ),
        ),
        child: Column(
          children: [
            // Top bar with progress + back
            ChildModeTopBar(
              totalSteps: widget.config.totalRounds,
              currentStep: _currentStep,
              onParentTap: () => Navigator.of(context).pop(),
            ),

            // Flame game
            Expanded(
              child: Stack(
                children: [
                  GameWidget(
                    game: _game,
                    backgroundBuilder: (_) => const SizedBox.shrink(),
                  ),

                  // Debug overlay
                  if (_showDebug)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.entry.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Step: $_currentStep/${widget.config.totalRounds}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10),
                            ),
                            Text(
                              'Difficulty: ${widget.config.difficulty}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10),
                            ),
                            Text(
                              '🎵 ${_musicMuted ? "OFF" : "ON"} '
                              '(${(widget.config.bgMusicVolume * 100).round()}%)',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10),
                            ),
                            if (_gameComplete)
                              Text(
                                'Score: $_score/$_totalItems (${_errors}err)',
                                style: const TextStyle(
                                    color: Colors.greenAccent, fontSize: 10),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Bottom bar
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              color: AppColors.white.withAlpha(180),
              child: Row(
                children: [
                  // Voice-over prompt
                  Expanded(
                    child: VoiceOverPromptBubble(
                      text: _gameComplete
                          ? '🎉 Done! Score: $_score/$_totalItems'
                          : 'Tap the shapes that look the same!',
                      isVisible: true,
                    ),
                  ),

                  // Action buttons
                  const SizedBox(width: AppSpacing.sm),

                  // Music toggle
                  IconButton(
                    icon: Icon(
                      _musicMuted
                          ? Icons.music_off_rounded
                          : Icons.music_note_rounded,
                      color: _musicMuted
                          ? AppColors.mutedForeground
                          : AppColors.primaryPurple,
                    ),
                    tooltip: _musicMuted ? 'Unmute music' : 'Mute music',
                    onPressed: _toggleMusic,
                  ),
                  IconButton(
                    icon: Icon(
                      _showDebug
                          ? Icons.bug_report
                          : Icons.bug_report_outlined,
                      color: AppColors.primaryPurple,
                    ),
                    tooltip: 'Toggle debug',
                    onPressed: () =>
                        setState(() => _showDebug = !_showDebug),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.primaryPurple),
                    tooltip: 'Restart game',
                    onPressed: _createGame,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.mutedForeground),
                    tooltip: 'Back to launcher',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
