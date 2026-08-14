import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../dev/developer_automation_registry.dart';
import '../../model/area_level.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../games/copy_me/copy_me_screen.dart';
import '../games/do_what_i_say/do_what_i_say_screen.dart';
import '../games/match_it/match_it_screen.dart';
import '../games/my_turn_your_turn/my_turn_your_turn_screen.dart';
import '../rewards/widgets/reward_overlay.dart';
import 'post_assessment_handoff_screen.dart';
import '../../widgets/mascot_host.dart';

/// Orchestrates the sequential post-assessment game flow.
///
/// Mirrors the pre-assessment: the same four games in the same order (so
/// pre/post telemetry is comparable), each played in 'post_assessment'
/// context. No sensory experiment — that only runs once, during the
/// pre-assessment. When all games finish it finalizes the post results,
/// re-runs the on-device AI so the child's levels and learning path
/// refresh to their new ability, and shows the pre-vs-post comparison.
class PostAssessmentProgressScreen extends StatefulWidget {
  const PostAssessmentProgressScreen({super.key, this.skipToFinish = false});

  /// Test seam: runs the finish-and-hand-off path as soon as the run exists,
  /// without playing four games first. That path is only reachable after the
  /// last game otherwise, which no widget test can drive — and it is the path
  /// that decides whether the child or the parent sees the results.
  @visibleForTesting
  final bool skipToFinish;

  @override
  State<PostAssessmentProgressScreen> createState() =>
      _PostAssessmentProgressScreenState();
}

/// Where the screen is in its own lifecycle.
enum _FlowState { initializing, ready, initFailed, finishing, finishFailed }

class _PostAssessmentProgressScreenState
    extends State<PostAssessmentProgressScreen> {
  int _currentGameIndex = 0;

  Timer? _countdownTimer;
  int _countdown = 7;
  bool _gameLaunched = false;

  _FlowState _flowState = _FlowState.initializing;
  String? _errorMessage;

  /// Guards the per-game completion handler against a duplicate callback.
  int? _completedGameIndex;

  /// Developer auto-play handle for the transition screen. Null in a normal
  /// build; lets automation start the pending game without waiting out the
  /// countdown.
  DeveloperFlowSession? _devFlow;

  // Same order as the pre-assessment so results are comparable per game.
  static const _gameOrder = [
    'copy_me',
    'do_what_i_say',
    'my_turn_your_turn',
    'match_it',
  ];
  static const _gameNames = [
    'Copy Me',
    'Do What I Say',
    'My Turn, Your Turn',
    'Match It',
  ];
  static const _gameEmojis = ['📋', '🗣️', '🤝', '🧩'];

  String get _childId =>
      context.read<ChildProvider>().profile?.id ?? 'unknown';

  @override
  void initState() {
    super.initState();
    // The child performs these activities — landscape like the games.
    lockParentLandscape();
    _initializeRun();
  }

  /// Creates the assessment run before anything can be played.
  ///
  /// The countdown used to start while the run was still being created, so a
  /// fast first game could be recorded with no run id and then be missing
  /// from the finalized results.
  Future<void> _initializeRun() async {
    setState(() {
      _flowState = _FlowState.initializing;
      _errorMessage = null;
    });
    try {
      await context
          .read<AssessmentProvider>()
          .startAssessmentRun(childId: _childId, type: 'post');
    } catch (e) {
      debugPrint('[PostAssessment] run initialization failed: $e');
      if (!mounted) return;
      setState(() {
        _flowState = _FlowState.initFailed;
        _errorMessage = AssessmentLabels.couldNotStart;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _flowState = _FlowState.ready);
    if (widget.skipToFinish) {
      _finishAssessment();
      return;
    }
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    DeveloperAutomationRegistry.instance.unregister(_devFlow);
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdown = 7;
    _gameLaunched = false;

    DeveloperAutomationRegistry.instance.unregister(_devFlow);
    _devFlow = DeveloperAutomationRegistry.instance.registerFlow(
      flowLabel: 'Post-Assessment',
      gameIndex: _currentGameIndex,
      gameCount: _gameOrder.length,
      launchNow: () => _launchGame(_gameOrder[_currentGameIndex]),
    );

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        _launchGame(_gameOrder[_currentGameIndex]);
      }
    });
  }

  void _launchGame(String gameId) {
    _countdownTimer?.cancel();
    if (_gameLaunched) return;
    _gameLaunched = true;
    DeveloperAutomationRegistry.instance.unregister(_devFlow);
    _devFlow = null;

    // Each game screen records its own session (with full analytics) in
    // 'post_assessment' context; onComplete only drives the flow.
    void onDone(int score, int total, int errors, int time) =>
        _onGameComplete();

    Widget screen;
    switch (gameId) {
      case 'copy_me':
        screen = CopyMeScreen(
          assessmentContext: 'post_assessment',
          onComplete: onDone,
        );
      case 'do_what_i_say':
        screen = DoWhatISayScreen(
          assessmentContext: 'post_assessment',
          onComplete: (score, total, errors, time, extras) =>
              _onGameComplete(),
        );
      case 'my_turn_your_turn':
        screen = MyTurnYourTurnScreen(
          assessmentContext: 'post_assessment',
          onComplete: (score, total, errors, time, extras) =>
              _onGameComplete(),
        );
      case 'match_it':
        screen = MatchItScreen(
          assessmentContext: 'post_assessment',
          onComplete: onDone,
        );
      default:
        return;
    }

    // The mascot keeps the child company through post-assessment too; the
    // host must sit above the game screen for its lookups to resolve.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MascotHost(child: screen)),
    );
  }

  void _onGameComplete() {
    // A second callback for the same game would pop a route that is no
    // longer there and skip a game.
    if (_completedGameIndex == _currentGameIndex) return;
    _completedGameIndex = _currentGameIndex;

    final childProvider = context.read<ChildProvider>();
    if (childProvider.profile == null) {
      Navigator.of(context).pop(); // Pop the game screen
      _advanceToNextGame();
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: RewardOverlay.forChild(
          profile: childProvider.profile!,
          showContinueButton: false,
          onComplete: () {
            Navigator.of(dialogContext).pop(); // Close reward overlay
            Navigator.of(context).pop(); // Pop the game screen underneath
            _advanceToNextGame();
          },
        ),
      ),
    );
  }

  void _advanceToNextGame() {
    if (_currentGameIndex < _gameOrder.length - 1) {
      setState(() => _currentGameIndex++);
      _startCountdown();
    } else {
      _finishAssessment();
    }
  }

  Future<void> _finishAssessment() async {
    if (_flowState == _FlowState.finishing) return;
    setState(() {
      _flowState = _FlowState.finishing;
      _errorMessage = null;
    });

    final assessProv = context.read<AssessmentProvider>();
    final childId = _childId;

    try {
      // The baseline is the frozen pre-assessment snapshot, not the current
      // "latest" prediction: by the time this runs the post prediction is
      // about to replace it, and the parent must be shown the run they were
      // originally given as "before".
      final preAreaLevels = Map<String, AreaLevel>.of(
          assessProv.preSnapshot?.prediction?.areaLevels ??
              assessProv.aiPrediction?.areaLevels ??
              const {});

      // Saves post results per game and computes the improvement summary.
      final improvement = await assessProv.finalizePostAssessment(childId);

      if (improvement['has_data'] != true) {
        if (!mounted) return;
        setState(() {
          _flowState = _FlowState.finishFailed;
          _errorMessage = assessProv.lastFinalizationError ??
              AssessmentLabels.couldNotSave;
        });
        return;
      }

      if (!mounted) return;

      // Re-run the on-device AI on the post sessions: new area levels, new
      // module recommendations, and a fresh learning path (progress resets).
      final postPrediction =
          await assessProv.predictWithAI(childId, assessmentType: 'post');

      // Freeze this run alongside the untouched pre snapshot.
      await assessProv.captureRunSnapshot(
        childId,
        assessmentType: 'post',
        prediction: postPrediction,
      );

      if (!mounted) return;
      // The child is still holding the device, so the child-facing hand-off
      // comes first; the results sit behind its verification gate.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PostAssessmentHandoffScreen(
            improvement: improvement,
            preAreaLevels: preAreaLevels,
            postAreaLevels: postPrediction?.areaLevels ?? const {},
          ),
        ),
      );
    } catch (e) {
      debugPrint('[PostAssessment] finish failed: $e');
      if (!mounted) return;
      setState(() {
        _flowState = _FlowState.finishFailed;
        _errorMessage = AssessmentLabels.couldNotSave;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_flowState) {
      _FlowState.initializing => _buildBusyScreen('Getting the games ready...'),
      _FlowState.finishing => _buildBusyScreen('Saving the results...'),
      _FlowState.initFailed => _buildErrorScreen(onRetry: _initializeRun),
      _FlowState.finishFailed => _buildErrorScreen(onRetry: _finishAssessment),
      _FlowState.ready => _buildTransitionScreen(),
    };
  }

  /// A safe placeholder while the run is being created or saved. There is
  /// deliberately no Play button here: there is nothing to play into yet.
  Widget _buildBusyScreen(String message) {
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A recoverable failure: the parent can retry, or leave without a
  /// half-finished run being presented as a real result.
  Widget _buildErrorScreen({required Future<void> Function() onRetry}) {
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('\u{1F615}', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage ?? AssessmentLabels.couldNotStart,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 220,
                      child: AppPrimaryButton(
                        label: AssessmentLabels.tryAgain,
                        icon: Icons.refresh_rounded,
                        onPressed: () => onRetry(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Not now'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransitionScreen() {
    final gameName = _gameNames[_currentGameIndex];
    final emoji = _gameEmojis[_currentGameIndex];
    final gameId = _gameOrder[_currentGameIndex];

    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Post-Assessment — Game ${_currentGameIndex + 1} of '
                    '${_gameOrder.length}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_gameOrder.length, (i) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _currentGameIndex
                              ? AppColors.mint
                              : i == _currentGameIndex
                                  ? AppColors.primaryPurple
                                  : AppColors.lavenderLight,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  Text(emoji, style: const TextStyle(fontSize: 56)),
                  const SizedBox(height: 12),
                  Text(
                    gameName,
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: AppColors.primaryPurple,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Show what you learned!',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: 220,
                    child: AppPrimaryButton(
                      label: 'Play!',
                      icon: Icons.play_arrow_rounded,
                      onPressed: () => _launchGame(gameId),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Starting in $_countdown...',
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: AppColors.primaryPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
