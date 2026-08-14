import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';

import '../model/ai_assessment_response.dart';
import '../model/area_level.dart';
import '../model/assessment_result.dart';
import '../model/gameplay_session.dart';
import '../model/support_profile.dart';
import '../providers/assessment_provider.dart';
import '../services/learning_path_service.dart';

/// A developer shortcut could not be completed. Carries a message that is
/// safe to show verbatim in the toolbox.
class DeveloperToolsException implements Exception {
  const DeveloperToolsException(this.message);

  final String message;

  @override
  String toString() => 'DeveloperToolsException: $message';
}

/// Deterministic stand-in for one played mini-game.
///
/// Everything a real game screen reports is spelled out here so the synthetic
/// run is scored by exactly the same rubric, model and comparison code as a
/// genuine one — nothing is faked further downstream.
@immutable
class SyntheticGameSpec {
  const SyntheticGameSpec({
    required this.gameId,
    required this.score,
    required this.totalItems,
    required this.errorCount,
    required this.avgResponseTimeMs,
    required this.retryCount,
    required this.hintCount,
    required this.promptCount,
    required this.idleTimeSeconds,
    required this.randomTouchCount,
    required this.offTaskActionCount,
    required this.improvementScore,
    required this.consistencyScore,
    required this.assistanceLevel,
  });

  final String gameId;
  final int score;
  final int totalItems;
  final int errorCount;
  final int avgResponseTimeMs;
  final int retryCount;
  final int hintCount;
  final int promptCount;
  final int idleTimeSeconds;
  final int randomTouchCount;
  final int offTaskActionCount;
  final double improvementScore;
  final double consistencyScore;
  final AssistanceLevel assistanceLevel;

  int get totalResponseTimeMs => avgResponseTimeMs * totalItems;
}

/// What the simulated pre-assessment produced — the same three values the
/// real [PreAssessmentProgressScreen] hands to `WaitingForParentScreen`.
@immutable
class SimulatedPreAssessment {
  const SimulatedPreAssessment({
    required this.results,
    required this.profile,
    required this.aiResponse,
  });

  final List<AssessmentResult> results;
  final SupportProfile profile;
  final AiAssessmentResponse? aiResponse;
}

/// What the simulated post-assessment produced — the same three values the
/// real [PostAssessmentProgressScreen] hands to `PostAssessmentHandoffScreen`.
@immutable
class SimulatedPostAssessment {
  const SimulatedPostAssessment({
    required this.improvement,
    required this.preAreaLevels,
    required this.postAreaLevels,
  });

  final Map<String, dynamic> improvement;
  final Map<String, AreaLevel> preAreaLevels;
  final Map<String, AreaLevel> postAreaLevels;
}

/// The learning-path step a "Complete Next Module" press finished.
@immutable
class CompletedModule {
  const CompletedModule({
    required this.gameId,
    required this.gameName,
    required this.remaining,
  });

  final String gameId;
  final String gameName;

  /// How many path steps are still incomplete after this one.
  final int remaining;
}

/// Drives the developer shortcuts through the app's real domain APIs.
///
/// Deliberately free of `BuildContext` and of any private provider state: the
/// shortcuts skip the *time* spent playing four games, not the pipeline that
/// turns gameplay into results. Everything here goes through
/// [AssessmentProvider]'s public API, so a simulated run is finalized, scored,
/// predicted and snapshotted exactly like a played one.
class DeveloperToolsService {
  const DeveloperToolsService({this.clock = DateTime.now});

  /// Injectable "now", so tests get fully repeatable timestamps.
  final DateTime Function() clock;

  /// The four games every assessment run requires, in flow order.
  static const assessmentGameIds = <String>[
    'copy_me',
    'do_what_i_say',
    'my_turn_your_turn',
    'match_it',
  ];

  /// Believable mid-range performance: a child who needs some support.
  static const preAssessmentSpecs = <SyntheticGameSpec>[
    SyntheticGameSpec(
      gameId: 'copy_me',
      score: 6,
      totalItems: 10,
      errorCount: 4,
      avgResponseTimeMs: 3400,
      retryCount: 2,
      hintCount: 2,
      promptCount: 3,
      idleTimeSeconds: 12,
      randomTouchCount: 5,
      offTaskActionCount: 4,
      improvementScore: 0.05,
      consistencyScore: 0.55,
      assistanceLevel: AssistanceLevel.guided,
    ),
    SyntheticGameSpec(
      gameId: 'do_what_i_say',
      score: 8,
      totalItems: 12,
      errorCount: 4,
      avgResponseTimeMs: 3000,
      retryCount: 2,
      hintCount: 3,
      promptCount: 3,
      idleTimeSeconds: 10,
      randomTouchCount: 4,
      offTaskActionCount: 3,
      improvementScore: 0.08,
      consistencyScore: 0.6,
      assistanceLevel: AssistanceLevel.guided,
    ),
    SyntheticGameSpec(
      gameId: 'my_turn_your_turn',
      score: 5,
      totalItems: 8,
      errorCount: 3,
      avgResponseTimeMs: 3800,
      retryCount: 3,
      hintCount: 2,
      promptCount: 4,
      idleTimeSeconds: 15,
      randomTouchCount: 6,
      offTaskActionCount: 5,
      improvementScore: 0.02,
      consistencyScore: 0.5,
      assistanceLevel: AssistanceLevel.guided,
    ),
    SyntheticGameSpec(
      gameId: 'match_it',
      score: 8,
      totalItems: 12,
      errorCount: 4,
      avgResponseTimeMs: 2900,
      retryCount: 1,
      hintCount: 2,
      promptCount: 2,
      idleTimeSeconds: 9,
      randomTouchCount: 4,
      offTaskActionCount: 3,
      improvementScore: 0.1,
      consistencyScore: 0.62,
      assistanceLevel: AssistanceLevel.minimal,
    ),
  ];

  /// The same four games, played better: more correct, fewer errors, faster
  /// and less assisted — so the pre/post comparison shows a predictable
  /// improvement rather than noise.
  static const postAssessmentSpecs = <SyntheticGameSpec>[
    SyntheticGameSpec(
      gameId: 'copy_me',
      score: 9,
      totalItems: 10,
      errorCount: 1,
      avgResponseTimeMs: 2400,
      retryCount: 1,
      hintCount: 1,
      promptCount: 1,
      idleTimeSeconds: 5,
      randomTouchCount: 2,
      offTaskActionCount: 1,
      improvementScore: 0.2,
      consistencyScore: 0.82,
      assistanceLevel: AssistanceLevel.minimal,
    ),
    SyntheticGameSpec(
      gameId: 'do_what_i_say',
      score: 11,
      totalItems: 12,
      errorCount: 1,
      avgResponseTimeMs: 2200,
      retryCount: 1,
      hintCount: 1,
      promptCount: 1,
      idleTimeSeconds: 4,
      randomTouchCount: 2,
      offTaskActionCount: 1,
      improvementScore: 0.22,
      consistencyScore: 0.85,
      assistanceLevel: AssistanceLevel.minimal,
    ),
    SyntheticGameSpec(
      gameId: 'my_turn_your_turn',
      score: 7,
      totalItems: 8,
      errorCount: 1,
      avgResponseTimeMs: 2600,
      retryCount: 1,
      hintCount: 1,
      promptCount: 2,
      idleTimeSeconds: 6,
      randomTouchCount: 3,
      offTaskActionCount: 2,
      improvementScore: 0.18,
      consistencyScore: 0.78,
      assistanceLevel: AssistanceLevel.minimal,
    ),
    SyntheticGameSpec(
      gameId: 'match_it',
      score: 11,
      totalItems: 12,
      errorCount: 1,
      avgResponseTimeMs: 2100,
      retryCount: 0,
      hintCount: 0,
      promptCount: 1,
      idleTimeSeconds: 3,
      randomTouchCount: 1,
      offTaskActionCount: 1,
      improvementScore: 0.25,
      consistencyScore: 0.88,
      assistanceLevel: AssistanceLevel.independent,
    ),
  ];

  /// A solid practice run, used when a learning-path module is completed.
  static const practiceSpec = SyntheticGameSpec(
    gameId: '', // filled in per module
    score: 8,
    totalItems: 10,
    errorCount: 2,
    avgResponseTimeMs: 2600,
    retryCount: 1,
    hintCount: 1,
    promptCount: 1,
    idleTimeSeconds: 5,
    randomTouchCount: 2,
    offTaskActionCount: 1,
    improvementScore: 0.15,
    consistencyScore: 0.8,
    assistanceLevel: AssistanceLevel.minimal,
  );

  /// How long one simulated game is treated as having taken.
  static const _gameSlot = Duration(minutes: 5);

  // ── Pre-assessment ───────────────────────────────────────────────────

  /// Simulates the four required pre-assessment games and runs the complete
  /// finalization pipeline: rubric scoring, AI prediction (with the app's own
  /// on-device/rubric fallbacks), support profile, and the frozen run
  /// snapshot.
  ///
  /// Throws a [DeveloperToolsException] the moment any step fails, so the
  /// caller never presents a hand-off over a run that was not saved.
  Future<SimulatedPreAssessment> completePreAssessment({
    required AssessmentProvider provider,
    required String childId,
  }) async {
    _requireChildId(childId);

    await _startRun(provider: provider, childId: childId, type: 'pre');
    await _recordSpecs(
      provider: provider,
      childId: childId,
      specs: preAssessmentSpecs,
      context: 'pre_assessment',
    );

    // No sensory experiment was played, so no sensory metrics are handed to
    // the rubric — it falls back to "no sensory support needed" on its own.
    // Inventing a sensory conclusion here would be a fabricated finding.
    final finalized = await provider.finalizePreAssessment(childId);
    if (!finalized) {
      throw DeveloperToolsException(provider.lastFinalizationError ??
          'The simulated pre-assessment could not be finalized.');
    }

    final aiResponse =
        await provider.predictWithAI(childId, assessmentType: 'pre');
    final profile =
        await provider.finalizeSupportProfile(childId, aiResponse: aiResponse);
    final snapshot = await provider.captureRunSnapshot(
      childId,
      assessmentType: 'pre',
      prediction: aiResponse,
      profile: profile,
    );

    if (snapshot.results.isEmpty) {
      throw const DeveloperToolsException(
          'The simulated pre-assessment produced no results.');
    }
    if (provider.recommendation == null) {
      throw const DeveloperToolsException(
          'The simulated pre-assessment produced no recommendation.');
    }
    if (aiResponse == null || aiResponse.areaLevels.isEmpty) {
      throw const DeveloperToolsException(
          'No area levels were produced, so there is no learning path. '
          'The AI, the on-device model and the rubric fallback all failed.');
    }

    debugPrint('[DeveloperTools] Simulated pre-assessment complete: '
        '${snapshot.results.length} results, '
        '${aiResponse.areaLevels.length} area levels');

    return SimulatedPreAssessment(
      results: snapshot.results,
      profile: profile,
      aiResponse: aiResponse,
    );
  }

  // ── Post-assessment ──────────────────────────────────────────────────

  /// Simulates the four post-assessment games and runs the real post
  /// finalization: comparison against the frozen pre-assessment baseline, a
  /// fresh prediction, and the post snapshot.
  ///
  /// Requires a finalized pre-assessment: the shortcut may skip the learning
  /// modules, but never the baseline the comparison is meaningless without.
  Future<SimulatedPostAssessment> completePostAssessment({
    required AssessmentProvider provider,
    required String childId,
  }) async {
    _requireChildId(childId);
    if (!hasPreAssessmentBaseline(provider)) {
      throw const DeveloperToolsException(
          'There is no pre-assessment baseline to compare against. '
          'Run "Complete Pre-Assessment" first.');
    }

    // Read the baseline before the run starts, exactly like the real screen:
    // the frozen pre snapshot, not the "latest" prediction that this run is
    // about to replace.
    final preAreaLevels = Map<String, AreaLevel>.of(
      provider.preSnapshot?.prediction?.areaLevels ??
          provider.aiPrediction?.areaLevels ??
          const {},
    );

    await _startRun(provider: provider, childId: childId, type: 'post');
    await _recordSpecs(
      provider: provider,
      childId: childId,
      specs: postAssessmentSpecs,
      context: 'post_assessment',
    );

    final improvement = await provider.finalizePostAssessment(childId);
    if (improvement['has_data'] != true) {
      throw DeveloperToolsException(provider.lastFinalizationError ??
          'The simulated post-assessment produced no comparison data.');
    }

    final postPrediction =
        await provider.predictWithAI(childId, assessmentType: 'post');
    await provider.captureRunSnapshot(
      childId,
      assessmentType: 'post',
      prediction: postPrediction,
    );

    debugPrint('[DeveloperTools] Simulated post-assessment complete: '
        'accuracy_improvement=${improvement['accuracy_improvement']}');

    return SimulatedPostAssessment(
      improvement: improvement,
      preAreaLevels: preAreaLevels,
      postAreaLevels: postPrediction?.areaLevels ?? const {},
    );
  }

  /// Whether a finalized pre-assessment exists to build on.
  static bool hasPreAssessmentBaseline(AssessmentProvider provider) =>
      provider.hasPreAssessment || provider.preSnapshot != null;

  // ── Learning path ────────────────────────────────────────────────────

  /// The child's recommended learning path, built by the same service the
  /// lobby and dashboard use.
  static List<LearningPathEntry> learningPath(
    AssessmentProvider provider, {
    Set<String>? activeGameIds,
  }) {
    final prediction = provider.aiPrediction;
    if (prediction == null) return const [];
    return LearningPathService.buildPath(
      areaLevels: prediction.areaLevels,
      serverModules: prediction.moduleDetails,
      featureValues: prediction.featureValues,
      activeGameIds: activeGameIds,
    );
  }

  /// The first path step the child has not completed, or null when the whole
  /// path is done (or there is no path yet).
  static LearningPathEntry? nextIncompleteModule(
    AssessmentProvider provider, {
    Set<String>? activeGameIds,
  }) {
    final completed = provider.pathCompletedGameIds;
    for (final entry in learningPath(provider, activeGameIds: activeGameIds)) {
      if (!completed.contains(entry.game.id)) return entry;
    }
    return null;
  }

  /// Completes exactly one module: the first incomplete step of the path.
  ///
  /// The practice session goes through [AssessmentProvider.recordGameSession]
  /// with context `practice`, which is what marks and persists path progress —
  /// no private state and no direct SharedPreferences write. Pressing again
  /// therefore advances to the next step rather than duplicating this one.
  Future<CompletedModule> completeNextModule({
    required AssessmentProvider provider,
    required String childId,
    Set<String>? activeGameIds,
  }) async {
    _requireChildId(childId);

    final path = learningPath(provider, activeGameIds: activeGameIds);
    if (path.isEmpty) {
      throw const DeveloperToolsException(
          'There is no recommended learning path yet. Complete the '
          'pre-assessment first.');
    }
    final next = nextIncompleteModule(provider, activeGameIds: activeGameIds);
    if (next == null) {
      throw const DeveloperToolsException(
          'All recommended modules completed');
    }

    final started = clock().subtract(_gameSlot);
    final session = await provider.recordGameSession(
      childId: childId,
      gameId: next.game.id,
      context: 'practice',
      score: practiceSpec.score,
      totalItems: practiceSpec.totalItems,
      errorCount: practiceSpec.errorCount,
      totalResponseTimeMs: practiceSpec.totalResponseTimeMs,
      startedAt: started,
      analytics: _analyticsFor(
        spec: practiceSpec,
        gameId: next.game.id,
        childId: childId,
        startedAt: started,
      ),
    );
    if (session == null) {
      throw DeveloperToolsException(
          'The practice session for ${next.game.name} was not recorded.');
    }

    final completed = provider.pathCompletedGameIds;
    if (!completed.contains(next.game.id)) {
      throw DeveloperToolsException(
          '${next.game.name} was recorded but not marked complete on the '
          'learning path.');
    }
    final remaining =
        path.where((e) => !completed.contains(e.game.id)).length;

    debugPrint('[DeveloperTools] Completed module ${next.game.id} '
        '($remaining remaining)');

    return CompletedModule(
      gameId: next.game.id,
      gameName: next.game.name,
      remaining: remaining,
    );
  }

  // ── Shared plumbing ──────────────────────────────────────────────────

  void _requireChildId(String childId) {
    // 'unknown' is the screens' fallback when no profile is selected; writing
    // assessment data against it would create records for a child that does
    // not exist.
    if (childId.isEmpty || childId == 'unknown') {
      throw const DeveloperToolsException(
          'No child profile is selected, so there is nothing to assess.');
    }
  }

  Future<void> _startRun({
    required AssessmentProvider provider,
    required String childId,
    required String type,
  }) async {
    try {
      await provider.startAssessmentRun(childId: childId, type: type);
    } catch (e) {
      throw DeveloperToolsException(
          'Could not start the simulated $type-assessment run: $e');
    }
    if (!provider.hasActiveAssessmentRun) {
      throw DeveloperToolsException(
          'The simulated $type-assessment run was not created.');
    }
  }

  /// Records one session per spec, each with its own start time so the
  /// provider's per-instance dedupe cannot collapse them into one.
  Future<void> _recordSpecs({
    required AssessmentProvider provider,
    required String childId,
    required List<SyntheticGameSpec> specs,
    required String context,
  }) async {
    final base = clock().subtract(_gameSlot * specs.length);
    for (var i = 0; i < specs.length; i++) {
      final spec = specs[i];
      final startedAt = base.add(_gameSlot * i);
      final GameplaySession? session;
      try {
        session = await provider.recordGameSession(
          childId: childId,
          gameId: spec.gameId,
          context: context,
          score: spec.score,
          totalItems: spec.totalItems,
          errorCount: spec.errorCount,
          totalResponseTimeMs: spec.totalResponseTimeMs,
          startedAt: startedAt,
          analytics: _analyticsFor(
            spec: spec,
            gameId: spec.gameId,
            childId: childId,
            startedAt: startedAt,
          ),
        );
      } catch (e) {
        throw DeveloperToolsException(
            'Could not record the simulated ${spec.gameId} session: $e');
      }
      if (session == null) {
        throw DeveloperToolsException(
            'The simulated ${spec.gameId} session was not recorded.');
      }
    }
  }

  /// Builds the analytics object a real game screen would have collected.
  ///
  /// No per-round telemetry is attached: nothing was played, and the sensory
  /// experiment attributes rounds to the configuration that was active while
  /// they were played. Leaving [GameSessionMetrics.rounds] empty is the
  /// project's own "no sensory data" path.
  GameSessionMetrics _analyticsFor({
    required SyntheticGameSpec spec,
    required String gameId,
    required String childId,
    required DateTime startedAt,
  }) {
    final metrics = GameSessionMetrics(
      gameId: gameId,
      sessionId: 'dev-$gameId-${startedAt.microsecondsSinceEpoch}',
      childId: childId,
      totalRounds: spec.totalItems,
    )
      ..startTime = startedAt.toIso8601String()
      ..endTime = startedAt.add(_gameSlot).toIso8601String()
      ..correctCount = spec.score
      ..wrongCount = spec.errorCount
      ..completedRounds = spec.totalItems
      ..isCompleted = true
      ..retryCount = spec.retryCount
      ..hintCount = spec.hintCount
      ..promptCount = spec.promptCount
      ..assistanceLevel = spec.assistanceLevel
      ..idleTimeSeconds = spec.idleTimeSeconds
      ..randomTouchCount = spec.randomTouchCount
      ..offTaskActionCount = spec.offTaskActionCount
      ..avgResponseTime = spec.avgResponseTimeMs / 1000.0
      ..avgValidResponseTime = spec.avgResponseTimeMs / 1000.0
      ..timeToFirstTouch = spec.avgResponseTimeMs / 1000.0
      ..timeToFirstValidAction = spec.avgResponseTimeMs / 1000.0
      ..timeToCompletion = _gameSlot.inSeconds.toDouble()
      ..improvementScore = spec.improvementScore
      ..consistencyScore = spec.consistencyScore
      ..gameSpecificMetrics = const {'simulated_by': 'developer_tools'};
    return metrics;
  }
}
