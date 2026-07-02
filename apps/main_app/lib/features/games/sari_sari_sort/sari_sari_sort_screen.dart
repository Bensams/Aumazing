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
  )? onComplete;

  final SensoryRoundController? sensoryController;

  /// Optional difficulty (1–3) derived from the child's level; null → default.
  final int? difficulty;

  @override
  State<SariSariSortScreen> createState() => _SariSariSortScreenState();
}

class _SariSariSortScreenState extends State<SariSariSortScreen> {
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
    _voiceOverService = VoiceOverService();

    final childProvider = context.read<ChildProvider>();
    final childId = childProvider.profile?.id ?? 'unknown';
    final audioService = context.read<AudioService>();

    // Difficulty → round/item count, plus the child's language.
    final config = GameConfig(
      difficulty: widget.difficulty ?? 2,
      childId: childId,
      language: childProvider.language,
    );
    _totalRounds = config.totalRounds;

    GameMotion.reduced = childProvider.reducedMotion;
    _game = SariSariSortGame(
      totalRounds: config.totalRounds,
      itemsPerRound: config.itemsPerRound,
      childId: childId,
      strings: config.strings,
      // Hint policy per difficulty tier (Easy: unlimited + guided demo,
      // Medium: small budget, Hard: no answer hints). Assessment keeps the
      // fixed legacy behaviour so its telemetry stays comparable.
      profile: widget.assessmentContext == 'practice'
          ? DifficultyProfile.forLevel(config.difficulty)
          : DifficultyProfile.assessment,
      onStepChanged: _onStepChanged,
      onGameComplete: _onGameComplete,
      onCorrectDrop: _onCorrectDrop,
      // Audio SFX
      onPlayCorrectSfx: () => audioService.playCorrectSfx(),
      onPlayWrongSfx: () => audioService.playWrongSfx(),
      onPlayDragSfx: () => audioService.playDragSfx(),
      onPlayDropSfx: () => audioService.playDropSfx(),
      onPlayLevelCompleteSfx: () => audioService.playLevelCompleteSfx(),
      onPlayGameCompleteSfx: () => audioService.playGameCompleteSfx(),
      // Voice-over
      onPlayCorrectVo: () => _voiceOverService.playCorrectPraise(),
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
  }

  void _onCorrectDrop() {
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
    GameSessionMetrics? analytics,
  }) {
    setState(() => _gameComplete = true);

    if (context.read<ChildProvider>().vibrationEnabled) {
      context.read<HapticService>().gameCompleteFeedback();
    }

    final childProvider = context.read<ChildProvider>();
    final assessmentProvider = context.read<AssessmentProvider>();
    final childId = childProvider.profile?.id ?? 'unknown';

    assessmentProvider.recordGameSession(
      childId: childId,
      gameId: 'sari_sari_sort',
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
          // Longer reward so children enjoy popping it (engagement);
          // the text "Great Job" dialog has been removed.
          minDisplayDuration: const Duration(seconds: 10),
          showContinueButton: false, // pop-to-advance; no text button
          onComplete: () {
            Navigator.of(dialogContext).pop(); // Close reward overlay
            if (widget.assessmentContext == 'practice') {
              // Post-reward choice: play the next game or back to the lobby.
              GameEndChoiceDialog.show(context,
                  currentGameId: 'sari_sari_sort');
            } else {
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
        builder: (_) => SariSariSortScreen(
          assessmentContext: widget.assessmentContext,
          sensoryController: widget.sensoryController,
          difficulty: widget.difficulty,
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
                      .gameBackgroundFor('sari_sari_sort')),
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
            onRetry:
                widget.assessmentContext == 'practice' ? _retryGame : null,
            onMenu: widget.assessmentContext == 'practice'
                ? () => Navigator.of(context).pop()
                : null,
          ),

          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: VoiceOverPromptBubble(
              text: _gameComplete
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
