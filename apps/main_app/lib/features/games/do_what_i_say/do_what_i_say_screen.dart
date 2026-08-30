import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../dev/developer_automation_registry.dart';
import '../../../providers/child_provider.dart';
import '../session_recording.dart';
import '../../../features/pre_assessment/sensory/sensory.dart';
import '../../../features/rewards/widgets/reward_overlay.dart';
import '../../child_mode/game_end_choice_dialog.dart';
import '../../home/home_screen.dart';
import '../../../widgets/mascot.dart';
import '../../../widgets/mascot_host.dart';

/// Screen wrapper for the Do What I Say game during pre-assessment.
class DoWhatISayScreen extends StatefulWidget {
  const DoWhatISayScreen({
    super.key,
    this.assessmentContext = 'pre_assessment',
    this.onComplete,
    this.sensoryController,
    this.difficulty,
    this.roundsOverride,
    this.configurationVersionOverride,
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

  /// Optional per-game override of the round count; null uses the policy default.
  final int? roundsOverride;

  /// Optional override of the stamped configuration_version; null uses the policy default.
  final String? configurationVersionOverride;

  @override
  State<DoWhatISayScreen> createState() => _DoWhatISayScreenState();
}

class _DoWhatISayScreenState extends State<DoWhatISayScreen>
    with SingleTickerProviderStateMixin, GameCompletionGuard {
  late final int _totalRounds =
      widget.roundsOverride ??
      GameRoundPolicy.roundsForContext(widget.assessmentContext);
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

  /// Developer auto-play/skip handle. Null in a normal build.
  DeveloperGameSession? _devSession;
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
    _celebrationFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _celebrationFadeController,
        curve: Curves.easeOut,
      ),
    );
    // Apply sensory config for round 1 at game initialization (pre-assessment only)
    widget.sensoryController?.applyRoundConfig(1);

    _voiceOverService = VoiceOverService(
      languageCode: context.read<ChildProvider>().voiceAssetFolder,
      speed: context.read<ChildProvider>().voicePlaybackRate,
    );
    final childId = context.read<ChildProvider>().profile?.id ?? 'unknown';
    final audioService = context.read<AudioService>();
    GameMotion.reduced = context.read<ChildProvider>().reducedMotion;
    GameObjectStyle.current = context.read<ChildProvider>().objectStyle;
    _game = DoWhatISayGame(
      totalRounds: _totalRounds,
      childId: childId,
      // Hint policy per difficulty tier (Easy: unlimited + guided demo,
      // Medium: small budget, Hard: no answer hints). Assessment keeps the
      // fixed legacy behaviour so its telemetry stays comparable.
      profile:
          widget.assessmentContext == 'practice'
              ? DifficultyProfile.forLevel(widget.difficulty ?? 2)
              : DifficultyProfile.assessment,
      // Audio SFX callbacks
      onPlayCorrectSfx: () => audioService.playCorrectSfx(),
      onPlayWrongSfx: () => audioService.playWrongSfx(),
      onPlayTapSfx: () => audioService.playGameTapSfx(),
      onPlayLevelCompleteSfx: () => audioService.playLevelCompleteSfx(),
      onPlayGameCompleteSfx: () => audioService.playGameCompleteCelebration(),
      // Voice-over callbacks
      // Immediate feedback names what was just answered ("red circle");
      // praise is saved for the end-of-game reward.
      onPlayCorrectVo:
          (label) => _voiceOverService.playAnswerLabel(
            color: label.color,
            shape: label.shape,
            letter: label.letter,
            item: label.item,
          ),
      onPlayWrongVo: () => _voiceOverService.playWrongEncouragement(),
      onPlayInstructionVo: () => _voiceOverService.play(VoiceOverCue.listen),
      onPlayTransitionVo: () => _voiceOverService.playTransition(),
      onPlayCelebrationVo: () => _voiceOverService.playRewardCelebration(),
      // Game-specific voice-over
      onPlayListenVo:
          () => _voiceOverService.play(VoiceOverCue.listenCarefully),
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
      // A wrong answer gets a brief "oh, not quite" that resolves into an
      // encouraging pose — the mascot never blames or despairs at the child.
      onWrongAnswer: () => MascotHost.maybeOf(context)?.reassure(),
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
      }) async {
        // The engine can fire this more than once on a fast finish; the
        // flow past this point pops routes, so run it exactly once.
        if (!beginCompletion()) return;
        // Stop any developer automation from acting on a finished game.
        _devSession?.markComplete();

        setState(() {
          _gameComplete = true;
          _showCelebration = true;
        });

        // Celebrate with the child before the reward overlay lands. The
        // overlay and its barrier are transparent, so the mascot stays
        // visible under it.
        MascotHost.maybeOf(context)?.play(MascotGesture.celebrate);

        // Trigger game-complete haptic feedback
        if (context.read<ChildProvider>().vibrationEnabled) {
          context.read<HapticService>().gameCompleteFeedback();
        }

        // Record the session in the assessment provider
        final childProvider = context.read<ChildProvider>();
        final childId = childProvider.profile?.id;

        // Attribute each round to the sensory condition that was active for
        // it before the session (and its rounds) are written.
        widget.sensoryController?.stampRoundSensoryState(analytics);

        // The write must land before the flow advances — otherwise an
        // assessment can be finalized without this game in it.
        //
        // A failed write must never strand the child on the finished frame.
        // The record call handles its own retry dialog and no-profile warning;
        // this catch is a last-resort net for anything that escapes it (a
        // deactivated context, an unexpected throw). Either way the reward/
        // choice still runs.
        try {
          await GameSessionRecording.record(
            context,
            childId: childId,
            gameId: 'do_what_i_say',
            assessmentContext: widget.assessmentContext,
            score: score,
            totalItems: totalItems,
            errorCount: errorCount,
            totalResponseTimeMs: totalResponseTimeMs,
            startedAt: _sessionStartTime,
            analytics: analytics,
            bgMusicEnabled: childProvider.musicEnabled,
            hapticFeedbackEnabled: childProvider.vibrationEnabled,
            applySessionSensoryDefaults: widget.sensoryController == null,
            configurationVersionOverride: widget.configurationVersionOverride,
          );
        } catch (e) {
          debugPrint('[DoWhatISay] session recording failed: $e');
        }
        if (!mounted) return;

        // Include randomTouchCount in extras so pre-assessment summary can display it
        final enrichedExtras = {
          ...extras,
          'random_touch_count': analytics?.randomTouchCount ?? 0,
        };

        // If onComplete is provided (pre-assessment mode), show celebration then call it
        // If onComplete is null (practice mode), show celebration then show built-in reward
        if (widget.assessmentContext == 'practice' &&
            widget.onComplete == null) {
          // Practice mode: Show celebration then built-in reward. The reward
          // hands off to the choice dialog; re-arm the watchdog so a slow
          // session write can't cut the reward/choice short.
          armCompletionWatchdog();
          _fadeOutCelebrationThenShowReward();
        } else if (widget.onComplete != null) {
          // Pre-assessment mode: the host takes over navigation once
          // onComplete is invoked, so the watchdog stands down.
          cancelCompletionWatchdog();
          _fadeOutCelebrationThenCallOnComplete(
            score,
            totalItems,
            errorCount,
            totalResponseTimeMs,
            enrichedExtras,
          );
        } else {
          // Assessment mode without onComplete: Just delay then pop.
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (!mounted) return;
            cancelCompletionWatchdog();
            Navigator.of(context).pop();
          });
        }
      },
    );

    _devSession = DeveloperAutomationRegistry.instance.registerGame(
      gameId: 'do_what_i_say',
      assessmentContext: widget.assessmentContext,
      game: _game,
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
        widget.onComplete!(
          score,
          totalItems,
          errorCount,
          totalResponseTimeMs,
          extras,
        );
      });
    });
  }

  void _showRewardThenPop() {
    final childProvider = context.read<ChildProvider>();

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder:
          (dialogContext) => PopScope(
            canPop: false,
            child: RewardOverlay.forChild(
              profile: childProvider.profile!,
              // Longer reward so children enjoy popping it (engagement);
              // the text "Great Job" dialog has been removed.
              minDisplayDuration: const Duration(seconds: 10),
              showContinueButton: false, // pop-to-advance; no text button
              onComplete: () {
                Navigator.of(dialogContext).pop(); // Close reward overlay
                if (widget.assessmentContext == 'practice') {
                  // Post-reward choice: play the next game or back to the lobby.
                  GameEndChoiceDialog.show(
                    context,
                    currentGameId: 'do_what_i_say',
                    // The choice route is pushed → the watchdog stands down.
                    onShown: cancelCompletionWatchdog,
                  );
                } else {
                  // The screen pops immediately; disarm the watchdog so it can't
                  // fire mid-pop for a half-torn route.
                  cancelCompletionWatchdog();
                  Navigator.of(context).pop(); // Back to the lobby
                }
              },
            ),
          ),
    );
  }

  void _retryGame() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        // A pushed route leaves the old host behind, so the replacement
        // screen carries its own — without it the mascot is simply absent
        // for the whole retry, reactions included.
        builder:
            (_) => MascotHost(
              child: DoWhatISayScreen(
                assessmentContext: widget.assessmentContext,
                sensoryController: widget.sensoryController,
              ),
            ),
      ),
    );
  }

  @override
  void dispose() {
    DeveloperAutomationRegistry.instance.unregister(_devSession);
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
                    .gameBackgroundFor('do_what_i_say'),
              ),
              child: GameWidget(game: _game),
            ),
          ),

          // Three-star sparkle overlay on correct match
          if (_showStarSparkle && _lastTapPosition != null)
            ThreeStarSparkle(
              // Round-complete star always appears centred, not at last touch.
              position: Offset(
                MediaQuery.of(context).size.width / 2,
                MediaQuery.of(context).size.height / 2,
              ),
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
            onRetry: widget.assessmentContext == 'practice' ? _retryGame : null,
            onMenu:
                widget.assessmentContext == 'practice'
                    ? () => Navigator.of(context).pop()
                    : null,
          ),

          // Flutter: Voice-over prompt (overlay)
          Positioned(
            // Inside the reserved band, hard into the upper-left corner.
            top: MediaQuery.of(context).padding.top + 8,
            left: AppSpacing.md,
            child: VoiceOverPromptBubble(
              showText: context.watch<ChildProvider>().showTextPrompts,
              text: _instruction,
              isVisible: !_gameComplete,
              onPlayVoiceOver:
                  _lastInstructionCues.isNotEmpty
                      ? () =>
                          _voiceOverService.playSequence(_lastInstructionCues)
                      : null,
              autoPlayOnAppear:
                  false, // Game handles auto-play via onPlayInstructionVoiceOver
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
