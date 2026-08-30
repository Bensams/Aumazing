import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../providers/child_provider.dart';
import '../session_recording.dart';
import '../../../features/pre_assessment/sensory/sensory.dart';
import '../../../features/rewards/widgets/reward_overlay.dart';
import '../../child_mode/game_end_choice_dialog.dart';
import '../../home/home_screen.dart';
import '../../../widgets/mascot.dart';
import '../../../widgets/mascot_host.dart';

/// Child game screen: "Trace It"
///
/// Uses a hybrid Flutter + Flame architecture:
/// - Flutter: ChildModeTopBar (progress dots + parent lock) and VoiceOverPromptBubble
/// - Flame: GameWidget hosting TraceItGame for the interactive game area
class TraceItScreen extends StatefulWidget {
  const TraceItScreen({
    super.key,
    this.assessmentContext = 'practice',
    this.onComplete,
    this.sensoryController,
    this.difficulty,
  });

  /// 'pre_assessment', 'post_assessment', or 'practice'
  final String assessmentContext;

  /// Optional difficulty (1–3) derived from the child's level. Also selects
  /// the glyph pool (pre-writing strokes → letters/numbers).
  final int? difficulty;
  final void Function(
    int score,
    int totalItems,
    int errorCount,
    int totalResponseTimeMs,
  )?
  onComplete;

  /// Optional sensory controller for per-round music/haptic during pre-assessment.
  final SensoryRoundController? sensoryController;

  @override
  State<TraceItScreen> createState() => _TraceItScreenState();
}

class _TraceItScreenState extends State<TraceItScreen>
    with GameCompletionGuard {
  late final int _totalRounds = GameRoundPolicy.roundsForContext(
    widget.assessmentContext,
  );
  int _currentStep = 0;
  bool _showPrompt = true;
  bool _gameComplete = false;

  bool _showStarSparkle = false;
  late final TraceItGame _game;
  late final DateTime _sessionStartTime;
  late final VoiceOverService _voiceOverService;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _sessionStartTime = DateTime.now();
    _voiceOverService = VoiceOverService(
      languageCode: context.read<ChildProvider>().voiceAssetFolder,
      speed: context.read<ChildProvider>().voicePlaybackRate,
    );

    widget.sensoryController?.applyRoundConfig(1);

    final childId = context.read<ChildProvider>().profile?.id ?? 'unknown';
    final audioService = context.read<AudioService>();
    GameMotion.reduced = context.read<ChildProvider>().reducedMotion;
    GameObjectStyle.current = context.read<ChildProvider>().objectStyle;
    _game = TraceItGame(
      totalRounds: _totalRounds,
      childId: childId,
      profile:
          widget.assessmentContext == 'practice'
              ? DifficultyProfile.forLevel(widget.difficulty ?? 2)
              : DifficultyProfile.assessment,
      onStepChanged: _onStepChanged,
      onGameComplete: _onGameComplete,
      onCorrectTrace: _onCorrectTrace,
      // A wrong answer gets a brief "oh, not quite" that resolves into an
      // encouraging pose — the mascot never blames or despairs at the child.
      onWrongAnswer: () => MascotHost.maybeOf(context)?.reassure(),
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
      onPlayInstructionVo: () => _voiceOverService.play(VoiceOverCue.followMe),
      onPlayTransitionVo: () => _voiceOverService.playTransition(),
      onPlayCelebrationVo: () => _voiceOverService.playRewardCelebration(),
    );
  }

  @override
  void dispose() {
    _voiceOverService.dispose();
    super.dispose();
  }

  void _onStepChanged(int step) {
    setState(() {
      _currentStep = step;
      _showPrompt = false;
      // Show star sparkle when a glyph is fully traced
      _showStarSparkle = true;
    });

    widget.sensoryController?.applyRoundConfig(step + 1);
  }

  /// Called on each completed stroke (not just round completion).
  void _onCorrectTrace() {
    // Nod along with the child on each correct answer.
    MascotHost.maybeOf(context)?.play(MascotGesture.nod);

    if (widget.sensoryController != null) {
      widget.sensoryController!.triggerHapticOnCorrect();
    } else if (context.read<ChildProvider>().vibrationEnabled) {
      context.read<HapticService>().correctFeedback();
    }
  }

  Future<void> _onGameComplete({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    GameSessionMetrics? analytics,
  }) async {
    // The engine can fire this more than once on a fast finish; the flow
    // past this point pops routes, so run it exactly once.
    if (!beginCompletion()) return;

    setState(() => _gameComplete = true);

    // Celebrate with the child before the reward overlay lands. The overlay
    // and its barrier are transparent, so the mascot stays visible under it.
    MascotHost.maybeOf(context)?.play(MascotGesture.celebrate);

    if (context.read<ChildProvider>().vibrationEnabled) {
      context.read<HapticService>().gameCompleteFeedback();
    }

    final childProvider = context.read<ChildProvider>();
    final childId = childProvider.profile?.id;

    // A failed write must never strand the child on the finished frame. The
    // record call handles its own retry dialog and no-profile warning; this
    // catch is a last-resort net for anything that escapes it (a deactivated
    // context, an unexpected throw). Either way the reward/choice still runs.
    try {
      await GameSessionRecording.record(
        context,
        childId: childId,
        gameId: 'trace_it',
        assessmentContext: widget.assessmentContext,
        score: score,
        totalItems: totalItems,
        errorCount: errorCount,
        totalResponseTimeMs: totalResponseTimeMs,
        startedAt: _sessionStartTime,
        analytics: analytics,
        bgMusicEnabled: childProvider.musicEnabled,
        hapticFeedbackEnabled: childProvider.vibrationEnabled,
      );
    } catch (e) {
      debugPrint('[TraceIt] session recording failed: $e');
    }
    if (!mounted) return;

    if (widget.onComplete != null) {
      // The host takes over navigation; the watchdog no longer applies.
      cancelCompletionWatchdog();
      widget.onComplete!(score, totalItems, errorCount, totalResponseTimeMs);
      return;
    }

    if (mounted) {
      // Re-arm the watchdog now that the reward is about to appear, so a slow
      // session write doesn't cut the reward/choice short.
      armCompletionWatchdog();
      // The reward overlay is about to appear; the watchdog stays armed until
      // the choice (or non-practice pop) is actually on screen.
      _showRewardThenCompletion(score, totalItems, errorCount);
    }
  }

  void _showRewardThenCompletion(int score, int totalItems, int errorCount) {
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
              minDisplayDuration: const Duration(seconds: 10),
              showContinueButton: false, // pop-to-advance; no text button
              onComplete: () {
                Navigator.of(dialogContext).pop(); // Close reward overlay
                if (widget.assessmentContext == 'practice') {
                  // Post-reward choice: play the next game or back to the lobby.
                  GameEndChoiceDialog.show(
                    context,
                    currentGameId: 'trace_it',
                    // The choice route is pushed → the watchdog stands down.
                    onShown: cancelCompletionWatchdog,
                  );
                } else {
                  // Non-practice: the screen pops immediately; disarm the watchdog
                  // so it can't fire mid-pop for a half-torn route.
                  cancelCompletionWatchdog();
                  Navigator.of(context).pop(); // Back to the lobby
                }
              },
            ),
          ),
    );
  }

  /// Replays the current game from the start (learning-path Retry).
  void _retryGame() {
    // Hold an encouraging pose while the child tries again.
    MascotHost.maybeOf(context)?.flash(MascotPose.encourage);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        // A pushed route leaves the old host behind, so the replacement
        // screen carries its own.
        builder:
            (_) => MascotHost(
              child: TraceItScreen(
                assessmentContext: widget.assessmentContext,
                sensoryController: widget.sensoryController,
                difficulty: widget.difficulty,
              ),
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
          // Flame: Game area (full screen)
          Container(
            decoration: BoxDecoration(
              gradient: context
                  .watch<ChildProvider>()
                  .activePalette
                  .gameBackgroundFor('trace_it'),
            ),
            child: GameWidget(game: _game),
          ),

          // Three-star sparkle overlay when a glyph is completed
          if (_showStarSparkle)
            ThreeStarSparkle(
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
              text:
                  _gameComplete
                      ? 'Well done! You finished the game!'
                      : 'Trace the letter with your finger!',
              isVisible: _showPrompt || _gameComplete,
            ),
          ),
        ],
      ),
    );
  }
}
