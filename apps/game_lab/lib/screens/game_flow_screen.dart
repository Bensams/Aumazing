import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart' hide AnimatedBuilder;

/// A screen that runs multiple games in sequence with rewards between them.
///
/// This is useful for testing the reward system between games in game_lab.
class GameFlowScreen extends StatefulWidget {
  const GameFlowScreen({
    super.key,
    required this.config,
    this.gameIds = const ['copy_me', 'match_it', 'do_what_i_say'],
  });

  final GameConfig config;
  final List<String> gameIds;

  @override
  State<GameFlowScreen> createState() => _GameFlowScreenState();
}

class _GameFlowScreenState extends State<GameFlowScreen> {
  int _currentGameIndex = 0;
  bool _showingReward = false;
  late AudioService _audioService;

  List<GameEntry> get _games =>
      widget.gameIds.map((id) => GameRegistry.find(id)).whereType<GameEntry>().toList();

  GameEntry? get _currentGame =>
      _currentGameIndex < _games.length ? _games[_currentGameIndex] : null;

  @override
  void initState() {
    super.initState();
    _audioService = AudioService();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _audioService.stopMusic();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _onGameComplete() {
    // Show reward overlay before moving to next game
    setState(() => _showingReward = true);
  }

  void _onRewardComplete() {
    setState(() => _showingReward = false);
    if (_currentGameIndex < _games.length - 1) {
      setState(() => _currentGameIndex++);
    } else {
      // All games complete - return to launcher
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showingReward) {
      return _buildRewardScreen();
    }

    final game = _currentGame;
    if (game == null) {
      return const Scaffold(
        body: Center(child: Text('No games configured')),
      );
    }

    return _GameTestScreen(
      entry: game,
      config: widget.config,
      currentGame: _currentGameIndex + 1,
      totalGames: _games.length,
      onGameComplete: _onGameComplete,
    );
  }

  Widget _buildRewardScreen() {
    final isLastGame = _currentGameIndex >= _games.length - 1;
    final rewardType = _RewardType.values[_currentGameIndex % _RewardType.values.length];

    return _RewardScreen(
      isLastGame: isLastGame,
      rewardType: rewardType,
      currentGame: _currentGameIndex + 1,
      totalGames: _games.length,
      onComplete: _onRewardComplete,
    );
  }

}

// Simple reward types for game_lab flow selection
enum _RewardType { balloons, fireworks, bubbles, candy }

/// Reward screen that shows dialogue first, then reward with fade animations
class _RewardScreen extends StatefulWidget {
  final bool isLastGame;
  final _RewardType rewardType;
  final int currentGame;
  final int totalGames;
  final VoidCallback onComplete;

  const _RewardScreen({
    required this.isLastGame,
    required this.rewardType,
    required this.currentGame,
    required this.totalGames,
    required this.onComplete,
  });

  @override
  State<_RewardScreen> createState() => _RewardScreenState();
}

class _RewardScreenState extends State<_RewardScreen>
    with TickerProviderStateMixin {
  bool _showDialogue = true;
  bool _showReward = false;
  late AnimationController _dialogueFadeController;
  late Animation<double> _dialogueFadeAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _dialogueFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _dialogueFadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _dialogueFadeController,
      curve: Curves.easeOut,
    ));

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));

    _startRewardFlow();
  }

  void _startRewardFlow() {
    // Phase 1: Show dialogue for 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      // Fade out dialogue
      _dialogueFadeController.forward().then((_) {
        if (!mounted) return;
        setState(() {
          _showDialogue = false;
          _showReward = true;
        });
        // Fade in reward
        _fadeController.forward();
        // Phase 2: Auto proceed after total 8 seconds (2s dialogue + 6s reward)
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted) {
            widget.onComplete();
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _dialogueFadeController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Widget _buildRewardEffect(_RewardType type) {
    switch (type) {
      case _RewardType.balloons:
        return BalloonsReward(
          balloonCount: 12,
          duration: const Duration(seconds: 8),
          onComplete: () {},
          onAllPopped: () {},
        );
      case _RewardType.fireworks:
        return FireworksReward(
          rocketCount: 8,
          duration: const Duration(seconds: 10),
          onComplete: () {},
          onAllExploded: () {},
        );
      case _RewardType.bubbles:
        return BubblesReward(
          bubbleCount: 15,
          duration: const Duration(seconds: 8),
          onComplete: () {},
          onAllPopped: () {},
        );
      case _RewardType.candy:
        return CandyReward(
          candyCount: 18,
          duration: const Duration(seconds: 8),
          onComplete: () {},
          onAllCollected: () {},
        );
    }
  }

  String _getHintText(_RewardType type) {
    switch (type) {
      case _RewardType.balloons:
        return '🎈 Pop the balloons!';
      case _RewardType.fireworks:
        return '🎆 Tap the rockets!';
      case _RewardType.bubbles:
        return '🫧 Pop the bubbles!';
      case _RewardType.candy:
        return '🍬 Collect the candy!';
    }
  }

  Widget _buildDialogueCard() {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360 || size.height < 600;

    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 20 : 40,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 24 : 40,
          vertical: isSmallScreen ? 30 : 48,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFFE8DEFA),
              Color(0xFFD4F4E8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🎉 Great Job!',
              style: TextStyle(
                fontSize: isSmallScreen ? 28 : 36,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF9B82C4),
              ),
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            Text(
              'Game ${widget.currentGame} of ${widget.totalGames} Complete!',
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 20,
                color: const Color(0xFF666666),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isSmallScreen ? 20 : 28),
            const CircularProgressIndicator(
              color: Color(0xFF9B82C4),
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360 || size.height < 600;

    return Scaffold(
      body: Container(
        color: Colors.transparent,
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Dialogue card (shown first for 2 seconds)
              if (_showDialogue)
                FadeTransition(
                  opacity: _dialogueFadeAnimation,
                  child: _buildDialogueCard(),
                ),

              // Reward effect layer (shown after dialogue fades)
              if (_showReward)
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildRewardEffect(widget.rewardType),
                ),

              // Continue button (only when reward is shown)
              if (_showReward)
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ElevatedButton.icon(
                      onPressed: widget.onComplete,
                      icon: Icon(
                        widget.isLastGame ? Icons.check : Icons.arrow_forward,
                        size: 20,
                      ),
                      label: Text(
                        widget.isLastGame ? 'Finish' : 'Next Game',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withAlpha(230),
                        foregroundColor: const Color(0xFF9B82C4),
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 20 : 28,
                          vertical: isSmallScreen ? 10 : 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 4,
                        shadowColor: Colors.black.withAlpha(50),
                      ),
                    ),
                  ),
                ),

              // Hint text (only when reward is shown)
              if (_showReward)
                Positioned(
                  top: 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 12 : 16,
                        vertical: isSmallScreen ? 6 : 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(200),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _getHintText(widget.rewardType),
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF9B82C4),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Individual game test screen used within the flow
class _GameTestScreen extends StatefulWidget {
  final GameEntry entry;
  final GameConfig config;
  final int currentGame;
  final int totalGames;
  final VoidCallback onGameComplete;

  const _GameTestScreen({
    required this.entry,
    required this.config,
    required this.currentGame,
    required this.totalGames,
    required this.onGameComplete,
  });

  @override
  State<_GameTestScreen> createState() => _GameTestScreenState();
}

class _GameTestScreenState extends State<_GameTestScreen> with WidgetsBindingObserver {
  late FlameGame _game;
  late AudioService _audioService;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _audioService = AudioService();
    WidgetsBinding.instance.addObserver(this);

    _game = widget.entry.create(
      config: widget.config,
      onStepChanged: (step) => setState(() => _currentStep = step),
      onGameComplete: ({
        required int score,
        required int totalItems,
        required int errorCount,
        required int totalResponseTimeMs,
      }) {
        widget.onGameComplete();
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioService.stopMusic();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GameWidget(game: _game),
          ChildModeTopBar(
            totalSteps: widget.config.totalRounds,
            currentStep: _currentStep,
            onParentTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
