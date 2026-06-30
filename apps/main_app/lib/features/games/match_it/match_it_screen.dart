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
  Offset? _lastTapPosition;
  bool _showStarSparkle = false;
  late final MatchItGame _game;
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

    // Apply sensory config for round 1 at game initialization (pre-assessment only)
    widget.sensoryController?.applyRoundConfig(1);

    final childId = context.read<ChildProvider>().profile?.id ?? 'unknown';
    final audioService = context.read<AudioService>();
    GameMotion.reduced = context.read<ChildProvider>().reducedMotion;
    _game = MatchItGame(
      totalRounds: _totalRounds,
      childId: childId,
      onStepChanged: _onStepChanged,
      onGameComplete: _onGameComplete,
      onCorrectMatch: _onCorrectMatch,
      // Audio SFX callbacks
      onPlayCorrectSfx: () => audioService.playCorrectSfx(),
      onPlayWrongSfx: () => audioService.playWrongSfx(),
      onPlayTapSfx: () => audioService.playGameTapSfx(),
      onPlayLevelCompleteSfx: () => audioService.playLevelCompleteSfx(),
      onPlayGameCompleteSfx: () => audioService.playGameCompleteSfx(),
      // Voice-over callbacks
      onPlayCorrectVo: () => _voiceOverService.playCorrectPraise(),
      onPlayWrongVo: () => _voiceOverService.playWrongEncouragement(),
      onPlayInstructionVo: () => _voiceOverService.play(VoiceOverCue.matchIt),
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
      gameId: 'match_it',
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
            Navigator.of(context).pop(); // Back to the lobby
          },
        ),
      ),
    );
  }

  /// Replays the current game from the start (learning-path Retry).
  void _retryGame() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MatchItScreen(
          assessmentContext: widget.assessmentContext,
          sensoryController: widget.sensoryController,
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
