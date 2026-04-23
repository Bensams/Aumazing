import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../providers/child_provider.dart';
import '../../../features/rewards/widgets/reward_overlay.dart';
import '../../home/home_screen.dart';

/// Screen wrapper for the Do What I Say game during pre-assessment.
class DoWhatISayScreen extends StatefulWidget {
  const DoWhatISayScreen({
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
  State<DoWhatISayScreen> createState() => _DoWhatISayScreenState();
}

class _DoWhatISayScreenState extends State<DoWhatISayScreen>
    with SingleTickerProviderStateMixin {
  static const _totalRounds = 5;
  int _currentStep = 0;
  bool _gameComplete = false;
  bool _showCelebration = false;
  String _instruction = 'Get ready…';
  late AnimationController _celebrationFadeController;
  late Animation<double> _celebrationFadeAnimation;
  late final DoWhatISayGame _game;

  @override
  void initState() {
    super.initState();
    _celebrationFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _celebrationFadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _celebrationFadeController,
      curve: Curves.easeOut,
    ));
    final childId = context.read<ChildProvider>().profile?.id ?? 'unknown';
    _game = DoWhatISayGame(
      totalRounds: _totalRounds,
      childId: childId,
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
        GameSessionMetrics? analytics,
      }) {
        setState(() {
          _gameComplete = true;
          _showCelebration = true;
        });
        
        // If onComplete is provided (pre-assessment mode), show celebration then call it
        // If onComplete is null (practice mode), show celebration then show built-in reward
        if (widget.assessmentContext == 'practice' && widget.onComplete == null) {
          // Practice mode: Show celebration then built-in reward
          _fadeOutCelebrationThenShowReward();
        } else if (widget.onComplete != null) {
          // Pre-assessment mode: Show celebration then call onComplete (pre-assessment handles reward)
          _fadeOutCelebrationThenCallOnComplete(score, totalItems, errorCount, totalResponseTimeMs, extras);
        } else {
          // Assessment mode without onComplete: Just delay then pop
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
      },
    );
  }

  void _fadeOutCelebrationThenShowReward() {
    // Wait 2 seconds for celebration to be visible, then fade out
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _celebrationFadeController.forward().then((_) {
        if (mounted) {
          setState(() => _showCelebration = false);
        }
        // Show reward after celebration fades
        _showRewardThenPop();
      });
    });
  }

  void _fadeOutCelebrationThenCallOnComplete(
    int score,
    int totalItems,
    int errorCount,
    int totalResponseTimeMs,
    Map<String, dynamic> extras,
  ) {
    // Wait 2 seconds for celebration to be visible, then fade out
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _celebrationFadeController.forward().then((_) {
        if (!mounted) return;
        // Call onComplete first - reward overlay will show on top of this game screen
        // The pre-assessment will handle showing reward, then popping this screen
        widget.onComplete!(score, totalItems, errorCount, totalResponseTimeMs, extras);
      });
    });
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

  @override
  void dispose() {
    _celebrationFadeController.dispose();
    super.dispose();
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
          if (_gameComplete && _showCelebration)
            FadeTransition(
              opacity: _celebrationFadeAnimation,
              child: const GameCelebrationOverlay(
                emoji: '👂',
                message: 'Great Listening!',
                subMessage: 'You followed the instructions!',
              ),
            ),
        ],
      ),
    );
  }
}
