import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../providers/child_provider.dart';
import '../../../features/rewards/widgets/reward_overlay.dart';
import '../../home/home_screen.dart';

/// Screen wrapper for the My Turn Your Turn game during pre-assessment.
class MyTurnYourTurnScreen extends StatefulWidget {
  const MyTurnYourTurnScreen({
    super.key,
    this.assessmentContext = 'pre_assessment',
    this.onComplete,
  });

  final String assessmentContext;
  final void Function(
    int score,
    int totalItems,
    int errorCount,
    int totalResponseTimeMs,
    Map<String, dynamic> extras,
  )?
  onComplete;

  @override
  State<MyTurnYourTurnScreen> createState() => _MyTurnYourTurnScreenState();
}

class _MyTurnYourTurnScreenState extends State<MyTurnYourTurnScreen> {
  static const _totalRounds = 5;
  int _currentStep = 0;
  bool _gameComplete = false;
  bool _isBuddyTurn = true;
  String _voiceOverText = 'Wait for Buddy… 🐻';
  late final MyTurnYourTurnGame _game;

  @override
  void initState() {
    super.initState();
    final childId = context.read<ChildProvider>().profile?.id ?? 'unknown';
    _game = MyTurnYourTurnGame(
      totalRounds: _totalRounds,
      childId: childId,
      onStepChanged: (step) => setState(() => _currentStep = step),
      onTurnChanged: (isBuddy) {
        if (mounted) {
          setState(() {
            _isBuddyTurn = isBuddy;
            // Update voice over text based on whose turn it is
            _voiceOverText = isBuddy 
                ? 'Wait for Buddy… 🐻' 
                : 'Your turn! Tap a spot! ⭐';
          });
        }
      },
      // TODO: Add onBuddyTurnError callback to game_core MyTurnYourTurnGame
      // for error detection when child taps during buddy's turn
      onGameComplete: ({
        required int score,
        required int totalItems,
        required int errorCount,
        required int totalResponseTimeMs,
        required Map<String, dynamic> extras,
        GameSessionMetrics? analytics,
      }) {
        setState(() => _gameComplete = true);
        
        // If onComplete is provided (pre-assessment mode), call it directly
        // Reward overlay will show on top of this game screen
        if (widget.onComplete != null) {
          widget.onComplete!(score, totalItems, errorCount, totalResponseTimeMs, extras);
          return;
        }
        
        // Normal mode: Show reward for practice mode, just delay for assessment
        if (widget.assessmentContext == 'practice') {
          _showRewardThenPop();
        } else {
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
      },
    );
  }

  void _showRewardThenPop() {
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
            Navigator.of(dialogContext).pop(); // Close reward overlay
            Navigator.of(dialogContext).pop(); // Return to previous screen
          },
        ),
      ),
    );
  }

  Future<void> _handleParentTap() async {
    final verified = await ParentVerificationDialog.show(context);
    if (verified && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: AppGradients.myTurnYourTurn,
            ),
            child: Column(
              children: [
                ChildModeTopBar(
                  totalSteps: _totalRounds,
                  currentStep: _currentStep,
                  onParentTap: _handleParentTap,
                ),
                Expanded(
                  child: GameWidget(
                    game: _game,
                    backgroundBuilder: (_) => const SizedBox.shrink(),
                  ),
                ),
                // Voice over prompt with dynamic text based on turn
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: VoiceOverPromptBubble(
                    text: _voiceOverText,
                    isVisible: !_gameComplete,
                  ),
                ),
              ],
            ),
          ),
          // Note: GameCelebrationOverlay removed - reward overlay now handles completion celebration
        ],
      ),
    );
  }
}
