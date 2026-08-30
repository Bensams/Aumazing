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

/// Child game screen: "Sari-Sari Store Sorting".
///
/// Hosts [SariSariSortGame] (a Flame drag-and-drop categorisation game) with
/// the same Flutter chrome as the other games (top bar, prompt bubble, reward).
/// Difficulty (round count + items per round) and language follow the child's
/// settings via [GameConfig].
class SariSariSortScreen extends StatefulWidget {
  const SariSariSortScreen({
    super.key,
    this.assessmentContext = 'practice',
    this.onComplete,
    this.sensoryController,
    this.difficulty,
  });

  /// 'pre_assessment', 'post_assessment', or 'practice'
  final String assessmentContext;
  final void Function(
    int score,
    int totalItems,
    int errorCount,
    int totalResponseTimeMs,
  )?
  onComplete;

  final SensoryRoundController? sensoryController;

  /// Optional difficulty (1–3) derived from the child's level; null → default.
  final int? difficulty;

  @override
  State<SariSariSortScreen> createState() => _SariSariSortScreenState();
}

class _SariSariSortScreenState extends State<SariSariSortScreen>
    with GameCompletionGuard {
  int _currentStep = 0;
  bool _showPrompt = true;
  bool _gameComplete = false;

  Offset? _lastTapPosition;
  bool _showStarSparkle = false;
  late final int _totalRounds;
  late final SariSariSortGame _game;
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

    final childProvider = context.read<ChildProvider>();
    final childId = childProvider.profile?.id ?? 'unknown';
    final audioService = context.read<AudioService>();

    // Difficulty → round/item count, plus the child's language.
    final config = GameConfig(
      difficulty: widget.difficulty ?? 2,
      childId: childId,
      language: childProvider.language,
    );
    _totalRounds = GameRoundPolicy.roundsForContext(widget.assessmentContext);

    GameMotion.reduced = childProvider.reducedMotion;
    GameObjectStyle.current = childProvider.objectStyle;
    _game = SariSariSortGame(
      totalRounds: _totalRounds,
      itemsPerRound: config.itemsPerRound,
      childId: childId,
      strings: config.strings,
      // Hint policy per difficulty tier (Easy: unlimited + guided demo,
      // Medium: small budget, Hard: no answer hints). Assessment keeps the
      // fixed legacy behaviour so its telemetry stays comparable.
      profile:
          widget.assessmentContext == 'practice'
              ? DifficultyProfile.forLevel(config.difficulty)
              : DifficultyProfile.assessment,
      onStepChanged: _onStepChanged,
      onGameComplete: _onGameComplete,
      onCorrectDrop: _onCorrectDrop,
      // A wrong answer gets a brief "oh, not quite" that resolves into an
      // encouraging pose — the mascot never blames or despairs at the child.
      onWrongAnswer: () => MascotHost.maybeOf(context)?.reassure(),
      // Audio SFX
      onPlayCorrectSfx: () => audioService.playCorrectSfx(),
      onPlayWrongSfx: () => audioService.playWrongSfx(),
      onPlayDragSfx: () => audioService.playDragSfx(),
      onPlayDropSfx: () => audioService.playDropSfx(),
      onPlayLevelCompleteSfx: () => audioService.playLevelCompleteSfx(),
      onPlayGameCompleteSfx: () => audioService.playGameCompleteCelebration(),
      // Voice-over
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
      onPlayTransitionVo: () => _voiceOverService.playTransition(),
      onPlayCelebrationVo: () => _voiceOverService.playRewardCelebration(),
    );

    // The character watches the item the child is holding travel to the
    // basket, so the drag is something someone is paying attention to rather
    // than a thing the child does alone.
    _game.dragFocus.addListener(_followDraggedItem);
  }

  /// Resolved once rather than per frame — the gaze updates every tick of a
  /// drag, and this walks the element tree to find the host.
  MascotController? _mascot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mascot = MascotHost.maybeOf(context);
  }

  void _followDraggedItem() => _mascot?.watch(_game.dragFocus.value);

  @override
  void dispose() {
    // Before the GameWidget tears the game down and disposes the notifier.
    _game.dragFocus.removeListener(_followDraggedItem);
    _voiceOverService.dispose();
    super.dispose();
  }

  void _onStepChanged(int step) {
    setState(() {
      _currentStep = step;
      _showPrompt = false;
      _showStarSparkle = true;
    });
  }

  void _onCorrectDrop() {
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
        gameId: 'sari_sari_sort',
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
      debugPrint('[SariSariSort] session recording failed: $e');
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
                    currentGameId: 'sari_sari_sort',
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

  void _retryGame() {
    // Hold an encouraging pose while the child tries again.
    MascotHost.maybeOf(context)?.flash(MascotPose.encourage);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        // A pushed route leaves the old host behind, so the replacement
        // screen carries its own.
        builder:
            (_) => MascotHost(
              child: SariSariSortScreen(
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
    final strings = context.watch<ChildProvider>().strings;
    return Scaffold(
      body: Stack(
        children: [
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
                    .gameBackgroundFor('sari_sari_sort'),
              ),
              child: GameWidget(game: _game),
            ),
          ),

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

          Positioned(
            // Inside the reserved band, hard into the upper-left corner.
            top: MediaQuery.of(context).padding.top + 8,
            left: AppSpacing.md,
            child: VoiceOverPromptBubble(
              showText: context.watch<ChildProvider>().showTextPrompts,
              text:
                  _gameComplete
                      ? 'Well done! You finished the game!'
                      : strings.sortInstruction,
              isVisible: _showPrompt || _gameComplete,
            ),
          ),
        ],
      ),
    );
  }
}
