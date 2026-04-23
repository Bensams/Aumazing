import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/assessment_result.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/scoring_service.dart';

import '../games/copy_me/copy_me_screen.dart';
import '../games/do_what_i_say/do_what_i_say_screen.dart';
import '../games/my_turn_your_turn/my_turn_your_turn_screen.dart';
import '../games/match_it/match_it_screen.dart';
import '../rewards/widgets/reward_overlay.dart';

import 'waiting_for_parent_screen.dart';

/// Orchestrates the sequential pre-assessment game flow.
///
/// Runs each game one-by-one, collects metrics, then navigates
/// to the waiting-for-parent screen where the parent can review
/// the summary and proceed to the results.
///
/// Sensory settings are read from [ChildProvider] (persisted profile)
/// rather than passed as a constructor parameter.
class PreAssessmentProgressScreen extends StatefulWidget {
  const PreAssessmentProgressScreen({super.key});

  @override
  State<PreAssessmentProgressScreen> createState() =>
      _PreAssessmentProgressScreenState();
}

class _PreAssessmentProgressScreenState
    extends State<PreAssessmentProgressScreen> {
  int _currentGameIndex = 0;
  final List<AssessmentResult> _results = [];

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

  String get _childId {
    final cp = context.read<ChildProvider>();
    return cp.profile?.id ?? 'unknown';
  }

  void _onGameComplete(
    String gameId,
    int score,
    int totalItems,
    int errorCount,
    int totalResponseTimeMs, [
    Map<String, dynamic> extras = const {},
  ]) {
    // Record session in assessment provider (persists to local DB + syncs)
    context.read<AssessmentProvider>().recordGameSession(
          childId: _childId,
          gameId: gameId,
          context: 'pre_assessment',
          score: score,
          totalItems: totalItems,
          errorCount: errorCount,
          totalResponseTimeMs: totalResponseTimeMs,
          startedAt: DateTime.now().subtract(
            Duration(milliseconds: totalResponseTimeMs),
          ),
        );

    // Store result locally for the summary
    _results.add(AssessmentResult(
      id: '${gameId}_${DateTime.now().millisecondsSinceEpoch}',
      childId: _childId,
      type: 'pre',
      gameId: gameId,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      avgResponseTimeMs:
          totalItems > 0 ? (totalResponseTimeMs / totalItems).round() : 0,
      completedAt: DateTime.now(),
      rawMetrics: extras,
    ));

    // Show reward overlay before advancing to next game
    _showRewardThenAdvance();
  }

  void _showRewardThenAdvance() {
    final childProvider = context.read<ChildProvider>();
    if (childProvider.profile == null) {
      // No profile, just advance without reward
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
          onComplete: () {
            Navigator.of(dialogContext).pop(); // Close reward overlay
            Navigator.of(context).pop(); // Pop the game screen underneath
            _advanceToNextGame(); // Move to next game lobby
          },
          showContinueButton: false, // Auto-proceed after 8 seconds, no button needed
        ),
      ),
    );
  }

  void _advanceToNextGame() {
    if (_currentGameIndex < _gameOrder.length - 1) {
      setState(() => _currentGameIndex++);
    } else {
      _finishAssessment();
    }
  }

  Future<void> _finishAssessment() async {
    // Finalize the pre-assessment: creates assessment results in local DB
    // and triggers Supabase sync via the sync service
    final assessProv = context.read<AssessmentProvider>();
    await assessProv.finalizePreAssessment(_childId);

    // Reload to get the finalized results
    await assessProv.loadAssessments(_childId);

    if (!mounted) return;

    const scorer = ScoringService();

    // Read sensory settings from the persisted child profile
    final sensorySettings = context.read<ChildProvider>().sensorySettingsMap;

    // Use the finalized results from the provider (which have proper data)
    final finalResults = assessProv.preResults;

    final profile = scorer.generateProfile(
      results: finalResults.isNotEmpty ? finalResults : _results,
      sensorySettings: sensorySettings,
    );

    // Navigate to the waiting-for-parent screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WaitingForParentScreen(
          results: finalResults.isNotEmpty ? finalResults : _results,
          profile: profile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildTransitionScreen();
  }

  /// Shows a brief transition screen before launching each game.
  /// Auto-starts after 7 seconds if user doesn't press Play.
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
            child: StatefulBuilder(
              builder: (context, setState) {
                int countdown = 7;

                // Countdown timer - updates every second
                Timer.periodic(const Duration(seconds: 1), (timer) {
                  if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
                    timer.cancel();
                    return;
                  }
                  if (countdown > 1) {
                    setState(() => countdown--);
                  } else {
                    timer.cancel();
                    _launchGame(gameId);
                  }
                });

                return SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    // Progress
                    Text(
                      'Game ${_currentGameIndex + 1} of ${_gameOrder.length}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Progress dots
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
                      'Ready to play?',
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
                      'Starting in $countdown...',
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: AppColors.primaryPurple,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _launchGame(String gameId) {
    Widget screen;
    switch (gameId) {
      case 'copy_me':
        screen = CopyMeScreen(
          onComplete: (score, total, errors, time) =>
              _onGameComplete(gameId, score, total, errors, time),
        );
      case 'do_what_i_say':
        screen = DoWhatISayScreen(
          onComplete: (score, total, errors, time, extras) =>
              _onGameComplete(gameId, score, total, errors, time, extras),
        );
      case 'my_turn_your_turn':
        screen = MyTurnYourTurnScreen(
          onComplete: (score, total, errors, time, extras) =>
              _onGameComplete(gameId, score, total, errors, time, extras),
        );
      case 'match_it':
        // Match It handles its own session recording.
        // Pass onComplete to prevent it from showing built-in reward (pre-assessment handles rewards).
        Navigator.of(context)
            .push(
          MaterialPageRoute(
            builder: (_) => MatchItScreen(
              assessmentContext: 'pre_assessment',
              onComplete: (score, total, errors, time) {
                // Call _onGameComplete to handle reward and advancement
                _onGameComplete(gameId, score, total, errors, time);
              },
            ),
          ),
        );
        return; // Match It handles its own navigation, don't fall through
      default:
        return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}
