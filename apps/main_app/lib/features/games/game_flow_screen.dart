import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/child_provider.dart';
import '../home/home_screen.dart';
import '../rewards/widgets/reward_overlay.dart';
import 'copy_me/copy_me_screen.dart';
import 'do_what_i_say/do_what_i_say_screen.dart';
import 'match_it/match_it_screen.dart';
import 'my_turn_your_turn/my_turn_your_turn_screen.dart';

/// Game types available in the flow
enum GameType {
  matchIt,
  copyMe,
  doWhatISay,
  myTurnYourTurn,
}

/// Screen that manages a sequence of games with rewards between them
/// Usage: GameFlowScreen(gameSequence: [GameType.copyMe, GameType.matchIt])
class GameFlowScreen extends StatefulWidget {
  final List<GameType> gameSequence;
  final VoidCallback? onComplete;
  final String flowContext;

  const GameFlowScreen({
    super.key,
    required this.gameSequence,
    this.onComplete,
    this.flowContext = 'practice',
  });

  /// Predefined practice flow: Copy Me → Match It → Do What I Say → My Turn Your Turn
  factory GameFlowScreen.practiceFlow({VoidCallback? onComplete}) {
    return GameFlowScreen(
      gameSequence: const [
        GameType.copyMe,
        GameType.matchIt,
        GameType.doWhatISay,
        GameType.myTurnYourTurn,
      ],
      flowContext: 'practice',
      onComplete: onComplete,
    );
  }

  /// Predefined mini flow: just 2 games
  factory GameFlowScreen.miniFlow({VoidCallback? onComplete}) {
    return GameFlowScreen(
      gameSequence: const [
        GameType.copyMe,
        GameType.matchIt,
      ],
      flowContext: 'practice',
      onComplete: onComplete,
    );
  }

  @override
  State<GameFlowScreen> createState() => _GameFlowScreenState();
}

class _GameFlowScreenState extends State<GameFlowScreen> {
  int _currentGameIndex = 0;

  GameType get _currentGame => widget.gameSequence[_currentGameIndex];
  bool get _isLastGame => _currentGameIndex >= widget.gameSequence.length - 1;

  void _onGameComplete() {
    // Show reward overlay
    final childProvider = context.read<ChildProvider>();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: RewardOverlay.forChild(
          profile: childProvider.profile!,
          onComplete: () {
            Navigator.of(dialogContext).pop(); // Close reward
            _continueToNext(); // Continue to next game or finish
          },
          continueButtonText: _isLastGame ? 'Finish' : 'Next Game',
        ),
      ),
    );
  }

  void _continueToNext() {
    if (_isLastGame) {
      // Flow complete - return to home or call completion callback
      widget.onComplete?.call();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } else {
      // Move to next game
      setState(() => _currentGameIndex++);
    }
  }

  Widget _buildCurrentGame() {
    switch (_currentGame) {
      case GameType.matchIt:
        return MatchItScreen(
          assessmentContext: widget.flowContext,
          onComplete: (_, __, ___, ____) => _onGameComplete(),
        );
      case GameType.copyMe:
        return CopyMeScreen(
          assessmentContext: widget.flowContext,
          onComplete: (_, __, ___, ____) => _onGameComplete(),
        );
      case GameType.doWhatISay:
        return DoWhatISayScreen(
          assessmentContext: widget.flowContext,
          onComplete: (_, __, ___, ____, ______) => _onGameComplete(),
        );
      case GameType.myTurnYourTurn:
        return MyTurnYourTurnScreen(
          assessmentContext: widget.flowContext,
          onComplete: (_, __, ___, ____, ______) => _onGameComplete(),
        );
    }
  }

  String _getGameName(GameType game) {
    switch (game) {
      case GameType.matchIt:
        return 'Match It';
      case GameType.copyMe:
        return 'Copy Me';
      case GameType.doWhatISay:
        return 'Do What I Say';
      case GameType.myTurnYourTurn:
        return 'My Turn Your Turn';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Current game
          _buildCurrentGame(),
          
          // Progress indicator overlay
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(220),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(20),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Progress dots
                    Row(
                      children: List.generate(
                        widget.gameSequence.length,
                        (index) => Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index <= _currentGameIndex
                                ? const Color(0xFF9B82C4)
                                : const Color(0xFFE0E0E0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Game counter
                    Expanded(
                      child: Text(
                        'Game ${_currentGameIndex + 1} of ${widget.gameSequence.length}: ${_getGameName(_currentGame)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
