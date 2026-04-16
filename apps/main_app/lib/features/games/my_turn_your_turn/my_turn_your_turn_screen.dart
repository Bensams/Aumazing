import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

/// Screen wrapper for the My Turn Your Turn game during pre-assessment.
class MyTurnYourTurnScreen extends StatefulWidget {
  const MyTurnYourTurnScreen({
    super.key,
    this.assessmentContext = 'pre_assessment',
    this.onComplete,
  });

  final String assessmentContext;
  final void Function(int score, int totalItems, int errorCount,
      int totalResponseTimeMs, Map<String, dynamic> extras)? onComplete;

  @override
  State<MyTurnYourTurnScreen> createState() => _MyTurnYourTurnScreenState();
}

class _MyTurnYourTurnScreenState extends State<MyTurnYourTurnScreen> {
  static const _totalRounds = 5;
  int _currentStep = 0;
  bool _gameComplete = false;
  bool _isBuddyTurn = true;
  late final MyTurnYourTurnGame _game;

  @override
  void initState() {
    super.initState();
    _game = MyTurnYourTurnGame(
      totalRounds: _totalRounds,
      onStepChanged: (step) => setState(() => _currentStep = step),
      onTurnChanged: (isBuddy) {
        if (mounted) setState(() => _isBuddyTurn = isBuddy);
      },
      onGameComplete: ({
        required int score,
        required int totalItems,
        required int errorCount,
        required int totalResponseTimeMs,
        required Map<String, dynamic> extras,
      }) {
        setState(() => _gameComplete = true);
        widget.onComplete?.call(
          score, totalItems, errorCount, totalResponseTimeMs, extras,
        );
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (mounted) Navigator.of(context).pop();
        });
      },
    );
  }

  Future<void> _handleParentTap() async {
    final verified = await ParentVerificationDialog.show(context);
    if (verified && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppGradients.myTurnYourTurn),
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: VoiceOverPromptBubble(
                    text: _isBuddyTurn
                        ? 'Wait for Buddy… 🐻'
                        : 'Your turn! Tap a spot! ⭐',
                    isVisible: !_gameComplete,
                  ),
                ),
              ],
            ),
          ),
          if (_gameComplete)
            const GameCelebrationOverlay(
              emoji: '🤝',
              message: 'Great Teamwork!',
              subMessage: 'You and Buddy took turns perfectly!',
            ),
        ],
      ),
    );
  }
}
