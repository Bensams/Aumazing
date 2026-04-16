import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

/// Screen wrapper for the Copy Me game during pre-assessment.
class CopyMeScreen extends StatefulWidget {
  const CopyMeScreen({
    super.key,
    this.assessmentContext = 'pre_assessment',
    this.onComplete,
  });

  final String assessmentContext;
  final void Function(int score, int totalItems, int errorCount,
      int totalResponseTimeMs)? onComplete;

  @override
  State<CopyMeScreen> createState() => _CopyMeScreenState();
}

class _CopyMeScreenState extends State<CopyMeScreen> {
  static const _totalRounds = 5;
  int _currentStep = 0;
  bool _gameComplete = false;
  bool _isDemoPhase = true;
  late final CopyMeGame _game;

  @override
  void initState() {
    super.initState();
    _game = CopyMeGame(
      totalRounds: _totalRounds,
      onStepChanged: (step) => setState(() {
        _currentStep = step;
      }),
      onGameComplete: ({
        required int score,
        required int totalItems,
        required int errorCount,
        required int totalResponseTimeMs,
      }) {
        setState(() => _gameComplete = true);
        widget.onComplete?.call(score, totalItems, errorCount, totalResponseTimeMs);
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (mounted) Navigator.of(context).pop();
        });
      },
    );
    _game.onPhaseChanged = (isDemo) {
      if (mounted) setState(() => _isDemoPhase = isDemo);
    };
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
            decoration: const BoxDecoration(gradient: AppGradients.copyMe),
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
                    text: _isDemoPhase
                        ? 'Watch carefully…'
                        : 'Your turn! Tap the shapes!',
                    isVisible: !_gameComplete,
                  ),
                ),
              ],
            ),
          ),
          if (_gameComplete)
            const GameCelebrationOverlay(
              emoji: '🧠',
              message: 'Great Memory!',
              subMessage: 'You copied the sequence perfectly!',
            ),
        ],
      ),
    );
  }
}
