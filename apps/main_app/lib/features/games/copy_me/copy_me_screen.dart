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

/// Screen wrapper for the Copy Me game during pre-assessment.
class CopyMeScreen extends StatefulWidget {
  const CopyMeScreen({
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
  )?
  onComplete;

  /// Optional sensory controller for per-round music/haptic during pre-assessment.
  final SensoryRoundController? sensoryController;

  /// Optional difficulty (1–3) from the child's level; null keeps the default.
  final int? difficulty;

  @override
  State<CopyMeScreen> createState() => _CopyMeScreenState();
}

/// All games use a fixed 4 rounds to keep sessions short for young children.
/// (Difficulty is reserved for future per-game tuning.)
int _roundsForDifficulty(int? difficulty) => 4;

class _CopyMeScreenState extends State<CopyMeScreen>
    with SingleTickerProviderStateMixin {
  late final int _totalRounds = _roundsForDifficulty(widget.difficulty);
  int _currentStep = 0;
  bool _gameComplete = false;
  bool _isDemoPhase = true;
  bool _showCelebration = false;
  Offset? _lastTapPosition;
  bool _showStarSparkle = false;
  late AnimationController _celebrationFadeController;
  late Animation<double> _celebrationFadeAnimation;
  late final CopyMeGame _game;
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
    _game = CopyMeGame(
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
      onPlayInstructionVo: () => _voiceOverService.play(VoiceOverCue.copyMe),
      onPlayTransitionVo: () => _voiceOverService.playTransition(),
      onPlayCelebrationVo: () => _voiceOverService.playRewardCelebration(),
      // Game-specific voice-overs
      onPlayMyTurnVo: () => _voiceOverService.play(VoiceOverCue.watchMeFirst),
      onPlayYourTurnVo: () => _voiceOverService.play(VoiceOverCue.nowYouTry),
      // Sequence highlight shimmer SFX
      onPlaySequenceHighlightSfx: (position) => audioService.playSequenceShimmerSfx(position),
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
          // Show star sparkle when a round/sequence is fully completed
          _showStarSparkle = true;
        });

        // Apply sensory config for the new round (pre-assessment only)
        // step is 0-based, applyRoundConfig expects 1-based
        widget.sensoryController?.applyRoundConfig(step + 1);
      },
      onGameComplete: ({
        required int score,
        required int totalItems,
        required int errorCount,
        required int totalResponseTimeMs,
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
          gameId: 'copy_me',
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
        
        // If onComplete is provided (pre-assessment mode), show celebration then call it
        // If onComplete is null (practice mode), show celebration then show built-in reward
        if (widget.assessmentContext == 'practice' && widget.onComplete == null) {
          // Practice mode: Show celebration then built-in reward
          _fadeOutCelebrationThenShowReward();
        } else if (widget.onComplete != null) {
          // Pre-assessment mode: Show celebration then call onComplete (pre-assessment handles reward)
          _fadeOutCelebrationThenCallOnComplete(score, totalItems, errorCount, totalResponseTimeMs);
        } else {
          // Assessment mode without onComplete: Just delay then pop
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
      },
    );
    _game.onPhaseChanged = (isDemo) {
      if (mounted) setState(() => _isDemoPhase = isDemo);
    };
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
  ) {
    // Wait for celebration to be visible for 2 seconds, then fade out
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _celebrationFadeController.forward().then((_) {
        if (!mounted) return;
        // Call onComplete first - reward overlay will show on top of this game screen
        // The pre-assessment will handle showing reward, then popping this screen
        widget.onComplete!(score, totalItems, errorCount, totalResponseTimeMs);
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
          // Longer reward so children enjoy popping it (engagement);
          // the text "Great Job" dialog has been removed.
          minDisplayDuration: const Duration(seconds: 7),
          onComplete: () {
            Navigator.of(dialogContext).pop(); // Close reward overlay
            Navigator.of(context).pop(); // Back to the lobby
          },
        ),
      ),
    );
  }

  void _retryGame() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CopyMeScreen(
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
                      .gameBackgroundFor('copy_me')),
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
              text:
                  _isDemoPhase
                      ? 'Watch carefully…'
                      : 'Your turn! Tap the shapes!',
              isVisible: !_gameComplete,
            ),
          ),

          // Celebration overlay
          if (_gameComplete && _showCelebration)
            FadeTransition(
              opacity: _celebrationFadeAnimation,
              child: const GameCelebrationOverlay(
                emoji: '🧠',
                message: 'Great Memory!',
                subMessage: 'You copied the sequence perfectly!',
              ),
            ),
        ],
      ),
    );
  }
}
