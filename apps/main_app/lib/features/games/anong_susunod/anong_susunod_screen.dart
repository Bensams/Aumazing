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
import '../../child_mode/game_end_choice_dialog.dart';
import '../../home/home_screen.dart';
import '../../../widgets/mascot.dart';
import '../../../widgets/mascot_host.dart';

/// Child game screen: "Ano'ng Susunod?" (What's Next?)
///
/// Uses a hybrid Flutter + Flame architecture:
/// - Flutter: ChildModeTopBar (progress dots + parent lock) and VoiceOverPromptBubble
/// - Flame: GameWidget hosting AnongSusunodGame for the interactive game area
class AnongSusunodScreen extends StatefulWidget {
  const AnongSusunodScreen({
    super.key,
    this.assessmentContext = 'practice',
    this.onComplete,
    this.sensoryController,
    this.difficulty,
  });

  /// 'pre_assessment', 'post_assessment', or 'practice'
  final String assessmentContext;

  /// Optional difficulty (1–3) derived from the child's level. Sets how many
  /// steps are pre-placed and whether cards may be seated out of order.
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
  State<AnongSusunodScreen> createState() => _AnongSusunodScreenState();
}

/// All games use a fixed 4 rounds to keep sessions short for young children.
int _roundsForDifficulty(int? difficulty) => 4;

class _AnongSusunodScreenState extends State<AnongSusunodScreen> {
  late final int _totalRounds = _roundsForDifficulty(widget.difficulty);
  int _currentStep = 0;
  bool _showPrompt = true;
  bool _gameComplete = false;
  bool _showStarSparkle = false;

  /// The current routine's name, already in the child's language. Null until
  /// the game has laid out its first round.
  String? _routineTitle;
  late final AnongSusunodGame _game;
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

    final config = GameConfig(
      difficulty: widget.difficulty ?? 2,
      childId: childId,
      language: childProvider.language,
    );

    GameMotion.reduced = childProvider.reducedMotion;
    GameObjectStyle.current = childProvider.objectStyle;

    _game = AnongSusunodGame(
      totalRounds: _totalRounds,
      childId: childId,
      profile: widget.assessmentContext == 'practice'
          ? DifficultyProfile.forLevel(widget.difficulty ?? 2)
          : DifficultyProfile.assessment,
      strings: config.strings,
      onStepChanged: _onStepChanged,
      onGameComplete: _onGameComplete,
      onCorrectPlacement: _onCorrectPlacement,
      onRoutineChanged: _onRoutineChanged,
      onWrongAnswer: () => MascotHost.maybeOf(context)?.reassure(),
      // Audio SFX callbacks
      onPlayCorrectSfx: () => audioService.playCorrectSfx(),
      onPlayWrongSfx: () => audioService.playWrongSfx(),
      onPlayTapSfx: () => audioService.playGameTapSfx(),
      onPlayLevelCompleteSfx: () => audioService.playLevelCompleteSfx(),
      onPlayGameCompleteSfx: () => audioService.playGameCompleteCelebration(),
      // Voice-over callbacks. `whatComesNext` already exists in the assessment
      // cue set and is literally this game's title, so no new recording is
      // needed for the instruction.
      //
      // A correct placement is answered by naming the step the child just put
      // down — "Maghugas ng kamay" — rather than with praise. The recording
      // comes out of the child's own voice pack, so the spoken step name is in
      // the same language as the word printed on the card.
      onPlayCorrectVo: (label) =>
          _voiceOverService.playAnswerLabel(routineStep: label.routineStep),
      onPlayWrongVo: () => _voiceOverService.playWrongEncouragement(),
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

  /// Called as each round opens, with the routine the round will run.
  ///
  /// The opening round names the routine and then asks the question; later
  /// rounds only name the routine, because by then the child has been asked it
  /// three times and the answer is the same each round.
  void _onRoutineChanged(
      String routineId, String routineTitle, bool isFirstRound) {
    if (!mounted) return;
    setState(() => _routineTitle = routineTitle);
    _voiceOverService.playRoutineTitle(routineId, alsoAsk: isFirstRound);
  }

  /// Called on each correct card placement (not just round completion).
  void _onCorrectPlacement() {
    MascotHost.maybeOf(context)?.play(MascotGesture.nod);

    if (widget.sensoryController != null) {
      widget.sensoryController!.triggerHapticOnCorrect();
    } else if (context.read<ChildProvider>().vibrationEnabled) {
      context.read<HapticService>().correctFeedback();
    }
  }

  void _onGameComplete({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required Map<String, dynamic> extras,
    GameSessionMetrics? analytics,
  }) {
    setState(() => _gameComplete = true);

    MascotHost.maybeOf(context)?.play(MascotGesture.celebrate);

    if (context.read<ChildProvider>().vibrationEnabled) {
      context.read<HapticService>().gameCompleteFeedback();
    }

    final childProvider = context.read<ChildProvider>();
    final assessmentProvider = context.read<AssessmentProvider>();
    final childId = childProvider.profile?.id ?? 'unknown';

    assessmentProvider.recordGameSession(
      childId: childId,
      gameId: 'anong_susunod',
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
              GameEndChoiceDialog.show(context, currentGameId: 'anong_susunod');
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
          child: AnongSusunodScreen(
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

  /// The caption in the prompt bubble, in the child's language.
  ///
  /// The routine's name leads, exactly as the spoken opening does, so the
  /// written and heard versions of the prompt are the same sentence.
  String _promptText(AppStrings strings) {
    if (_gameComplete) return strings.anongSusunodComplete;
    final title = _routineTitle;
    final question = strings.anongSusunodInstruction;
    return title == null ? question : '$title. $question';
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
                    .gameBackgroundFor('anong_susunod')),
            child: GameWidget(game: _game),
          ),

          // Three-star sparkle overlay when a routine is completed
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
              text: _promptText(strings),
              isVisible: _showPrompt || _gameComplete,
            ),
          ),
        ],
      ),
    );
  }
}
