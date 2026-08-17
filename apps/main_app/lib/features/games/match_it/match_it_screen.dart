import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Child game screen: "Match It"
///
/// Uses a hybrid Flutter + Flame architecture:
/// - Flutter: ChildModeTopBar (progress dots + parent lock) and VoiceOverPromptBubble
/// - Flame: GameWidget hosting MatchItGame for the interactive game area
class MatchItScreen extends StatefulWidget {
  const MatchItScreen({
    super.key,
    this.assessmentContext = 'practice',
    this.onComplete,
    this.sensoryController,
    this.difficulty,
  });

  /// 'pre_assessment', 'post_assessment', or 'practice'
  final String assessmentContext;

  /// Optional difficulty (1–3) derived from the child's level. When null,
  /// the default round count is used (preserves assessment behaviour).
  final int? difficulty;
  final void Function(
    int score,
    int totalItems,
    int errorCount,
    int totalResponseTimeMs,
  )? onComplete;

  /// Optional sensory controller for per-round music/haptic during pre-assessment.
  final SensoryRoundController? sensoryController;

  @override
  State<MatchItScreen> createState() => _MatchItScreenState();
}

/// All games use a fixed 4 rounds to keep sessions short for young children.
/// (Difficulty is reserved for future per-game tuning.)
int _roundsForDifficulty(int? difficulty) => 4;

class _MatchItScreenState extends State<MatchItScreen> {
  late final int _totalRounds = _roundsForDifficulty(widget.difficulty);
  int _currentStep = 0;
  bool _showPrompt = true;
  bool _gameComplete = false;

  /// Guards against a duplicate game-complete callback recording the
  /// session (or advancing the flow) twice.
  bool _completionHandled = false;
  Offset? _lastTapPosition;
  bool _showStarSparkle = false;
  late final MatchItGame _game;

  /// Developer auto-play/skip handle. Null in a normal build.
  DeveloperGameSession? _devSession;
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

    // Apply sensory config for round 1 at game initialization (pre-assessment only)
    widget.sensoryController?.applyRoundConfig(1);

    final childId = context.read<ChildProvider>().profile?.id ?? 'unknown';
    final audioService = context.read<AudioService>();
    GameMotion.reduced = context.read<ChildProvider>().reducedMotion;
    GameObjectStyle.current = context.read<ChildProvider>().objectStyle;
    _game = MatchItGame(
      totalRounds: _totalRounds,
      childId: childId,
      // Hint policy per difficulty tier (Easy: unlimited + guided demo,
      // Medium: small budget, Hard: no answer hints). Assessment keeps the
      // fixed legacy behaviour so its telemetry stays comparable.
      profile: widget.assessmentContext == 'practice'
          ? DifficultyProfile.forLevel(widget.difficulty ?? 2)
          : DifficultyProfile.assessment,
      onStepChanged: _onStepChanged,
      onGameComplete: _onGameComplete,
      onCorrectMatch: _onCorrectMatch,
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
      onPlayCorrectVo: (label) => _voiceOverService.playAnswerLabel(
        color: label.color,
        shape: label.shape,
        letter: label.letter,
        item: label.item,
      ),
      onPlayWrongVo: () => _voiceOverService.playWrongEncouragement(),
      onPlayInstructionVo: () => _voiceOverService.play(VoiceOverCue.matchIt),
      onPlayTransitionVo: () => _voiceOverService.playTransition(),
      onPlayCelebrationVo: () => _voiceOverService.playRewardCelebration(),
    );

    _devSession = DeveloperAutomationRegistry.instance.registerGame(
      gameId: 'match_it',
      assessmentContext: widget.assessmentContext,
      game: _game,
    );
  }

  @override
  void dispose() {
    DeveloperAutomationRegistry.instance.unregister(_devSession);
    _voiceOverService.dispose();
    super.dispose();
  }

  void _onStepChanged(int step) {
    setState(() {
      _currentStep = step;
      _showPrompt = false;
      // Show star sparkle when a round is fully completed
      _showStarSparkle = true;
    });

    // Apply sensory config for the new round (pre-assessment only)
    // step is 0-based, applyRoundConfig expects 1-based
    widget.sensoryController?.applyRoundConfig(step + 1);
  }

  /// Called on each individual correct match (not just round completion).
  /// Triggers haptic feedback only (star sparkle moved to onStepChanged):
  /// - Pre-assessment: use sensory controller's per-round config
  /// - Other modes: fall back to child's vibration preference
  void _onCorrectMatch() {
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
    if (_completionHandled) return;
    _completionHandled = true;
    // Stop any developer automation from acting on a finished game.
    _devSession?.markComplete();

    setState(() => _gameComplete = true);

    // Celebrate with the child before the reward overlay lands. The overlay
    // and its barrier are transparent, so the mascot stays visible under it.
    MascotHost.maybeOf(context)?.play(MascotGesture.celebrate);

    // Trigger game-complete haptic feedback
    if (context.read<ChildProvider>().vibrationEnabled) {
      context.read<HapticService>().gameCompleteFeedback();
    }

    // Record the session in the assessment provider
    final childProvider = context.read<ChildProvider>();
    final childId = childProvider.profile?.id;

    // Attribute each round to the sensory condition that was active for it
    // before the session (and its rounds) are written.
    widget.sensoryController?.stampRoundSensoryState(analytics);

    // The write must land before the flow advances — otherwise an assessment
    // can be finalized without this game in it.
    await GameSessionRecording.record(
      context,
      childId: childId,
      gameId: 'match_it',
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
    );
    if (!mounted) return;

    // If onComplete callback is provided (game flow mode), call it instead of showing built-in reward
    if (widget.onComplete != null) {
      widget.onComplete!(score, totalItems, errorCount, totalResponseTimeMs);
      return;
    }

    // Show reward effect first, then completion dialog (normal mode)
    if (mounted) {
      _showRewardThenCompletion(score, totalItems, errorCount);
    }
  }

  void _showRewardThenCompletion(int score, int totalItems, int errorCount) {
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
          minDisplayDuration: const Duration(seconds: 10),
          showContinueButton: false, // pop-to-advance; no text button
          onComplete: () {
            Navigator.of(dialogContext).pop(); // Close reward overlay
            if (widget.assessmentContext == 'practice') {
              // Post-reward choice: play the next game or back to the lobby.
              GameEndChoiceDialog.show(context,
                  currentGameId: 'match_it');
            } else {
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
        builder: (_) => MascotHost(
          child: MatchItScreen(
            assessmentContext: widget.assessmentContext,
            sensoryController: widget.sensoryController,
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
                      .gameBackgroundFor('match_it')),
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
            onRetry:
                widget.assessmentContext == 'practice' ? _retryGame : null,
            onMenu: widget.assessmentContext == 'practice'
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
                      : 'Tap the shapes that look the same!',
              isVisible: _showPrompt || _gameComplete,
            ),
          ),
        ],
      ),
    );
  }
}
