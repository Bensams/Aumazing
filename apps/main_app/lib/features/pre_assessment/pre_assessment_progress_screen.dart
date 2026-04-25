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
import '../../services/rubric/rubric_labels.dart';

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
    _startAssessmentRun();
  }

  /// Create an assessment run record so all sessions and results
  /// are linked together under a single run ID.
  void _startAssessmentRun() {
    final assessProv = context.read<AssessmentProvider>();
    assessProv.startAssessmentRun(
      childId: _childId,
      type: 'pre',
    );
  }

  /// Persist the parent's sensory consent decision to the local database.
  void _saveSensoryConsent() {
    final consentGiven =
        widget.sensoryConsentResult == SensoryConsentResult.accepted;
    final assessProv = context.read<AssessmentProvider>();
    localDbService.insertSensoryConsent(
      childId: _childId,
      assessmentRunId: assessProv.currentAssessmentRunId,
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
    // NOTE: recordGameSession() is NOT called here because each game screen
    // (CopyMeScreen, DoWhatISayScreen, MyTurnYourTurnScreen, MatchItScreen)
    // already calls recordGameSession() with the full GameSessionMetrics
    // analytics object. Calling it here as well would double-record sessions
    // and lose the analytics data (failed taps, retries, off-task actions).

    // Extract randomTouchCount from extras if available (passed by game screens)
    final randomTouchCount = (extras['random_touch_count'] as int?) ?? 0;

    // Store result locally for the summary
    _results.add(AssessmentResult(
      id: '${gameId}_${DateTime.now().millisecondsSinceEpoch}',
      childId: _childId,
      type: 'pre',
      gameId: gameId,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      randomTouchCount: randomTouchCount,
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
      final assessProv = context.read<AssessmentProvider>();
      final metricsMapList =
          _sensoryMetrics.map((m) => m.toMap()).toList();
      await localDbService.insertSensoryRoundMetrics(
        childId: _childId,
        assessmentRunId: assessProv.currentAssessmentRunId,
        metricsMapList: metricsMapList,
      );
      debugPrint(
        '[PreAssessment] Saved ${metricsMapList.length} sensory round metrics',
      );

      // Save sensory preference result to local DB
      await localDbService.insertSensoryPreference(
        childId: _childId,
        assessmentRunId: assessProv.currentAssessmentRunId,
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
  /// The Developmental Profile labels (communication, socialInteraction,
  /// playSkills, attention, sensory) always come from the [RubricResult]
  /// produced by [RubricScoringService] so that rubric scoring is the
  /// single source of truth for the profile UI.
  ///
  /// When AI is available, the Recommendations section (difficulty, prompt
  /// style, session length, etc.) is driven by the AI response. When AI is
  /// unavailable, recommendations fall back to sensible defaults derived
  /// from the rubric labels.
  SupportProfile _buildSupportProfile(
    AiAssessmentResponse? aiResponse,
    List<AssessmentResult> finalResults,
  ) {
    final assessProv = context.read<AssessmentProvider>();
    final rubric = assessProv.rubricResult;

    // ── Developmental Profile labels from rubric ──────────────────────
    final String communication;
    final String socialInteraction;
    final String playSkills;
    final String attention;
    final List<String> sensoryNotes;

    if (rubric != null) {
      communication = _mapPerformanceLabel(rubric.communicationLabel);
      socialInteraction =
          _mapPerformanceLabel(rubric.socialInteractionLabel);
      playSkills = _mapPerformanceLabel(rubric.playSkillsLabel);
      attention = _mapAttentionLabel(rubric.behaviorAttentionLabel);
      sensoryNotes = [rubric.sensoryPreferenceLabel.displayName];

      debugPrint('[PreAssessment] 📐 Using rubric-based profile labels: '
          'comm=$communication, social=$socialInteraction, '
          'play=$playSkills, attn=$attention, '
          'sensory=${rubric.sensoryPreferenceLabel.displayName}');
    } else {
      // Rubric not available — use neutral defaults
      debugPrint('[PreAssessment] ⚠️ Rubric result not available, '
          'using neutral defaults for profile labels');
      communication = 'emerging';
      socialInteraction = 'emerging';
      playSkills = 'emerging';
      attention = 'moderate';
      sensoryNotes = const [];
    }

    // ── Recommendations from AI or rubric-based defaults ─────────────
    if (aiResponse != null) {
      debugPrint('[PreAssessment] ✅ Using AI-based recommendations: '
          '${aiResponse.profileDisplayName} '
          '(${aiResponse.confidencePercent}), '
          'support_level=${aiResponse.supportLevel}');

      final profile = aiResponse.predictedProfile;

      return SupportProfile(
        communication: communication,
        socialInteraction: socialInteraction,
        playSkills: playSkills,
        attention: attention,
        sensoryNotes: sensoryNotes,
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
      // Fallback: derive recommendations from rubric labels
      debugPrint('[PreAssessment] ⚠️ Using rubric-based recommendations '
          '(AI unavailable)');

      // Derive difficulty from rubric performance labels
      final emergingCount = [communication, socialInteraction, playSkills]
          .where((l) => l == 'emerging')
          .length;
      final strongCount = [communication, socialInteraction, playSkills]
          .where((l) => l == 'strong')
          .length;

      final String difficulty;
      if (strongCount >= 2) {
        difficulty = 'advanced';
      } else if (emergingCount >= 2) {
        difficulty = 'beginner';
      } else {
        difficulty = 'intermediate';
      }

      final sessionMin = attention == 'short attention' ? 3 : 5;
      final lowStim = attention == 'short attention';
      final needsTurnPractice = socialInteraction == 'emerging';
      final promptRep = emergingCount >= 2
          ? 3
          : emergingCount >= 1
              ? 2
              : 1;

      return SupportProfile(
        communication: communication,
        socialInteraction: socialInteraction,
        playSkills: playSkills,
        attention: attention,
        sensoryNotes: sensoryNotes,
        recommendedDifficulty: difficulty,
        recommendedPromptStyle: 'combined',
        recommendedSessionMinutes: sessionMin,
        lowStimulationMode: lowStim,
        turnTakingPractice: needsTurnPractice,
        promptRepetition: promptRep,
      );
    }
  }

  /// Map [PerformanceLabel] to the string used by [SupportProfile].
  String _mapPerformanceLabel(PerformanceLabel label) {
    switch (label) {
      case PerformanceLabel.strength:
        return 'strong';
      case PerformanceLabel.emerging:
        return 'good';
      case PerformanceLabel.needsSupport:
        return 'emerging';
    }
  }

  /// Map [AttentionLabel] to the string used by [SupportProfile].
  String _mapAttentionLabel(AttentionLabel label) {
    switch (label) {
      case AttentionLabel.sustainedAttention:
        return 'sustained';
      case AttentionLabel.variableAttention:
        return 'moderate';
      case AttentionLabel.needsAttentionSupport:
        return 'short attention';
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
