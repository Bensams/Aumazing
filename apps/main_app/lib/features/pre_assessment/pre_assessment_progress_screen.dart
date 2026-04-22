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

    // Advance or finish
    if (_currentGameIndex < _gameOrder.length - 1) {
      setState(() => _currentGameIndex++);
    } else {
      _finishAssessment();
    }
  }

  /// Called when Match It completes (it records its own session).
  /// We just need to store the result for the summary and advance.
  void _onMatchItReturned() {
    // Match It already recorded its session via AssessmentProvider.
    // Check if match_it result already exists (avoid duplicates)
    final hasMatchIt = _results.any((r) => r.gameId == 'match_it');
    if (hasMatchIt) return;

    // Match It records its own session, so we create a placeholder result.
    // The actual data is in the assessment provider's sessions.
    // We'll use default values since the real data is already persisted.
    _results.add(AssessmentResult(
      id: 'match_it_${DateTime.now().millisecondsSinceEpoch}',
      childId: _childId,
      type: 'pre',
      gameId: 'match_it',
      score: 0, // Will be overridden by finalize
      totalItems: 0,
      errorCount: 0,
      avgResponseTimeMs: 0,
      completedAt: DateTime.now(),
    ));

    // Now finish the assessment
    _finishAssessment();
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
              ],
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
        // Match It handles its own session recording and completion dialog.
        // We push it and listen for when it pops back.
        Navigator.of(context)
            .push(
          MaterialPageRoute(
            builder: (_) => const MatchItScreen(
              assessmentContext: 'pre_assessment',
            ),
          ),
        )
            .then((_) {
          // Match It has popped back — it already recorded its session
          if (mounted) {
            _onMatchItReturned();
          }
        });
        return; // Don't fall through to the generic push below
      default:
        return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}
