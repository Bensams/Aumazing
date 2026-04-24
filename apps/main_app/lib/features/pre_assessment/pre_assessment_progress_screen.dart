import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/services/local_db_service.dart';
import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/scoring_service.dart';

import '../games/copy_me/copy_me_screen.dart';
import '../games/do_what_i_say/do_what_i_say_screen.dart';
import '../games/my_turn_your_turn/my_turn_your_turn_screen.dart';
import '../games/match_it/match_it_screen.dart';
import '../rewards/widgets/reward_overlay.dart';

import 'sensory/sensory.dart';
import 'waiting_for_parent_screen.dart';

/// Orchestrates the sequential pre-assessment game flow.
///
/// Runs each game one-by-one, collects metrics, then navigates
/// to the waiting-for-parent screen where the parent can review
/// the summary and proceed to the results.
///
/// Accepts a [sensoryConsentResult] from the consent dialog shown
/// on the intro screen. When accepted, a [SensoryRoundController]
/// manages per-round music/haptic toggling. When declined, the
/// parent's existing [ChildProvider] settings are used for all rounds.
class PreAssessmentProgressScreen extends StatefulWidget {
  /// The parent's consent decision from [SensoryConsentDialog].
  final SensoryConsentResult sensoryConsentResult;

  const PreAssessmentProgressScreen({
    super.key,
    required this.sensoryConsentResult,
  });

  @override
  State<PreAssessmentProgressScreen> createState() =>
      _PreAssessmentProgressScreenState();
}

class _PreAssessmentProgressScreenState
    extends State<PreAssessmentProgressScreen> {
  int _currentGameIndex = 0;
  final List<AssessmentResult> _results = [];

  /// Controls per-round sensory settings (music/haptic toggling).
  late final SensoryRoundController _sensoryController;

  /// Collected sensory round metrics across all games.
  final List<SensoryRoundMetrics> _sensoryMetrics = [];

  /// The analyzed sensory preference result (populated after all games).
  SensoryPreferenceResult? _sensoryPreferenceResult;

  @override
  void initState() {
    super.initState();
    _initSensoryController();
    _saveSensoryConsent();
  }

  /// Persist the parent's sensory consent decision to the local database.
  void _saveSensoryConsent() {
    final consentGiven =
        widget.sensoryConsentResult == SensoryConsentResult.accepted;
    localDbService.insertSensoryConsent(
      childId: _childId,
      consentGiven: consentGiven,
    );
    debugPrint(
      '[PreAssessment] Saved sensory consent: $consentGiven for $_childId',
    );
  }

  void _initSensoryController() {
    final childProvider = context.read<ChildProvider>();
    final audioService = context.read<AudioService>();

    final consentAccepted =
        widget.sensoryConsentResult == SensoryConsentResult.accepted;

    // Build the round list based on consent
    final rounds = consentAccepted
        ? SensoryRoundConfig.preAssessmentRounds
        : SensoryRoundConfig.parentDeclinedRounds(
            musicEnabled: childProvider.musicEnabled,
            hapticEnabled: childProvider.vibrationEnabled,
          );

    _sensoryController = SensoryRoundController(
      audioService: audioService,
      rounds: rounds,
      consentGiven: consentAccepted,
      originalAudioConfig: audioService.config,
      originalVibrationEnabled: childProvider.vibrationEnabled,
    );
  }

  @override
  void dispose() {
    // Restore original audio/haptic settings before disposing
    _sensoryController.dispose();
    super.dispose();
  }

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

    // Collect sensory round metrics from aggregate game data
    _collectSensoryMetrics(
      gameId: gameId,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      totalResponseTimeMs: totalResponseTimeMs,
    );

    // Show reward overlay before advancing to next game
    _showRewardThenAdvance();
  }

  /// Create sensory round metrics from aggregate game completion data.
  ///
  /// Since [_onGameComplete] receives aggregate data (not per-round), we
  /// distribute the totals evenly across the [SensoryRoundController]'s
  /// round configurations so the [SensoryPreferenceAnalyzer] can compare
  /// performance under each sensory condition.
  void _collectSensoryMetrics({
    required String gameId,
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
  }) {
    final rounds = _sensoryController.rounds;
    if (rounds.isEmpty) return;

    final itemsPerRound =
        totalItems > 0 ? (totalItems / rounds.length).ceil() : 1;
    final correctPerRound = score > 0 ? (score / rounds.length) : 0.0;
    final wrongPerRound = errorCount > 0 ? (errorCount / rounds.length) : 0.0;
    final timePerRound = totalResponseTimeMs > 0
        ? (totalResponseTimeMs / rounds.length)
        : 0.0;

    for (final round in rounds) {
      final accuracy = itemsPerRound > 0
          ? (correctPerRound / itemsPerRound).clamp(0.0, 1.0)
          : 0.0;

      _sensoryMetrics.add(SensoryRoundMetrics(
        gameId: gameId,
        roundNumber: round.roundNumber,
        sensoryConfig: round,
        correctCount: correctPerRound.round(),
        wrongCount: wrongPerRound.round(),
        accuracy: accuracy,
        totalResponseTimeMs: timePerRound.round(),
        avgResponseTimeMs:
            itemsPerRound > 0 ? timePerRound / itemsPerRound : 0.0,
        tapCount: correctPerRound.round() + wrongPerRound.round(),
        idleTimeSeconds: 0.0, // Not available from aggregate data
        randomTouchCount: 0, // Not available from aggregate data
        timeToFirstTouchMs: 0.0, // Not available from aggregate data
        timeToCompletionMs: timePerRound,
        hintCount: 0,
        promptCount: 0,
        retryCount: 0,
      ));
    }
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
    // ── Sensory preference analysis ──────────────────────────────────────
    if (_sensoryController.consentGiven && _sensoryMetrics.isNotEmpty) {
      final analyzer = SensoryPreferenceAnalyzer();
      _sensoryPreferenceResult = analyzer.analyze(_sensoryMetrics);
      debugPrint(
        '[PreAssessment] Sensory analysis complete: '
        'music=${_sensoryPreferenceResult!.recommendedMusicEnabled}, '
        'haptic=${_sensoryPreferenceResult!.recommendedHapticEnabled}, '
        'confidence=${_sensoryPreferenceResult!.confidence}',
      );

      // Save sensory round metrics to local DB
      final metricsMapList =
          _sensoryMetrics.map((m) => m.toMap()).toList();
      await localDbService.insertSensoryRoundMetrics(
        childId: _childId,
        metricsMapList: metricsMapList,
      );
      debugPrint(
        '[PreAssessment] Saved ${metricsMapList.length} sensory round metrics',
      );

      // Save sensory preference result to local DB
      await localDbService.insertSensoryPreference(
        childId: _childId,
        preferenceMap: _sensoryPreferenceResult!.toMap(),
      );
      debugPrint('[PreAssessment] Saved sensory preference result');
    }

    // Restore original audio/haptic settings now that testing is done
    await _sensoryController.restoreOriginalSettings();

    if (!mounted) return;

    // Finalize the pre-assessment: creates assessment results in local DB
    // and triggers Supabase sync via the sync service
    final assessProv = context.read<AssessmentProvider>();
    await assessProv.finalizePreAssessment(_childId);

    // Reload to get the finalized results
    await assessProv.loadAssessments(_childId);

    if (!mounted) return;

    // Call AI Assessment API for XGBoost-based prediction
    debugPrint('[PreAssessment] Calling AI Assessment API...');
    final aiResponse = await assessProv.predictWithAI(_childId);

    if (!mounted) return;

    // Use the finalized results from the provider (which have proper data)
    final finalResults = assessProv.preResults;

    // Generate profile — use AI if available, otherwise rule-based fallback
    final profile = _buildSupportProfile(aiResponse, finalResults);

    // Navigate to the waiting-for-parent screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WaitingForParentScreen(
          results: finalResults.isNotEmpty ? finalResults : _results,
          profile: profile,
          aiResponse: aiResponse,
        ),
      ),
    );
  }

  /// Build a [SupportProfile] from the AI response or rule-based fallback.
  ///
  /// When AI is available, uses [AiAssessmentResponse.supportLevel] to set
  /// nuanced levels across all developmental areas, with the primary area
  /// (matching the predicted profile) set lower than the others.
  SupportProfile _buildSupportProfile(
    AiAssessmentResponse? aiResponse,
    List<AssessmentResult> finalResults,
  ) {
    if (aiResponse != null) {
      debugPrint('[PreAssessment] ✅ Using AI-based profile: '
          '${aiResponse.profileDisplayName} '
          '(${aiResponse.confidencePercent}), '
          'support_level=${aiResponse.supportLevel}');

      // Map support_level to nuanced developmental levels
      // high → primary area 'emerging', others 'developing'
      // moderate → primary area 'developing', others 'developing'
      // low → primary area 'developing', others 'strong'
      final String primaryLevel;
      final String secondaryLevel;
      final String attentionPrimary;
      final String attentionSecondary;

      switch (aiResponse.supportLevel) {
        case 'high':
          primaryLevel = 'emerging';
          secondaryLevel = 'developing';
          attentionPrimary = 'short attention';
          attentionSecondary = 'moderate';
        case 'moderate':
          primaryLevel = 'developing';
          secondaryLevel = 'developing';
          attentionPrimary = 'moderate';
          attentionSecondary = 'moderate';
        case 'low':
        default:
          primaryLevel = 'developing';
          secondaryLevel = 'strong';
          attentionPrimary = 'moderate';
          attentionSecondary = 'sustained';
      }

      final profile = aiResponse.predictedProfile;

      return SupportProfile(
        communication: profile == 'communication_support'
            ? primaryLevel
            : secondaryLevel,
        socialInteraction: profile == 'social_support'
            ? primaryLevel
            : secondaryLevel,
        playSkills: profile == 'play_support'
            ? primaryLevel
            : secondaryLevel,
        attention: profile == 'attention_support'
            ? attentionPrimary
            : attentionSecondary,
        sensoryNotes: const [], // Don't stuff AI info into sensoryNotes
        recommendedDifficulty: aiResponse.supportLevel == 'high'
            ? 'beginner'
            : aiResponse.supportLevel == 'moderate'
                ? 'intermediate'
                : 'advanced',
        recommendedPromptStyle: aiResponse.supportLevel == 'high'
            ? 'visual'
            : aiResponse.supportLevel == 'moderate'
                ? 'combined'
                : 'verbal',
        recommendedSessionMinutes: aiResponse.supportLevel == 'high'
            ? 3
            : aiResponse.supportLevel == 'moderate'
                ? 5
                : 7,
        lowStimulationMode: profile == 'attention_support',
        turnTakingPractice: profile == 'social_support',
        promptRepetition: aiResponse.supportLevel == 'high'
            ? 3
            : aiResponse.supportLevel == 'moderate'
                ? 2
                : 1,
      );
    } else {
      // Fallback: existing rule-based scoring
      debugPrint('[PreAssessment] ⚠️ Using rule-based profile '
          '(AI unavailable)');
      const scorer = ScoringService();
      final sensorySettings =
          context.read<ChildProvider>().sensorySettingsMap;
      return scorer.generateProfile(
        results: finalResults.isNotEmpty ? finalResults : _results,
        sensorySettings: sensorySettings,
      );
    }
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
          sensoryController: _sensoryController,
          onComplete: (score, total, errors, time) =>
              _onGameComplete(gameId, score, total, errors, time),
        );
      case 'do_what_i_say':
        screen = DoWhatISayScreen(
          sensoryController: _sensoryController,
          onComplete: (score, total, errors, time, extras) =>
              _onGameComplete(gameId, score, total, errors, time, extras),
        );
      case 'my_turn_your_turn':
        screen = MyTurnYourTurnScreen(
          sensoryController: _sensoryController,
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
              sensoryController: _sensoryController,
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
