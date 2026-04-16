import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

/// Screen wrapper for the Do What I Say game during pre-assessment.
class DoWhatISayScreen extends StatefulWidget {
  const DoWhatISayScreen({
    super.key,
    this.assessmentContext = 'pre_assessment',
    this.onComplete,
  });

  final String assessmentContext;
  final void Function(int score, int totalItems, int errorCount,
      int totalResponseTimeMs, Map<String, dynamic> extras)? onComplete;

  @override
  State<DoWhatISayScreen> createState() => _DoWhatISayScreenState();
}

class _DoWhatISayScreenState extends State<DoWhatISayScreen> {
  static const _totalRounds = 5;
  int _currentStep = 0;
  bool _gameComplete = false;
  String _instruction = 'Get ready…';
  late final DoWhatISayGame _game;

  @override
  void initState() {
    super.initState();
    _game = DoWhatISayGame(
      totalRounds: _totalRounds,
      onStepChanged: (step) => setState(() => _currentStep = step),
      onInstructionChanged: (text) {
        if (mounted) setState(() => _instruction = text);
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
            decoration: const BoxDecoration(gradient: AppGradients.doWhatISay),
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
                    text: _instruction,
                    isVisible: !_gameComplete,
                  ),
                ),
              ],
            ),
          ),
          if (_gameComplete)
            const GameCelebrationOverlay(
              emoji: '👂',
              message: 'Great Listening!',
              subMessage: 'You followed the instructions!',
            ),
        ],
      ),
    );
  }
}
