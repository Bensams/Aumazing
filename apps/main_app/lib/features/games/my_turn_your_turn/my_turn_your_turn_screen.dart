import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../providers/assessment_provider.dart';
import '../../../providers/child_provider.dart';
import '../../../features/pre_assessment/sensory/sensory.dart';
import '../../../features/rewards/widgets/reward_overlay.dart';
import '../../home/home_screen.dart';

/// Screen wrapper for the My Turn Your Turn game during pre-assessment.
class MyTurnYourTurnScreen extends StatefulWidget {
  const MyTurnYourTurnScreen({
    super.key,
    this.assessmentContext = 'pre_assessment',
    this.onComplete,
    this.sensoryController,
    this.difficulty,
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

  /// Optional sensory controller for per-round music/haptic during pre-assessment.
  final SensoryRoundController? sensoryController;

  /// Optional difficulty (1–3) from the child's level; null keeps the default.
  final int? difficulty;

  @override
  State<MyTurnYourTurnScreen> createState() => _MyTurnYourTurnScreenState();
}

/// All games use a fixed 4 rounds to keep sessions short for young children.
/// (Difficulty is reserved for future per-game tuning.)
int _roundsForDifficulty(int? difficulty) => 4;

class _MyTurnYourTurnScreenState extends State<MyTurnYourTurnScreen> {
  late final int _totalRounds = _roundsForDifficulty(widget.difficulty);
  int _currentStep = 0;
  bool _gameComplete = false;
  bool _isBuddyTurn = true;
  Offset? _lastTapPosition;
  bool _showStarSparkle = false;
  String _voiceOverText = 'Wait for Buddy… 🐻';
  late final MyTurnYourTurnGame _game;
  late final DateTime _sessionStartTime;
  late final VoiceOverService _voiceOverService;

  @override
  void initState() {
    super.initState();
    _sessionStartTime = DateTime.now();

    // Apply sensory config for round 1 at game initialization (pre-assessment only)
    widget.sensoryController?.applyRoundConfig(1);

    _voiceOverService = VoiceOverService();
    final childId = context.read<ChildProvider>().profile?.id ?? 'unknown';
    final audioService = context.read<AudioService>();
    GameMotion.reduced = context.read<ChildProvider>().reducedMotion;
    _game = MyTurnYourTurnGame(
      totalRounds: _totalRounds,
      childId: childId,
      // Audio SFX callbacks
      onPlayCorrectSfx: () => audioService.playCorrectSfx(),
      onPlayWrongSfx: () => audioService.playWrongSfx(),
      onPlayTapSfx: () => audioService.playGameTapSfx(),
      onPlayLevelCompleteSfx: () => audioService.playLevelCompleteSfx(),
      onPlayGameCompleteSfx: () => audioService.playGameCompleteSfx(),
      // Voice-over callbacks
      onPlayCorrectVo: () => _voiceOverService.playCorrectPraise(),
      onPlayWrongVo: () => _voiceOverService.playWrongEncouragement(),
      onPlayInstructionVo: () => _voiceOverService.play(VoiceOverCue.letsTakeTurns),
      onPlayTransitionVo: () => _voiceOverService.playTransition(),
      onPlayCelebrationVo: () => _voiceOverService.playRewardCelebration(),
      // Game-specific voice-overs
      onPlayMyTurnVo: () => _voiceOverService.play(VoiceOverCue.myTurn),
      onPlayYourTurnVo: () => _voiceOverService.play(VoiceOverCue.yourTurn),
      onPlayWaitVo: () => _voiceOverService.play(VoiceOverCue.wait),
      onCorrectMatch: () {
        // Trigger haptic on each correct child turn (but NOT star sparkle):
        // - Pre-assessment: use sensory controller's per-round config
        // - Other modes: fall back to child's vibration preference
        if (widget.sensoryController != null) {
          widget.sensoryController!.triggerHapticOnCorrect();
        } else if (context.read<ChildProvider>().vibrationEnabled) {
          context.read<HapticService>().correctFeedback();
        }
      },
      onStepChanged: (step) {
        setState(() {
          _currentStep = step;
          // Show star sparkle when a round is fully completed
          _showStarSparkle = true;
        });

        // Apply sensory config for the new round (pre-assessment only)
        // step is 0-based, applyRoundConfig expects 1-based
        widget.sensoryController?.applyRoundConfig(step + 1);
      },
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

        // Trigger game-complete haptic feedback
        if (context.read<ChildProvider>().vibrationEnabled) {
          context.read<HapticService>().gameCompleteFeedback();
        }

        // Record the session in the assessment provider
        final childProvider = context.read<ChildProvider>();
        final assessmentProvider = context.read<AssessmentProvider>();
        final childId = childProvider.profile?.id ?? 'unknown';

        assessmentProvider.recordGameSession(
          childId: childId,
          gameId: 'my_turn_your_turn',
          context: widget.assessmentContext,
          score: score,
          totalItems: totalItems,
          errorCount: errorCount,
          totalResponseTimeMs: totalResponseTimeMs,
          startedAt: _sessionStartTime,
          analytics: analytics,
          bgMusicEnabled: childProvider.musicEnabled,
          hapticFeedbackEnabled: childProvider.vibrationEnabled,
        );
        
        // Include randomTouchCount in extras so pre-assessment summary can display it
        final enrichedExtras = {
          ...extras,
          'random_touch_count': analytics?.randomTouchCount ?? 0,
        };

        // If onComplete is provided (pre-assessment mode), call it directly
        // Reward overlay will show on top of this game screen
        if (widget.onComplete != null) {
          widget.onComplete!(score, totalItems, errorCount, totalResponseTimeMs, enrichedExtras);
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
            _showGameCompletion();
          },
        ),
      ),
    );
  }

  /// Practice/learning-path completion: offer Retry + Next.
  void _showGameCompletion() {
    showGameCompletionDialog(
      context,
      showRetryNext: widget.assessmentContext == 'practice',
      title: 'Great Job!',
      onRetry: _retryGame,
      onNext: () => Navigator.of(context).pop(),
    );
  }

  void _retryGame() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MyTurnYourTurnScreen(
          assessmentContext: widget.assessmentContext,
          sensoryController: widget.sensoryController,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _voiceOverService.dispose();
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
          // Flame: Game area (full screen with gradient)
          Listener(
            onPointerDown: (event) {
              setState(() {
                _lastTapPosition = event.localPosition;
              });
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: context
                    .watch<ChildProvider>()
                    .activePalette
                    .gameBackgroundFor('my_turn_your_turn'),
              ),
              child: GameWidget(game: _game),
            ),
          ),

          // Three-star sparkle overlay on correct match
          if (_showStarSparkle && _lastTapPosition != null)
            ThreeStarSparkle(
              position: _lastTapPosition!,
              onComplete: () {
                setState(() {
                  _showStarSparkle = false;
                });
              },
            ),

          // Flutter: Top bar with progress + parent lock (overlay)
          ChildModeTopBar(
            totalSteps: _totalRounds,
            currentStep: _currentStep,
            onParentTap: _handleParentTap,
            onRetry:
                widget.assessmentContext == 'practice' ? _retryGame : null,
            onMenu: widget.assessmentContext == 'practice'
                ? () => Navigator.of(context).pop()
                : null,
          ),

          // Flutter: Voice-over prompt with dynamic text based on turn (overlay)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: VoiceOverPromptBubble(
              text: _voiceOverText,
              isVisible: !_gameComplete,
            ),
          ),
          // Note: GameCelebrationOverlay removed - reward overlay now handles completion celebration
        ],
      ),
    );
  }
}
