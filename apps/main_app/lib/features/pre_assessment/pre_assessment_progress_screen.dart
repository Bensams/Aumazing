import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/services/local_db_service.dart';
import '../../dev/developer_automation_registry.dart';
import '../../model/assessment_result.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';

import '../games/copy_me/copy_me_screen.dart';
import '../games/do_what_i_say/do_what_i_say_screen.dart';
import '../games/my_turn_your_turn/my_turn_your_turn_screen.dart';
import '../games/match_it/match_it_screen.dart';
import '../rewards/widgets/reward_overlay.dart';
import '../../widgets/mascot_host.dart';

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

/// Where the screen is in its own lifecycle.
enum _FlowState { initializing, ready, initFailed, finishing, finishFailed }

class _PreAssessmentProgressScreenState
    extends State<PreAssessmentProgressScreen> {
  int _currentGameIndex = 0;
  final List<AssessmentResult> _results = [];

  /// Nothing may be played until the assessment run exists.
  _FlowState _flowState = _FlowState.initializing;
  String? _errorMessage;

  /// True when a game reported no usable per-round telemetry, which makes
  /// the sensory comparison unreliable.
  bool _sensoryTelemetryReliable = true;

  /// Guards the per-game completion handler against a duplicate callback.
  int? _completedGameIndex;

  /// Controls per-round sensory settings (music/haptic toggling).
  late final SensoryRoundController _sensoryController;

  /// Collected sensory round metrics across all games.
  final List<SensoryRoundMetrics> _sensoryMetrics = [];

  /// The analyzed sensory preference result (populated after all games).
  SensoryPreferenceResult? _sensoryPreferenceResult;

  /// Countdown timer for auto-launching the current game.
  Timer? _countdownTimer;

  /// Current countdown value displayed on the transition screen.
  int _countdown = 7;

  /// Guard flag to prevent multiple game launches from orphaned timers.
  bool _gameLaunched = false;

  /// Developer auto-play handle for the transition screen. Null in a normal
  /// build; lets automation start the pending game without waiting out the
  /// countdown.
  DeveloperFlowSession? _devFlow;

  @override
  void initState() {
    super.initState();
    // The child performs these activities — landscape like the games.
    lockParentLandscape();
    _initSensoryController();
    _initializeRun();
  }

  /// Creates the assessment run, then persists the consent decision against
  /// it, and only then lets the child start playing.
  ///
  /// The countdown and the Play button used to start while the run was still
  /// being created, so an early first game could be recorded with no run id
  /// — and the consent row was written against a run that did not exist yet.
  Future<void> _initializeRun() async {
    setState(() {
      _flowState = _FlowState.initializing;
      _errorMessage = null;
    });

    final assessProv = context.read<AssessmentProvider>();
    final childId = _childId;

    try {
      await assessProv.startAssessmentRun(childId: childId, type: 'pre');
      await _saveSensoryConsent(assessProv.currentAssessmentRunId, childId);
    } catch (e) {
      debugPrint('[PreAssessment] run initialization failed: $e');
      if (!mounted) return;
      setState(() {
        _flowState = _FlowState.initFailed;
        _errorMessage = AssessmentLabels.couldNotStart;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _flowState = _FlowState.ready);
    _startCountdown();
  }

  /// Persist the parent's sensory consent decision against the run.
  Future<void> _saveSensoryConsent(String? runId, String childId) async {
    final consentGiven =
        widget.sensoryConsentResult == SensoryConsentResult.accepted;
    await localDbService.insertSensoryConsent(
      childId: childId,
      assessmentRunId: runId,
      consentGiven: consentGiven,
    );
    debugPrint(
      '[PreAssessment] Saved sensory consent: $consentGiven for $childId',
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

  /// Starts (or restarts) the 7-second countdown timer for the transition
  /// screen. Cancels any previously running timer first.
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdown = 7;
    _gameLaunched = false;

    DeveloperAutomationRegistry.instance.unregister(_devFlow);
    _devFlow = DeveloperAutomationRegistry.instance.registerFlow(
      flowLabel: 'Pre-Assessment',
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

  @override
  void dispose() {
    _countdownTimer?.cancel();
    DeveloperAutomationRegistry.instance.unregister(_devFlow);
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
    // already awaits recordGameSession() with the full GameSessionMetrics
    // analytics object. Calling it here as well would double-record sessions
    // and lose the analytics data (failed taps, retries, off-task actions).

    // A second callback for the same game would push a duplicate result and
    // pop a route that is no longer there.
    if (_completedGameIndex == _currentGameIndex) return;
    _completedGameIndex = _currentGameIndex;

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

    // Collect the real per-round telemetry for the sensory experiment.
    _collectSensoryMetrics(gameId);

    // Show reward overlay before advancing to next game
    _showRewardThenAdvance();
  }

  /// Collects this game's *measured* rounds for the sensory experiment.
  ///
  /// Each [GameRoundMetrics] the game recorded is attributed to the
  /// [SensoryRoundConfig] that was active while it was played. When a game
  /// reports no per-round telemetry (or rounds the experiment has no
  /// configuration for) the comparison is flagged unreliable, and the
  /// recommendation is surfaced as unavailable rather than invented.
  void _collectSensoryMetrics(String gameId) {
    final analytics =
        context.read<AssessmentProvider>().analyticsForGame(gameId);
    final collection = SensoryRoundTelemetry.collect(
      gameId: gameId,
      analytics: analytics,
      rounds: _sensoryController.rounds,
    );

    _sensoryMetrics.addAll(collection.metrics);
    if (!collection.reliable) {
      _sensoryTelemetryReliable = false;
      debugPrint('[PreAssessment] Per-round telemetry missing or '
          'unattributable for $gameId — sensory recommendation downgraded');
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
      _startCountdown(); // Restart countdown for the next game's transition screen
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
      // -- Sensory preference analysis --------------------------------
      if (_sensoryController.consentGiven && _sensoryMetrics.isNotEmpty) {
        final analyzer = SensoryPreferenceAnalyzer();
        _sensoryPreferenceResult = analyzer.analyze(
          _sensoryMetrics,
          telemetryReliable: _sensoryTelemetryReliable,
        );
        debugPrint(
          '[PreAssessment] Sensory analysis complete: '
          'available=${_sensoryPreferenceResult!.available}, '
          'music=${_sensoryPreferenceResult!.recommendedMusicEnabled}, '
          'haptic=${_sensoryPreferenceResult!.recommendedHapticEnabled}, '
          'confidence=${_sensoryPreferenceResult!.confidence}',
        );

        // Save sensory round metrics to local DB
        final metricsMapList = _sensoryMetrics.map((m) => m.toMap()).toList();
        await localDbService.insertSensoryRoundMetrics(
          childId: childId,
          assessmentRunId: assessProv.currentAssessmentRunId,
          metricsMapList: metricsMapList,
        );
        debugPrint('[PreAssessment] Saved ${metricsMapList.length} sensory '
            'round metrics');

        // Save sensory preference result to local DB
        await localDbService.insertSensoryPreference(
          childId: childId,
          assessmentRunId: assessProv.currentAssessmentRunId,
          preferenceMap: _sensoryPreferenceResult!.toMap(),
        );
        debugPrint('[PreAssessment] Saved sensory preference result');
      }

      // Hand the measured rounds to the rubric so its sensory label reflects
      // what was actually observed.
      assessProv.setSensoryMetrics(_sensoryMetrics);

      // Restore original audio/haptic settings now that testing is done
      await _sensoryController.restoreOriginalSettings();

      // Finalize the pre-assessment: creates assessment results in local DB
      // and triggers Supabase sync via the sync service. A failure here means
      // there is no result to show -- surface it instead of a fake success.
      final finalized = await assessProv.finalizePreAssessment(childId);
      if (!finalized) {
        if (!mounted) return;
        setState(() {
          _flowState = _FlowState.finishFailed;
          _errorMessage = assessProv.lastFinalizationError ??
              AssessmentLabels.couldNotSave;
        });
        return;
      }

      if (!mounted) return;

      // Call AI Assessment API for XGBoost-based prediction. It runs before
      // any reload, because the prediction needs this run's sessions.
      debugPrint('[PreAssessment] Calling AI Assessment API...');
      final aiResponse =
          await assessProv.predictWithAI(childId, assessmentType: 'pre');

      if (!mounted) return;

      // Finalize and persist the profile for this run. The parent's later
      // Assessment Summary reads this same profile back rather than
      // recomputing it, so both views always agree.
      final profile = await assessProv.finalizeSupportProfile(
        childId,
        aiResponse: aiResponse,
      );

      // Freeze this run so a later post-assessment cannot rewrite what the
      // parent was shown as the pre-assessment.
      final snapshot = await assessProv.captureRunSnapshot(
        childId,
        assessmentType: 'pre',
        prediction: aiResponse,
        profile: profile,
      );

      if (!mounted) return;

      // Navigate to the waiting-for-parent screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => WaitingForParentScreen(
            results: snapshot.results.isNotEmpty ? snapshot.results : _results,
            profile: profile,
            aiResponse: aiResponse,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[PreAssessment] finish failed: $e');
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
            child: SingleChildScrollView(
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

  void _launchGame(String gameId) {
    // Cancel the countdown timer and guard against duplicate launches
    _countdownTimer?.cancel();
    if (_gameLaunched) return;
    _gameLaunched = true;
    DeveloperAutomationRegistry.instance.unregister(_devFlow);
    _devFlow = null;

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
            builder: (_) => MascotHost(
              child: MatchItScreen(
                assessmentContext: 'pre_assessment',
                sensoryController: _sensoryController,
                onComplete: (score, total, errors, time) {
                  // Call _onGameComplete to handle reward and advancement
                  _onGameComplete(gameId, score, total, errors, time);
                },
              ),
            ),
          ),
        );
        return; // Match It handles its own navigation, don't fall through
      default:
        return;
    }

    // The mascot keeps the child company through pre-assessment too; the host
    // must sit above the game screen for its lookups to resolve.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MascotHost(child: screen)),
    );
  }
}
