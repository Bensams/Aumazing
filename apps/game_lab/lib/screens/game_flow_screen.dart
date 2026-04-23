import 'dart:math';

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
    final rewardType = RewardType.values[_currentGameIndex % RewardType.values.length];

    return _RewardScreen(
      isLastGame: isLastGame,
      rewardType: rewardType,
      currentGame: _currentGameIndex + 1,
      totalGames: _games.length,
      onComplete: _onRewardComplete,
    );
  }

}

// Simple reward types for game_lab
enum RewardType { balloons, fireworks, bubbles, candy }

/// Reward screen that shows dialogue first, then reward with fade animations
class _RewardScreen extends StatefulWidget {
  final bool isLastGame;
  final RewardType rewardType;
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

  Widget _buildRewardEffect(RewardType type) {
    switch (type) {
      case RewardType.balloons:
        return BalloonsReward(
          balloonCount: 12,
          duration: const Duration(seconds: 8),
          onAllPopped: () {},
        );
      case RewardType.fireworks:
        return FireworksReward(
          rocketCount: 8,
          duration: const Duration(seconds: 10),
          onAllExploded: () {},
        );
      case RewardType.bubbles:
        return BubblesReward(
          bubbleCount: 15,
          duration: const Duration(seconds: 8),
          onAllPopped: () {},
        );
      case RewardType.candy:
        return CandyReward(
          candyCount: 18,
          duration: const Duration(seconds: 8),
          onAllCollected: () {},
        );
    }
  }

  String _getHintText(RewardType type) {
    switch (type) {
      case RewardType.balloons:
        return '🎈 Pop the balloons!';
      case RewardType.fireworks:
        return '🎆 Tap the rockets!';
      case RewardType.bubbles:
        return '🫧 Pop the bubbles!';
      case RewardType.candy:
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
                  child: Positioned.fill(
                    child: _buildRewardEffect(widget.rewardType),
                  ),
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

// Simple reward widgets for game_lab (inline to avoid imports)

/// Balloons reward widget for testing
class BalloonsReward extends StatefulWidget {
  final int balloonCount;
  final Duration duration;
  final VoidCallback onAllPopped;
  final VoidCallback? onComplete;

  const BalloonsReward({
    required this.balloonCount,
    required this.duration,
    required this.onAllPopped,
    this.onComplete,
  });

  @override
  State<BalloonsReward> createState() => _BalloonsRewardState();
}

class _BalloonsRewardState extends State<BalloonsReward> {
  final List<_BalloonConfig> _balloons = [];
  int _poppedCount = 0;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _generateBalloons();
  }

  void _generateBalloons() {
    final colors = [
      const Color(0xFFFF6B6B),
      const Color(0xFF4ECDC4),
      const Color(0xFFFFE66D),
      const Color(0xFF9B82C4),
      const Color(0xFF95E1D3),
      const Color(0xFFF38181),
    ];

    for (int i = 0; i < widget.balloonCount; i++) {
      _balloons.add(_BalloonConfig(
        initialX: 0.1 + _random.nextDouble() * 0.8,
        size: 40 + _random.nextDouble() * 40,
        color: colors[_random.nextInt(colors.length)],
        delay: Duration(milliseconds: i * 300),
        floatDuration: widget.duration + Duration(milliseconds: _random.nextInt(2000)),
      ));
    }
  }

  void _onBalloonPopped() {
    setState(() => _poppedCount++);
    if (_poppedCount >= widget.balloonCount) {
      widget.onAllPopped();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: _balloons.asMap().entries.map((entry) {
        return _PoppableBalloon(
          config: entry.value,
          onPopped: _onBalloonPopped,
        );
      }).toList(),
    );
  }
}

class _BalloonConfig {
  final double initialX;
  final double size;
  final Color color;
  final Duration delay;
  final Duration floatDuration;

  _BalloonConfig({
    required this.initialX,
    required this.size,
    required this.color,
    required this.delay,
    required this.floatDuration,
  });
}

class _PoppableBalloon extends StatefulWidget {
  final _BalloonConfig config;
  final VoidCallback onPopped;

  const _PoppableBalloon({
    required this.config,
    required this.onPopped,
  });

  @override
  State<_PoppableBalloon> createState() => _PoppableBalloonState();
}

class _PoppableBalloonState extends State<_PoppableBalloon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _yAnimation;
  bool _isPopped = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.config.floatDuration,
    );

    _yAnimation = Tween<double>(
      begin: 1.2,
      end: -0.2,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

    // Delay start
    Future.delayed(widget.config.delay, () {
      if (mounted) _controller.forward();
    });

    // Check for off-screen
    _controller.addListener(() {
      if (_yAnimation.value <= -0.15 && !_isPopped) {
        _onOffScreen();
      }
    });
  }

  void _onOffScreen() {
    if (!_isPopped) {
      setState(() => _isPopped = true);
      widget.onPopped();
    }
  }

  void _pop() {
    if (_isPopped) return;
    setState(() => _isPopped = true);
    widget.onPopped();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPopped) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;
        final x = widget.config.initialX * screenWidth;
        final y = _yAnimation.value * screenHeight;

        return Positioned(
          left: x - widget.config.size / 2,
          top: y,
          child: GestureDetector(
            onTap: _pop,
            child: Container(
              width: widget.config.size,
              height: widget.config.size * 1.2,
              decoration: BoxDecoration(
                color: widget.config.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.config.color.withAlpha(100),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Bubbles Reward
class BubblesReward extends StatefulWidget {
  final int bubbleCount;
  final Duration duration;
  final VoidCallback onAllPopped;
  final VoidCallback? onComplete;

  const BubblesReward({
    required this.bubbleCount,
    required this.duration,
    required this.onAllPopped,
    this.onComplete,
  });

  @override
  State<BubblesReward> createState() => _BubblesRewardState();
}

class _BubblesRewardState extends State<BubblesReward> {
  final List<_BubbleConfig> _bubbles = [];
  int _poppedCount = 0;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _generateBubbles();
  }

  void _generateBubbles() {
    final colors = [
      Colors.blue.withAlpha(150),
      Colors.cyan.withAlpha(150),
      Colors.purple.withAlpha(150),
      Colors.pink.withAlpha(150),
    ];

    for (int i = 0; i < widget.bubbleCount; i++) {
      _bubbles.add(_BubbleConfig(
        initialX: 0.1 + _random.nextDouble() * 0.8,
        size: 30 + _random.nextDouble() * 30,
        color: colors[_random.nextInt(colors.length)],
        delay: Duration(milliseconds: i * 250),
        floatDuration: widget.duration + Duration(milliseconds: _random.nextInt(2000)),
      ));
    }
  }

  void _onBubblePopped() {
    setState(() => _poppedCount++);
    if (_poppedCount >= widget.bubbleCount) {
      widget.onAllPopped();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: _bubbles.asMap().entries.map((entry) {
        return _PoppableBubble(
          config: entry.value,
          onPopped: _onBubblePopped,
        );
      }).toList(),
    );
  }
}

class _BubbleConfig {
  final double initialX;
  final double size;
  final Color color;
  final Duration delay;
  final Duration floatDuration;

  _BubbleConfig({
    required this.initialX,
    required this.size,
    required this.color,
    required this.delay,
    required this.floatDuration,
  });
}

class _PoppableBubble extends StatefulWidget {
  final _BubbleConfig config;
  final VoidCallback onPopped;

  const _PoppableBubble({
    required this.config,
    required this.onPopped,
  });

  @override
  State<_PoppableBubble> createState() => _PoppableBubbleState();
}

class _PoppableBubbleState extends State<_PoppableBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _yAnimation;
  bool _isPopped = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.config.floatDuration,
    );

    _yAnimation = Tween<double>(
      begin: 1.1,
      end: -0.1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

    Future.delayed(widget.config.delay, () {
      if (mounted) _controller.forward();
    });

    _controller.addListener(() {
      if (_yAnimation.value <= -0.05 && !_isPopped) {
        _onOffScreen();
      }
    });
  }

  void _onOffScreen() {
    if (!_isPopped) {
      setState(() => _isPopped = true);
      widget.onPopped();
    }
  }

  void _pop() {
    if (_isPopped) return;
    setState(() => _isPopped = true);
    widget.onPopped();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPopped) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;
        final x = widget.config.initialX * screenWidth;
        final y = _yAnimation.value * screenHeight;

        return Positioned(
          left: x - widget.config.size / 2,
          top: y - widget.config.size / 2,
          child: GestureDetector(
            onTap: _pop,
            child: Container(
              width: widget.config.size,
              height: widget.config.size,
              decoration: BoxDecoration(
                color: widget.config.color.withAlpha(50),
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.config.color,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.config.color.withAlpha(80),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Fireworks Reward
class FireworksReward extends StatefulWidget {
  final int rocketCount;
  final Duration duration;
  final VoidCallback onAllExploded;
  final VoidCallback? onComplete;

  const FireworksReward({
    required this.rocketCount,
    required this.duration,
    required this.onAllExploded,
    this.onComplete,
  });

  @override
  State<FireworksReward> createState() => _FireworksRewardState();
}

class _FireworksRewardState extends State<FireworksReward> {
  final List<_RocketConfig> _rockets = [];
  int _explodedCount = 0;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _generateRockets();
  }

  void _generateRockets() {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.yellow,
      Colors.purple,
      Colors.orange,
    ];

    for (int i = 0; i < widget.rocketCount; i++) {
      _rockets.add(_RocketConfig(
        initialX: 0.15 + _random.nextDouble() * 0.7,
        size: 20 + _random.nextDouble() * 15,
        color: colors[_random.nextInt(colors.length)],
        delay: Duration(milliseconds: i * 800),
      ));
    }
  }

  void _onRocketExploded() {
    setState(() => _explodedCount++);
    if (_explodedCount >= widget.rocketCount) {
      widget.onAllExploded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: _rockets.asMap().entries.map((entry) {
        return _LaunchingRocket(
          config: entry.value,
          onExploded: _onRocketExploded,
        );
      }).toList(),
    );
  }
}

class _RocketConfig {
  final double initialX;
  final double size;
  final Color color;
  final Duration delay;

  _RocketConfig({
    required this.initialX,
    required this.size,
    required this.color,
    required this.delay,
  });
}

class _LaunchingRocket extends StatefulWidget {
  final _RocketConfig config;
  final VoidCallback onExploded;

  const _LaunchingRocket({
    required this.config,
    required this.onExploded,
  });

  @override
  State<_LaunchingRocket> createState() => _LaunchingRocketState();
}

class _LaunchingRocketState extends State<_LaunchingRocket>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _launchAnimation;
  bool _hasExploded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _launchAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    Future.delayed(widget.config.delay, () {
      if (mounted) {
        _controller.forward().then((_) {
          if (mounted && !_hasExploded) {
            _explode();
          }
        });
      }
    });
  }

  void _explode() {
    setState(() => _hasExploded = true);
    widget.onExploded();
  }

  void _triggerEarlyExplosion() {
    if (!_hasExploded) {
      _controller.stop();
      _explode();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final y = _launchAnimation.value * screenHeight;
    final x = widget.config.initialX;

    return Stack(
      children: [
        if (!_hasExploded)
          Positioned(
            left: x * MediaQuery.of(context).size.width - widget.config.size / 2,
            top: y,
            child: GestureDetector(
              onTap: _triggerEarlyExplosion,
              child: Container(
                width: widget.config.size,
                height: widget.config.size * 2,
                decoration: BoxDecoration(
                  color: widget.config.color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        if (_hasExploded)
          Positioned(
            left: x * MediaQuery.of(context).size.width - 50,
            top: y - 50,
            child: _ExplosionEffect(color: widget.config.color),
          ),
      ],
    );
  }
}

class _ExplosionEffect extends StatefulWidget {
  final Color color;

  const _ExplosionEffect({required this.color});

  @override
  State<_ExplosionEffect> createState() => _ExplosionEffectState();
}

class _ExplosionEffectState extends State<_ExplosionEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    widget.color,
                    widget.color.withAlpha(0),
                  ],
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

// Candy Reward
class CandyReward extends StatefulWidget {
  final int candyCount;
  final Duration duration;
  final VoidCallback onAllCollected;
  final VoidCallback? onComplete;

  const CandyReward({
    required this.candyCount,
    required this.duration,
    required this.onAllCollected,
    this.onComplete,
  });

  @override
  State<CandyReward> createState() => _CandyRewardState();
}

class _CandyRewardState extends State<CandyReward> {
  final List<_CandyConfig> _candies = [];
  int _collectedCount = 0;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _generateCandies();
  }

  void _generateCandies() {
    final colors = [
      Colors.pink,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
    ];

    for (int i = 0; i < widget.candyCount; i++) {
      _candies.add(_CandyConfig(
        initialX: 0.1 + _random.nextDouble() * 0.8,
        size: 25 + _random.nextDouble() * 20,
        color: colors[_random.nextInt(colors.length)],
        delay: Duration(milliseconds: i * 200),
        fallDuration: widget.duration + Duration(milliseconds: _random.nextInt(1500)),
      ));
    }
  }

  void _onCandyCollected() {
    setState(() => _collectedCount++);
    if (_collectedCount >= widget.candyCount) {
      widget.onAllCollected();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: _candies.asMap().entries.map((entry) {
        return _CollectibleCandy(
          config: entry.value,
          onCollected: _onCandyCollected,
        );
      }).toList(),
    );
  }
}

class _CandyConfig {
  final double initialX;
  final double size;
  final Color color;
  final Duration delay;
  final Duration fallDuration;

  _CandyConfig({
    required this.initialX,
    required this.size,
    required this.color,
    required this.delay,
    required this.fallDuration,
  });
}

class _CollectibleCandy extends StatefulWidget {
  final _CandyConfig config;
  final VoidCallback onCollected;

  const _CollectibleCandy({
    required this.config,
    required this.onCollected,
  });

  @override
  State<_CollectibleCandy> createState() => _CollectibleCandyState();
}

class _CollectibleCandyState extends State<_CollectibleCandy>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _yAnimation;
  bool _isCollected = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.config.fallDuration,
    );

    _yAnimation = Tween<double>(
      begin: -0.2,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

    Future.delayed(widget.config.delay, () {
      if (mounted) _controller.forward();
    });

    _controller.addListener(() {
      if (_yAnimation.value >= 1.05 && !_isCollected) {
        _onOffScreen();
      }
    });
  }

  void _onOffScreen() {
    if (!_isCollected) {
      setState(() => _isCollected = true);
      widget.onCollected();
    }
  }

  void _collect() {
    if (_isCollected) return;
    setState(() => _isCollected = true);
    widget.onCollected();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCollected) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;
        final x = widget.config.initialX * screenWidth;
        final y = _yAnimation.value * screenHeight;

        return Positioned(
          left: x - widget.config.size / 2,
          top: y,
          child: GestureDetector(
            onTap: _collect,
            child: Transform.rotate(
              angle: _yAnimation.value * pi,
              child: Container(
                width: widget.config.size,
                height: widget.config.size,
                decoration: BoxDecoration(
                  color: widget.config.color,
                  borderRadius: BorderRadius.circular(widget.config.size * 0.3),
                  boxShadow: [
                    BoxShadow(
                      color: widget.config.color.withAlpha(100),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
