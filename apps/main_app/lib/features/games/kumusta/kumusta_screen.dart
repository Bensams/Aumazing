import 'dart:math' as math;

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

/// Child game screen: "Kumusta!" (Greet Back)
///
/// Uses the same hybrid Flutter + Flame architecture as the other games:
/// - Flutter: ChildModeTopBar (progress dots + parent lock) and the prompt
/// - Flame: GameWidget hosting KumustaGame for the interactive area
class KumustaScreen extends StatefulWidget {
  const KumustaScreen({
    super.key,
    this.assessmentContext = 'practice',
    this.onComplete,
    this.sensoryController,
    this.difficulty,
  });

  /// 'pre_assessment', 'post_assessment', or 'practice'
  final String assessmentContext;

  /// Optional difficulty (1–3) derived from the child's level. Sets how many
  /// greetings are on screen, whether the buddy holds its gesture, and whether
  /// the child gets a turn to greet first.
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
  State<KumustaScreen> createState() => _KumustaScreenState();
}

class _KumustaScreenState extends State<KumustaScreen> {
  late final int _totalRounds = GameRoundPolicy.roundsForContext(widget.assessmentContext);
  int _currentStep = 0;
  bool _showPrompt = true;
  bool _gameComplete = false;

  /// Guards against a duplicate game-complete callback recording the
  /// session (or advancing the flow) twice.
  bool _completionHandled = false;
  bool _showSparkle = false;
  late final KumustaGame _game;
  late final DateTime _sessionStartTime;
  late final VoiceOverService _voiceOverService;

  /// The buddy for this session, chosen once. Random rather than fixed so the
  /// child meets both characters across sessions, but never mid-session: a
  /// greeting exchange is with *someone*, and swapping partners halfway would
  /// undo the point of the game.
  late final String _character =
      math.Random().nextBool() ? 'bps' : 'reiz';

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

    _game = KumustaGame(
      totalRounds: _totalRounds,
      childId: childId,
      character: _character,
      profile: widget.assessmentContext == 'practice'
          ? DifficultyProfile.forLevel(widget.difficulty ?? 2)
          : DifficultyProfile.assessment,
      onStepChanged: _onStepChanged,
      onGameComplete: _onGameComplete,
      onCorrectGreeting: _onCorrectGreeting,
      // A wrong greeting gets a brief "oh, not quite" that resolves into an
      // encouraging pose. The buddy on screen never looks disappointed, so the
      // mascot must not either.
      onWrongAnswer: () => MascotHost.maybeOf(context)?.reassure(),
      // Audio SFX callbacks
      onPlayCorrectSfx: () => audioService.playCorrectSfx(),
      onPlayWrongSfx: () => audioService.playWrongSfx(),
      onPlayTapSfx: () => audioService.playGameTapSfx(),
      onPlayLevelCompleteSfx: () => audioService.playLevelCompleteSfx(),
      onPlayGameCompleteSfx: () => audioService.playGameCompleteCelebration(),
      // Voice-over callbacks. Every cue resolves inside the child's own voice
      // pack, so the spoken language follows the parent's setting exactly as
      // the on-screen text does.
      onPlayCorrectVo: () => _voiceOverService.playCorrectPraise(),
      onPlayWrongVo: () => _voiceOverService.playWrongEncouragement(),
      // `sayHelloBack` — "Say hello back!" The instruction has to ask for an
      // *action back*, not describe the screen, because the child's job is to
      // answer a bid. `showMe` stood here first and asks for the wrong thing:
      // it is the assessment library's "demonstrate for me", which is a child
      // performing for an adult rather than returning someone's greeting.
      onPlayInstructionVo: () =>
          _voiceOverService.play(VoiceOverCue.sayHelloBack),
      // The verbal prompt rung: "Your turn." Deliberately the turn-taking cue
      // rather than "tap here" — it names the social obligation, which is the
      // thing being taught, instead of the motor act.
      onPlayHintVo: () =>
          _voiceOverService.play(VoiceOverCue.yourTurnInstruction),
      onPlayTransitionVo: () => _voiceOverService.playTransition(),
      onPlayCelebrationVo: () => _voiceOverService.playRewardCelebration(),
      onBuddyGreets: _onBuddyGreets,
    );
  }

  @override
  void dispose() {
    _voiceOverService.dispose();
    super.dispose();
  }

  /// The buddy has just offered a greeting: say it out loud.
  ///
  /// A greeting a child hears as well as sees is one they can answer from
  /// either channel, which matters for a child who processes speech more
  /// readily than gesture — or the reverse.
  void _onBuddyGreets(Greeting greeting) {
    // The mascot waves along with the buddy, so the two characters on screen
    // agree about what is happening.
    MascotHost.maybeOf(context)?.play(MascotGesture.wave);
    _voiceOverService.play(_cueFor(greeting));
  }

  /// Names the greeting the buddy is offering.
  ///
  /// These four cues are dedicated recordings ("Apir!", "Beat!"), generated
  /// through `tools/voice_gen` for all eighteen packs. They replaced borrowed
  /// cues that named the wrong thing entirely: fistBump played "Now you try"
  /// and thumbsUp played "Very good" — praise, spoken before the child had
  /// done anything, which teaches that the reward arrives regardless of the
  /// answer. wave played "Here we go", an opener rather than a greeting.
  ///
  /// Saying the gesture aloud is also the only route in for a child who cannot
  /// yet read the hand: the buddy's pose and the card glyph are both visual,
  /// so without the word there is no non-visual way to answer the bid.
  VoiceOverCue _cueFor(Greeting greeting) {
    switch (greeting) {
      case Greeting.wave:
        return VoiceOverCue.greetingWave;
      case Greeting.highFive:
        return VoiceOverCue.greetingHighFive;
      case Greeting.fistBump:
        return VoiceOverCue.greetingFistBump;
      case Greeting.thumbsUp:
        return VoiceOverCue.greetingThumbsUp;
    }
  }

  void _onStepChanged(int step) {
    setState(() {
      _currentStep = step;
      _showPrompt = false;
      _showSparkle = true;
    });

    widget.sensoryController?.applyRoundConfig(step + 1);
  }

  /// Called on each greeting the child returns correctly.
  void _onCorrectGreeting() {
    // The mascot nods along — a second person agreeing that the exchange
    // worked, which is the social reinforcement the game trades in.
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
      gameId: 'kumusta',
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
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: RewardOverlay.forChild(
          profile: childProvider.profile!,
          minDisplayDuration: const Duration(seconds: 10),
          showContinueButton: false, // pop-to-advance; no text button
          onComplete: () {
            Navigator.of(dialogContext).pop(); // Close reward overlay
            if (widget.assessmentContext == 'practice') {
              GameEndChoiceDialog.show(context, currentGameId: 'kumusta');
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
          showMascot: false, // Kumusta draws its own buddy.
          child: KumustaScreen(
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
                    .gameBackgroundFor('kumusta')),
            child: GameWidget(game: _game),
          ),

          // Three-star sparkle overlay when a round is completed
          if (_showSparkle)
            ThreeStarSparkle(
              position: Offset(
                MediaQuery.of(context).size.width / 2,
                MediaQuery.of(context).size.height / 2,
              ),
              onComplete: () {
                setState(() {
                  _showSparkle = false;
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
                  ? strings.kumustaComplete
                  : strings.kumustaInstruction,
              isVisible: _showPrompt || _gameComplete,
            ),
          ),
        ],
      ),
    );
  }
}
