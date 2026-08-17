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

/// Child game screen: "Sabay Tayo!" (joint attention)
///
/// Uses a hybrid Flutter + Flame architecture:
/// - Flutter: ChildModeTopBar (progress dots + parent lock) and VoiceOverPromptBubble
/// - Flame: GameWidget hosting SabayTayoGame for the interactive game area
class SabayTayoScreen extends StatefulWidget {
  const SabayTayoScreen({
    super.key,
    this.assessmentContext = 'practice',
    this.onComplete,
    this.sensoryController,
    this.difficulty,
  });

  /// 'pre_assessment', 'post_assessment', or 'practice'
  final String assessmentContext;

  /// Optional difficulty (1–3) derived from the child's level. Sets how many
  /// objects are on screen and which cues the buddy gives.
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
  State<SabayTayoScreen> createState() => _SabayTayoScreenState();
}

/// All games use a fixed 4 rounds to keep sessions short for young children.
int _roundsForDifficulty(int? difficulty) => 4;

/// The sprite set the in-game buddy is drawn from.
///
/// Pinned to BPS to match `MascotHost.character`, which every caller leaves at
/// its `MascotCharacter.bps` default. That match is not cosmetic: the buddy and
/// the app's mascot are two characters on screen at the same time, and a child
/// being asked "where is he looking?" should not first have to work out how
/// many people are in the room. If the mascot ever becomes selectable, this has
/// to follow it — the same reasoning that recast the Ano'ng Susunod routine
/// cards to a single character.
const String _buddyCharacter = 'bps';

class _SabayTayoScreenState extends State<SabayTayoScreen> {
  late final int _totalRounds = _roundsForDifficulty(widget.difficulty);
  int _currentStep = 0;
  bool _showPrompt = true;
  bool _gameComplete = false;

  /// Guards against a duplicate game-complete callback recording the
  /// session (or advancing the flow) twice.
  bool _completionHandled = false;
  bool _showStarSparkle = false;
  late final SabayTayoGame _game;
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

    final childProvider = context.read<ChildProvider>();
    final childId = childProvider.profile?.id ?? 'unknown';
    final audioService = context.read<AudioService>();
    GameMotion.reduced = childProvider.reducedMotion;
    GameObjectStyle.current = childProvider.objectStyle;

    _game = SabayTayoGame(
      totalRounds: _totalRounds,
      childId: childId,
      strings: childProvider.strings,
      profile: widget.assessmentContext == 'practice'
          ? DifficultyProfile.forLevel(widget.difficulty ?? 2)
          : DifficultyProfile.assessment,
      character: _buddyCharacter,
      onStepChanged: _onStepChanged,
      onGameComplete: _onGameComplete,
      onCorrectFind: _onCorrectFind,
      // A wrong tap gets a brief "oh, not quite" that resolves into an
      // encouraging pose — the mascot never blames the child for looking in
      // the wrong place.
      onWrongAnswer: () => MascotHost.maybeOf(context)?.reassure(),
      // Audio SFX callbacks
      onPlayCorrectSfx: () => audioService.playCorrectSfx(),
      onPlayWrongSfx: () => audioService.playWrongSfx(),
      // The soft chime that opens a trial: "look at me" before "look at that".
      onPlayTapSfx: () => audioService.playGameTapSfx(),
      onPlayLevelCompleteSfx: () => audioService.playLevelCompleteSfx(),
      onPlayGameCompleteSfx: () => audioService.playGameCompleteCelebration(),
      // Voice-over callbacks. Every cue below resolves inside the child's own
      // voice pack, so the spoken language follows the language the parent set
      // in exactly the same way the on-screen text does.
      //
      // Naming the object found ("Bola") rather than praising: the object set
      // is drawn from the sari-sari catalogue precisely so these recordings
      // already exist in all three languages.
      onPlayCorrectVo: (label) =>
          _voiceOverService.playAnswerLabel(item: label.item),
      onPlayWrongVo: () => _voiceOverService.playWrongEncouragement(),
      onPlayInstructionVo: () =>
          _voiceOverService.play(VoiceOverCue.lookWhereImLooking),
      onPlayHintVo: () => _voiceOverService.play(VoiceOverCue.lookOverThere),
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
      _showStarSparkle = true;
    });

    widget.sensoryController?.applyRoundConfig(step + 1);
  }

  /// Called on each correctly-followed gaze (not just round completion).
  void _onCorrectFind() {
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
    required Map<String, dynamic> extras,
    GameSessionMetrics? analytics,
  }) async {
    // The engine can fire this more than once on a fast finish; the flow
    // past this point pops routes, so run it exactly once.
    if (_completionHandled) return;
    _completionHandled = true;

    setState(() => _gameComplete = true);

    MascotHost.maybeOf(context)?.play(MascotGesture.celebrate);

    if (context.read<ChildProvider>().vibrationEnabled) {
      context.read<HapticService>().gameCompleteFeedback();
    }

    final childProvider = context.read<ChildProvider>();
    final childId = childProvider.profile?.id;

    // The write must land before the flow advances, so a completed game is
    // never celebrated over a session that was silently lost.
    await GameSessionRecording.record(
      context,
      childId: childId,
      gameId: 'sabay_tayo',
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
    if (!mounted) return;

    if (widget.onComplete != null) {
      widget.onComplete!(score, totalItems, errorCount, totalResponseTimeMs);
      return;
    }

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
          minDisplayDuration: const Duration(seconds: 10),
          showContinueButton: false, // pop-to-advance; no text button
          onComplete: () {
            Navigator.of(dialogContext).pop(); // Close reward overlay
            if (widget.assessmentContext == 'practice') {
              GameEndChoiceDialog.show(context, currentGameId: 'sabay_tayo');
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
    MascotHost.maybeOf(context)?.flash(MascotPose.encourage);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MascotHost(
          child: SabayTayoScreen(
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
          // Flame: Game area (full screen)
          Container(
            decoration: BoxDecoration(
                gradient: context
                    .watch<ChildProvider>()
                    .activePalette
                    .gameBackgroundFor('sabay_tayo')),
            child: GameWidget(game: _game),
          ),

          // Three-star sparkle overlay when a round is completed
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
            onRetry:
                widget.assessmentContext == 'practice' ? _retryGame : null,
            onMenu: widget.assessmentContext == 'practice'
                ? () => Navigator.of(context).pop()
                : null,
          ),

          // Flutter: Voice-over prompt (overlay)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: AppSpacing.md,
            child: VoiceOverPromptBubble(
              showText: context.watch<ChildProvider>().showTextPrompts,
              text: _gameComplete
                  ? strings.sabayTayoComplete
                  : strings.sabayTayoInstruction,
              isVisible: _showPrompt || _gameComplete,
            ),
          ),
        ],
      ),
    );
  }
}
