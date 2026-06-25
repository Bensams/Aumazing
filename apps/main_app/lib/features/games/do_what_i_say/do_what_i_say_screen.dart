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

/// Screen wrapper for the Do What I Say game during pre-assessment.
class DoWhatISayScreen extends StatefulWidget {
  const DoWhatISayScreen({
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
  State<DoWhatISayScreen> createState() => _DoWhatISayScreenState();
}

int _roundsForDifficulty(int? difficulty) {
  switch (difficulty) {
    case 1:
      return 3;
    case 3:
      return 7;
    default:
      return 5;
  }
}

class _DoWhatISayScreenState extends State<DoWhatISayScreen>
    with SingleTickerProviderStateMixin {
  late final int _totalRounds = _roundsForDifficulty(widget.difficulty);
  int _currentStep = 0;
  bool _gameComplete = false;
  bool _showCelebration = false;
  Offset? _lastTapPosition;
  bool _showStarSparkle = false;
  String _instruction = 'Get ready…';
  List<VoiceOverCue> _lastInstructionCues = [];
  late AnimationController _celebrationFadeController;
  late Animation<double> _celebrationFadeAnimation;
  late final DoWhatISayGame _game;
  late final DateTime _sessionStartTime;
  late final VoiceOverService _voiceOverService;

  @override
  void initState() {
    super.initState();
    _sessionStartTime = DateTime.now();
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
    // Apply sensory config for round 1 at game initialization (pre-assessment only)
    widget.sensoryController?.applyRoundConfig(1);

    _voiceOverService = VoiceOverService();
    final childId = context.read<ChildProvider>().profile?.id ?? 'unknown';
    final audioService = context.read<AudioService>();
    GameMotion.reduced = context.read<ChildProvider>().reducedMotion;
    _game = DoWhatISayGame(
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
      onPlayInstructionVo: () => _voiceOverService.play(VoiceOverCue.listen),
      onPlayTransitionVo: () => _voiceOverService.playTransition(),
      onPlayCelebrationVo: () => _voiceOverService.playRewardCelebration(),
      // Game-specific voice-over
      onPlayListenVo: () => _voiceOverService.play(VoiceOverCue.listenCarefully),
      // Composite voice-over for instructions (e.g. "Tap the" + "Red" + "Circle")
      onPlayInstructionVoiceOver: (action, color, shape) {
        final cues = VoiceOverService.composeInstruction(
          action: action,
          color: color,
          shape: shape,
        );
        _lastInstructionCues = cues;
        _voiceOverService.playSequence(cues);
      },
      onCorrectMatch: () {
        // Trigger haptic on each correct tap (but NOT star sparkle):
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
          gameId: 'do_what_i_say',
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

        // If onComplete is provided (pre-assessment mode), show celebration then call it
        // If onComplete is null (practice mode), show celebration then show built-in reward
        if (widget.assessmentContext == 'practice' && widget.onComplete == null) {
          // Practice mode: Show celebration then built-in reward
          _fadeOutCelebrationThenShowReward();
        } else if (widget.onComplete != null) {
          // Pre-assessment mode: Show celebration then call onComplete (pre-assessment handles reward)
          _fadeOutCelebrationThenCallOnComplete(score, totalItems, errorCount, totalResponseTimeMs, enrichedExtras);
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
        builder: (_) => DoWhatISayScreen(
          assessmentContext: widget.assessmentContext,
          sensoryController: widget.sensoryController,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _celebrationFadeController.dispose();
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
                      .gameBackgroundFor('do_what_i_say')),
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

          // Flutter: Voice-over prompt (overlay)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: VoiceOverPromptBubble(
              text: _instruction,
              isVisible: !_gameComplete,
              onPlayVoiceOver: _lastInstructionCues.isNotEmpty
                  ? () => _voiceOverService.playSequence(_lastInstructionCues)
                  : null,
              autoPlayOnAppear: false, // Game handles auto-play via onPlayInstructionVoiceOver
            ),
          ),

          // Celebration overlay
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
