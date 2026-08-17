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
import '../../child_mode/game_end_choice_dialog.dart';
import '../../home/home_screen.dart';
import '../../pre_assessment/sensory/sensory.dart';
import '../../rewards/widgets/reward_overlay.dart';
import '../../../widgets/mascot.dart';
import '../../../widgets/mascot_host.dart';

class TulongKaibiganScreen extends StatefulWidget {
  const TulongKaibiganScreen({
    super.key,
    this.assessmentContext = 'practice',
    this.onComplete,
    this.sensoryController,
    this.difficulty,
  });

  final String assessmentContext;
  final void Function(int score, int totalItems, int errorCount,
      int totalResponseTimeMs)? onComplete;
  final SensoryRoundController? sensoryController;
  final int? difficulty;

  @override
  State<TulongKaibiganScreen> createState() => _TulongKaibiganScreenState();
}

class _TulongKaibiganScreenState extends State<TulongKaibiganScreen> {
  int _currentStep = 0;
  bool _showPrompt = true;
  bool _gameComplete = false;

  /// Guards against a duplicate game-complete callback recording the
  /// session (or advancing the flow) twice.
  bool _completionHandled = false;
  late final int _totalRounds;
  late final TulongKaibiganGame _game;
  late final DateTime _sessionStartTime;
  late final VoiceOverService _voiceOver;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _sessionStartTime = DateTime.now();
    widget.sensoryController?.applyRoundConfig(1);
    final child = context.read<ChildProvider>();
    _voiceOver = VoiceOverService(
      languageCode: child.voiceAssetFolder,
      speed: child.voicePlaybackRate,
    );
    final config = GameConfig(
      difficulty: widget.difficulty ?? 2,
      childId: child.profile?.id ?? 'unknown',
      language: child.language,
    );
    _totalRounds = config.totalRounds;
    GameMotion.reduced = child.reducedMotion;
    GameObjectStyle.current = child.objectStyle;
    final audio = context.read<AudioService>();
    _game = TulongKaibiganGame(
      totalRounds: config.totalRounds,
      itemsPerRound: config.itemsPerRound,
      childId: config.childId,
      strings: config.strings,
      profile: widget.assessmentContext == 'practice'
          ? DifficultyProfile.forLevel(config.difficulty)
          : DifficultyProfile.assessment,
      onStepChanged: _onStepChanged,
      onGameComplete: _onGameComplete,
      onCorrectDrop: _onCorrectDrop,
      onWrongAnswer: () => MascotHost.maybeOf(context)?.reassure(),
      onPlayCorrectSfx: audio.playCorrectSfx,
      onPlayWrongSfx: audio.playWrongSfx,
      onPlayDragSfx: audio.playDragSfx,
      onPlayDropSfx: audio.playDropSfx,
      onPlayLevelCompleteSfx: audio.playLevelCompleteSfx,
      onPlayGameCompleteSfx: audio.playGameCompleteCelebration,
      onPlayCorrectVo: (label) => _voiceOver.playAnswerLabel(item: label.item),
      onPlayWrongVo: _voiceOver.playWrongEncouragement,
      onPlayRequestVo: (label) => _voiceOver.playItemRequest(label.item),
      onPlayThankYouVo: () => _voiceOver.play(VoiceOverCue.thankYouFriend),
      onPlayTransitionVo: _voiceOver.playTransition,
      onPlayCelebrationVo: _voiceOver.playRewardCelebration,
    );
  }

  @override
  void dispose() {
    _voiceOver.dispose();
    super.dispose();
  }

  void _onStepChanged(int step) {
    setState(() {
      _currentStep = step;
      _showPrompt = false;
    });

    // Per-round music and haptic intensity during pre-assessment. Every other
    // game screen does this on both the first round and each transition; only
    // driving the haptics from the controller left this one playing round 1's
    // sensory profile for the whole session.
    widget.sensoryController?.applyRoundConfig(step + 1);
  }

  void _onCorrectDrop() {
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

    setState(() => _gameComplete = true);
    MascotHost.maybeOf(context)?.play(MascotGesture.celebrate);
    final child = context.read<ChildProvider>();
    if (child.vibrationEnabled) {
      context.read<HapticService>().gameCompleteFeedback();
    }
    widget.sensoryController?.stampRoundSensoryState(analytics);
    // The write must land before the flow advances, so a completed game is
    // never celebrated over a session that was silently lost.
    await GameSessionRecording.record(
      context,
      childId: child.profile?.id,
      gameId: 'tulong_kaibigan',
      assessmentContext: widget.assessmentContext,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      totalResponseTimeMs: totalResponseTimeMs,
      startedAt: _sessionStartTime,
      analytics: analytics,
      bgMusicEnabled: child.musicEnabled,
      hapticFeedbackEnabled: child.vibrationEnabled,
      applySessionSensoryDefaults: widget.sensoryController == null,
    );
    if (!mounted) return;
    if (widget.onComplete != null) {
      widget.onComplete!(score, totalItems, errorCount, totalResponseTimeMs);
      return;
    }
    if (mounted) _showReward();
  }

  void _showReward() {
    final child = context.read<ChildProvider>();
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: RewardOverlay.forChild(
          profile: child.profile!,
          minDisplayDuration: const Duration(seconds: 10),
          showContinueButton: false,
          onComplete: () {
            Navigator.of(dialogContext).pop();
            if (widget.assessmentContext == 'practice') {
              GameEndChoiceDialog.show(context,
                  currentGameId: 'tulong_kaibigan');
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    );
  }

  void _retryGame() {
    MascotHost.maybeOf(context)?.flash(MascotPose.encourage);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => MascotHost(
        child: TulongKaibiganScreen(
          assessmentContext: widget.assessmentContext,
          sensoryController: widget.sensoryController,
          difficulty: widget.difficulty,
        ),
      ),
    ));
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
      body: Stack(children: [
        Container(
          decoration: BoxDecoration(
            gradient: context
                .watch<ChildProvider>()
                .activePalette
                .gameBackgroundFor('tulong_kaibigan'),
          ),
          child: GameWidget(game: _game),
        ),
        ChildModeTopBar(
          totalSteps: _totalRounds,
          currentStep: _currentStep,
          onParentTap: _handleParentTap,
          onRetry: widget.assessmentContext == 'practice' ? _retryGame : null,
          onMenu: widget.assessmentContext == 'practice'
              ? () => Navigator.of(context).pop()
              : null,
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: AppSpacing.md,
          child: VoiceOverPromptBubble(
            showText: context.watch<ChildProvider>().showTextPrompts,
            text: _gameComplete
                ? strings.tulongKaibiganComplete
                : strings.tulongKaibiganInstruction,
            isVisible: _showPrompt || _gameComplete,
          ),
        ),
      ]),
    );
  }
}
