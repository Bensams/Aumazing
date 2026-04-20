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

  // Gameplay analytics debug data
  double _avgResponseTimeMs = 0;
  double _accuracy = 0;
  int _retryCount = 0;
  int _timeSpentMs = 0;
  bool _isCompleted = false;
  double _completionRate = 0;
  int _completedSubTasks = 0;
  int _totalSubTasks = 0;
  String _interactionQuality = 'enhanced';
  int _totalTaps = 0;
  int _rapidTaps = 0;
  double _rapidTapRatio = 0;
  int _totalDragPoints = 0;
  bool _hasSmoothDrags = false;
  DateTime? _sessionStartTime;

  // Enhanced analytics debug data
  int _hintCount = 0;
  int _promptCount = 0;
  int _idleTimeSeconds = 0;
  int _offTaskCount = 0;
  double _improvementScore = 0;
  double _consistencyScore = 0;
  String _assistanceLevel = 'independent';
  Map<String, dynamic> _gameSpecificMetrics = {};
  List<GameRoundMetrics> _roundMetrics = [];

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
      _resetAnalytics();
    });

    _game = widget.entry.create(
      config: widget.config,
      onStepChanged: (step) {
        setState(() {
          _currentStep = step;
          _updateAnalyticsFromGame();
        });
      },
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
          _updateAnalyticsFromGame();
        });
        // Play a completion SFX
        _audioService.playSfx('complete.ogg');
      },
    );

    // Start analytics timer
    _sessionStartTime = DateTime.now();
    _startAnalyticsTimer();
  }

  void _resetAnalytics() {
    _avgResponseTimeMs = 0;
    _accuracy = 0;
    _retryCount = 0;
    _timeSpentMs = 0;
    _isCompleted = false;
    _completionRate = 0;
    _completedSubTasks = 0;
    _totalSubTasks = 0;
    _interactionQuality = 'mixed';
    _totalTaps = 0;
    _rapidTaps = 0;
    _rapidTapRatio = 0;
    _totalDragPoints = 0;
    _hasSmoothDrags = false;
    _sessionStartTime = null;
  }

  void _startAnalyticsTimer() {
    // Update time spent every second while game is active
    Future.doWhile(() async {
      if (!mounted || _gameComplete) return false;
      await Future.delayed(const Duration(seconds: 1));
      if (mounted && !_gameComplete) {
        setState(() {
          _updateAnalyticsFromGame();
          if (_sessionStartTime != null) {
            _timeSpentMs = DateTime.now().difference(_sessionStartTime!).inMilliseconds;
          }
        });
      }
      return mounted && !_gameComplete;
    });
  }

  void _updateAnalyticsFromGame() {
    // Try to extract analytics from games using GameplayAnalyticsMixin
    final game = _game;
    if (game is MatchItGame) {
      _extractMatchItAnalytics(game);
    } else if (game is CopyMeGame) {
      _extractCopyMeAnalytics(game);
    } else if (game is DoWhatISayGame) {
      _extractDoWhatISayAnalytics(game);
    } else if (game is MyTurnYourTurnGame) {
      _extractMyTurnYourTurnAnalytics(game);
    }
  }

  void _extractMatchItAnalytics(MatchItGame game) {
    final session = game.analyticsSession;
    if (session == null) return;

    _avgResponseTimeMs = session.avgResponseTime * 1000;
    _accuracy = session.accuracy;
    _retryCount = session.retryCount;
    _isCompleted = session.isCompleted;
    _completionRate = session.taskCompletionRate;
    _completedSubTasks = session.completedRounds;
    _totalSubTasks = session.totalRounds;
    _interactionQuality = 'enhanced';
    _totalTaps = game.analyticsTotalTouches;
    _rapidTaps = 0;
    _rapidTapRatio = 0.0;
    _totalDragPoints = 0;
    _hasSmoothDrags = false;

    // Enhanced metrics
    _hintCount = session.hintCount;
    _promptCount = session.promptCount;
    _idleTimeSeconds = session.idleTimeSeconds;
    _offTaskCount = session.offTaskActionCount;
    _improvementScore = session.improvementScore;
    _consistencyScore = session.consistencyScore;
    _assistanceLevel = session.assistanceLevel.name;
    _gameSpecificMetrics = session.gameSpecificMetrics;
    _roundMetrics = session.rounds;
  }

  void _extractCopyMeAnalytics(CopyMeGame game) {
    final session = game.analyticsSession;
    if (session == null) return;

    _avgResponseTimeMs = session.avgResponseTime * 1000;
    _accuracy = session.accuracy;
    _retryCount = session.retryCount;
    _isCompleted = session.isCompleted;
    _completionRate = session.taskCompletionRate;
    _completedSubTasks = session.completedRounds;
    _totalSubTasks = session.totalRounds;
    _interactionQuality = 'enhanced';
    _totalTaps = game.analyticsTotalTouches;
    _rapidTaps = 0;
    _rapidTapRatio = 0.0;
    _totalDragPoints = 0;
    _hasSmoothDrags = false;

    // Enhanced metrics
    _hintCount = session.hintCount;
    _promptCount = session.promptCount;
    _idleTimeSeconds = session.idleTimeSeconds;
    _offTaskCount = session.offTaskActionCount;
    _improvementScore = session.improvementScore;
    _consistencyScore = session.consistencyScore;
    _assistanceLevel = session.assistanceLevel.name;
    _gameSpecificMetrics = session.gameSpecificMetrics;
    _roundMetrics = session.rounds;
  }

  void _extractDoWhatISayAnalytics(DoWhatISayGame game) {
    final session = game.analyticsSession;
    if (session == null) return;

    _avgResponseTimeMs = session.avgResponseTime * 1000;
    _accuracy = session.accuracy;
    _retryCount = session.retryCount;
    _isCompleted = session.isCompleted;
    _completionRate = session.taskCompletionRate;
    _completedSubTasks = session.completedRounds;
    _totalSubTasks = session.totalRounds;
    _interactionQuality = 'enhanced';
    _totalTaps = game.analyticsTotalTouches;
    _rapidTaps = 0;
    _rapidTapRatio = 0.0;
    _totalDragPoints = 0;
    _hasSmoothDrags = false;

    // Enhanced metrics
    _hintCount = session.hintCount;
    _promptCount = session.promptCount;
    _idleTimeSeconds = session.idleTimeSeconds;
    _offTaskCount = session.offTaskActionCount;
    _improvementScore = session.improvementScore;
    _consistencyScore = session.consistencyScore;
    _assistanceLevel = session.assistanceLevel.name;
    _gameSpecificMetrics = session.gameSpecificMetrics;
    _roundMetrics = session.rounds;
  }

  void _extractMyTurnYourTurnAnalytics(MyTurnYourTurnGame game) {
    final session = game.analyticsSession;
    if (session == null) return;

    _avgResponseTimeMs = session.avgResponseTime * 1000;
    _accuracy = session.accuracy;
    _retryCount = session.retryCount;
    _isCompleted = session.isCompleted;
    _completionRate = session.taskCompletionRate;
    _completedSubTasks = session.completedRounds;
    _totalSubTasks = session.totalRounds;
    _interactionQuality = 'enhanced';
    _totalTaps = game.analyticsTotalTouches;
    _rapidTaps = 0;
    _rapidTapRatio = 0.0;
    _totalDragPoints = 0;
    _hasSmoothDrags = false;

    // Enhanced metrics
    _hintCount = session.hintCount;
    _promptCount = session.promptCount;
    _idleTimeSeconds = session.idleTimeSeconds;
    _offTaskCount = session.offTaskActionCount;
    _improvementScore = session.improvementScore;
    _consistencyScore = session.consistencyScore;
    _assistanceLevel = session.assistanceLevel.name;
    _gameSpecificMetrics = session.gameSpecificMetrics;
    _roundMetrics = session.rounds;
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

  Widget _buildDebugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
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

                  // Debug overlay with gameplay analytics
                  if (_showDebug)
                    Positioned(
                      top: 8,
                      right: 8,
                      bottom: 10,
                      child: Container(
                        width: 200,
                        height: 300,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _gameComplete
                                ? Colors.greenAccent
                                : Colors.white24,
                            width: 1,
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                            // Header
                            Row(
                              children: [
                                const Icon(Icons.analytics_rounded,
                                    color: Colors.white70, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  widget.entry.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white24, height: 12),

                            // Progress
                            _buildDebugRow('Step', '$_currentStep/${widget.config.totalRounds}'),
                            _buildDebugRow('Score', '$_score/$_totalItems'),
                            _buildDebugRow('Errors', '$_errors'),

                            const Divider(color: Colors.white24, height: 12),

                            // Analytics indicators
                            _buildDebugRow(
                              'Response Time',
                              '${_avgResponseTimeMs.toStringAsFixed(0)}ms',
                            ),
                            _buildDebugRow(
                              'Accuracy',
                              '${(_accuracy * 100).toStringAsFixed(1)}%',
                            ),
                            _buildDebugRow('Retries', '$_retryCount'),
                            _buildDebugRow(
                              'Time Spent',
                              '${(_timeSpentMs / 1000).toStringAsFixed(1)}s',
                            ),
                            _buildDebugRow(
                              'Completed',
                              _isCompleted ? 'Yes' : 'No',
                            ),
                            _buildDebugRow(
                              'Completion Rate',
                              '${(_completionRate * 100).toStringAsFixed(0)}% ($_completedSubTasks/$_totalSubTasks)',
                            ),

                            const Divider(color: Colors.white24, height: 12),

                            // Interaction patterns
                            _buildDebugRow(
                              'Interaction',
                              _interactionQuality,
                            ),
                            _buildDebugRow('Taps', '$_totalTaps'),
                            _buildDebugRow(
                              'Rapid Taps',
                              '$_rapidTaps (${(_rapidTapRatio * 100).toStringAsFixed(0)}%)',
                            ),
                            _buildDebugRow('Drags', '$_totalDragPoints'),
                            _buildDebugRow(
                              'Smooth Drags',
                              _hasSmoothDrags ? 'Yes' : 'No',
                            ),

                            const Divider(color: Colors.white24, height: 12),

                            // Enhanced Analytics - Assistance
                            _buildDebugRow(
                              'Assistance Level',
                              _assistanceLevel,
                            ),
                            _buildDebugRow('Hints', '$_hintCount'),
                            _buildDebugRow('Prompts', '$_promptCount'),
                            _buildDebugRow(
                              'Idle Time',
                              '${_idleTimeSeconds}s',
                            ),
                            _buildDebugRow('Off-Task', '$_offTaskCount'),

                            const Divider(color: Colors.white24, height: 12),

                            // Enhanced Analytics - Progress
                            _buildDebugRow(
                              'Improvement',
                              '${(_improvementScore * 100).toStringAsFixed(0)}%',
                            ),
                            _buildDebugRow(
                              'Consistency',
                              '${(_consistencyScore * 100).toStringAsFixed(0)}%',
                            ),

                            // Game-specific metrics
                            if (_gameSpecificMetrics.isNotEmpty) ...[
                              const Divider(color: Colors.white24, height: 12),
                              ..._gameSpecificMetrics.entries.take(4).map(
                                (e) => _buildDebugRow(
                                  e.key,
                                  e.value.toString(),
                                ),
                              ),
                            ],

                            // Round details
                            if (_roundMetrics.isNotEmpty) ...[
                              const Divider(color: Colors.white24, height: 12),
                              _buildDebugRow(
                                'Rounds Done',
                                '${_roundMetrics.length}',
                              ),
                            ],

                            if (_gameComplete) ...[
                              const Divider(color: Colors.greenAccent, height: 12),
                              const Text(
                                '✓ Game Complete',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
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

                  // Visual guide buttons for Copy Me Game
                  if (_game is CopyMeGame && !_gameComplete) ...[
                    IconButton(
                      icon: const Icon(Icons.replay_rounded,
                          color: AppColors.skyBlue),
                      tooltip: 'Replay sequence',
                      onPressed: () => (_game as CopyMeGame).replaySequenceAsVisualGuide(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.lightbulb_rounded,
                          color: AppColors.butterYellow),
                      tooltip: 'Show hints',
                      onPressed: () => (_game as CopyMeGame).showFullSequenceHints(),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],

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
