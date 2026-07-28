import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/area_level.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../games/copy_me/copy_me_screen.dart';
import '../games/do_what_i_say/do_what_i_say_screen.dart';
import '../games/match_it/match_it_screen.dart';
import '../games/my_turn_your_turn/my_turn_your_turn_screen.dart';
import '../rewards/widgets/reward_overlay.dart';
import 'post_assessment_result_screen.dart';

/// Orchestrates the sequential post-assessment game flow.
///
/// Mirrors the pre-assessment: the same four games in the same order (so
/// pre/post telemetry is comparable), each played in 'post_assessment'
/// context. No sensory experiment — that only runs once, during the
/// pre-assessment. When all games finish it finalizes the post results,
/// re-runs the on-device AI so the child's levels and learning path
/// refresh to their new ability, and shows the pre-vs-post comparison.
class PostAssessmentProgressScreen extends StatefulWidget {
  const PostAssessmentProgressScreen({super.key});

  @override
  State<PostAssessmentProgressScreen> createState() =>
      _PostAssessmentProgressScreenState();
}

class _PostAssessmentProgressScreenState
    extends State<PostAssessmentProgressScreen> {
  int _currentGameIndex = 0;

  Timer? _countdownTimer;
  int _countdown = 7;
  bool _gameLaunched = false;
  bool _finishing = false;

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
    context.read<AssessmentProvider>().startAssessmentRun(
          childId: _childId,
          type: 'post',
        );
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdown = 7;
    _gameLaunched = false;

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

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _onGameComplete() {
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
    if (_finishing) return;
    setState(() => _finishing = true);

    final assessProv = context.read<AssessmentProvider>();
    final childId = _childId;

    // Capture the pre-assessment area levels BEFORE the new prediction
    // overwrites them — they're the baseline of the comparison.
    final preAreaLevels = Map<String, AreaLevel>.of(
        assessProv.aiPrediction?.areaLevels ?? const {});

    // Saves post results per game and computes the improvement summary.
    final improvement = await assessProv.finalizePostAssessment(childId);

    if (!mounted) return;

    // Re-run the on-device AI on the post sessions: new area levels, new
    // module recommendations, and a fresh learning path (progress resets).
    final postPrediction = await assessProv.predictWithAI(childId);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PostAssessmentResultScreen(
          improvement: improvement,
          preAreaLevels: preAreaLevels,
          postAreaLevels: postPrediction?.areaLevels ?? const {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_finishing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _buildTransitionScreen();
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
