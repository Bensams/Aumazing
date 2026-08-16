import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../model/ai_assessment_response.dart';
import '../model/area_level.dart';
import '../model/assessment_result.dart';
import '../model/support_profile.dart';
import 'learning_path_service.dart';

/// Builds the one canonical [AssessmentResultViewModel] that both the
/// immediate completion screen and the parent's later Assessment Summary
/// render.
///
/// Everything the two screens display comes from here, so they cannot drift:
/// the same games, the same developmental areas, the same recommended
/// settings, the same learning path, the same analysis source and
/// confidence. Nothing is recomputed from the child's current settings — the
/// [SupportProfile] handed in is the one finalized with the run.
abstract final class AssessmentResultMapper {
  static AssessmentResultViewModel build({
    required List<AssessmentResult> results,
    required SupportProfile profile,
    AiAssessmentResponse? aiResponse,
    Set<String>? activeGameIds,
    String assessmentType = 'pre',
    ResultProgress? progress,
  }) {
    final games = [
      for (final result in results)
        ResultGameScore(
          gameId: result.gameId,
          name: gameName(result.gameId),
          emoji: gameEmoji(result.gameId),
          accuracy: result.adjustedAccuracy,
          correctCount: result.score,
          errorCount: result.errorCount,
          totalItems: result.totalItems,
        ),
    ];

    final path =
        aiResponse == null
            ? const <ResultModule>[]
            : [
              for (final step in LearningPathService.buildPath(
                areaLevels: aiResponse.areaLevels,
                serverModules: aiResponse.moduleDetails,
                featureValues: aiResponse.featureValues,
                activeGameIds: activeGameIds,
              ))
                ResultModule(
                  name: step.game.name,
                  startingLevel: step.difficulty,
                  reason: activityReason(
                    areaKey: step.areaKey,
                    areaLevels: aiResponse.areaLevels,
                  ),
                ),
            ];

    // The model recommended activities but every one of them was filtered
    // out — an empty path with a non-empty recommendation set.
    final filteredOut =
        aiResponse != null &&
        path.isEmpty &&
        (aiResponse.moduleDetails.isNotEmpty ||
            aiResponse.recommendedModules.isNotEmpty);

    return AssessmentResultViewModel(
      assessmentType: assessmentType,
      assessmentRunId: _runId(results),
      completedAt: _completedAt(results),
      games: games,
      areas: buildAreas(profile: profile, aiResponse: aiResponse),
      recommendations: buildRecommendations(profile),
      source: resolveSource(results: results, aiResponse: aiResponse),
      confidence: aiResponse?.confidence,
      summary: _summary(aiResponse),
      profileDisplayName:
          aiResponse != null && !aiResponse.hasAreaLevels
              ? aiResponse.profileDisplayName
              : null,
      supportLevel: aiResponse?.supportLevel,
      learningPath: path,
      sensoryObservations: profile.sensoryNotes,
      learningPathUnavailable: filteredOut,
      progress: progress,
    );
  }

  // ── Analysis source ──────────────────────────────────────────────────

  /// The analysis source, taken from the model that actually produced the
  /// stored labels. A rubric-synthesized prediction is *not* AI, even though
  /// it is delivered as an [AiAssessmentResponse].
  static AssessmentAnalysisSource resolveSource({
    required List<AssessmentResult> results,
    AiAssessmentResponse? aiResponse,
  }) {
    for (final result in results) {
      switch (result.modelSource) {
        case 'xgboost_onnx':
          return AssessmentAnalysisSource.onDeviceAi;
        case 'xgboost':
          return AssessmentAnalysisSource.cloudAi;
        case 'rubric_based':
          return AssessmentAnalysisSource.ruleBased;
      }
    }
    if (aiResponse == null) return AssessmentAnalysisSource.ruleBased;
    return aiResponse.onDevice
        ? AssessmentAnalysisSource.onDeviceAi
        : AssessmentAnalysisSource.cloudAi;
  }

  // ── Developmental areas ──────────────────────────────────────────────

  /// Canonical developmental-area names, in display order.
  static const areaTitles = <String, String>{
    'communication': 'Communication',
    'social': 'Social Interaction',
    'play': 'Play Skills',
    'attention': 'Attention',
  };

  static const _levelNames = ['Needs Support', 'Emerging', 'Strength'];

  /// Areas from the AI's per-area levels when it emitted them, otherwise
  /// from the finalized rubric profile labels. Both paths produce the same
  /// area names and the same three level names.
  static List<ResultAreaLevel> buildAreas({
    required SupportProfile profile,
    AiAssessmentResponse? aiResponse,
  }) {
    final levels = aiResponse?.areaLevels;
    if (levels != null && levels.isNotEmpty) {
      return [
        for (final entry in areaTitles.entries)
          if (levels[entry.key] != null)
            ResultAreaLevel(
              label: entry.value,
              levelName: levels[entry.key]!.levelName,
              levelInt: levels[entry.key]!.levelInt,
              confidence: levels[entry.key]!.confidence,
            ),
      ];
    }

    ResultAreaLevel area(String label, String rawLevel) {
      final levelInt = levelOrdinal(rawLevel);
      return ResultAreaLevel(
        label: label,
        levelName: _levelNames[levelInt],
        levelInt: levelInt,
      );
    }

    return [
      area(areaTitles['communication']!, profile.communication),
      area(areaTitles['social']!, profile.socialInteraction),
      area(areaTitles['play']!, profile.playSkills),
      area(areaTitles['attention']!, profile.attention),
    ];
  }

  /// Maps a [SupportProfile] level string onto the 0–2 ordinal used
  /// everywhere else (0 = Needs Support, 1 = Emerging, 2 = Strength).
  static int levelOrdinal(String rawLevel) {
    switch (rawLevel.toLowerCase()) {
      case 'strong':
      case 'strength':
      case 'sustained':
        return 2;
      case 'good':
      case 'developing':
      case 'improving':
      case 'moderate':
        return 1;
      default:
        return 0;
    }
  }

  // ── Why an activity was recommended ──────────────────────────────────

  /// A parent-friendly reason for putting an activity on the path (AUM-161).
  ///
  /// The learning path already knows which area each activity targets
  /// ([LearningPathEntry.areaKey]); this turns that into a sentence a parent
  /// can act on. The wording deliberately describes the *activity* and the
  /// *skill area* — "builds Communication, the area with the most room to
  /// grow" — never the child, and never a condition. An assessment run says
  /// what happened in four games; it is not a diagnosis, so nothing here may
  /// read like one.
  ///
  /// Returns null when the area is unknown, so the row simply shows no
  /// reason rather than an invented one.
  static String? activityReason({
    required String areaKey,
    required Map<String, AreaLevel> areaLevels,
  }) {
    final title = areaTitles[areaKey];
    if (title == null) return null;

    final level = areaLevels[areaKey]?.levelInt;
    switch (level) {
      case 0:
        return 'Practises $title, the area with the most room to grow '
            'right now.';
      case 1:
        return 'Keeps building $title, which is coming along.';
      case 2:
        return 'Plays to a strength in $title to keep it going.';
      default:
        return 'Practises $title.';
    }
  }

  // ── Recommended settings ─────────────────────────────────────────────

  /// The finalized recommended settings, in a fixed order with fixed labels.
  static List<ResultRecommendation> buildRecommendations(
    SupportProfile profile,
  ) {
    return [
      ResultRecommendation(
        icon: Icons.speed_rounded,
        label: AssessmentLabels.difficulty,
        value: _titleCase(profile.recommendedDifficulty),
      ),
      ResultRecommendation(
        icon: Icons.record_voice_over_rounded,
        label: AssessmentLabels.promptStyle,
        value: _titleCase(profile.recommendedPromptStyle),
      ),
      ResultRecommendation(
        icon: Icons.timer_rounded,
        label: AssessmentLabels.sessionLength,
        value: '${profile.recommendedSessionMinutes} min',
      ),
      ResultRecommendation(
        icon: Icons.repeat_rounded,
        label: AssessmentLabels.promptRepetition,
        value: '${profile.promptRepetition}x',
      ),
      if (profile.lowStimulationMode)
        const ResultRecommendation(
          icon: Icons.visibility_off_rounded,
          label: AssessmentLabels.lowStimulationMode,
          value: 'On',
        ),
      if (profile.turnTakingPractice)
        const ResultRecommendation(
          icon: Icons.people_rounded,
          label: AssessmentLabels.turnTakingPractice,
          value: 'Extra practice',
        ),
    ];
  }

  // ── Game display ─────────────────────────────────────────────────────

  /// Display name for a game id — the registry's own name, so the result
  /// screens, the learning path and the launcher all agree.
  static String gameName(String gameId) {
    for (final game in GameRegistry.games) {
      if (game.id == gameId) return game.name;
    }
    return gameId;
  }

  /// Emoji for a game id. The registry carries icons and logos rather than
  /// emoji, so the compact result rows map them here.
  static String gameEmoji(String gameId) => _gameEmoji[gameId] ?? '🎮';

  static const _gameEmoji = <String, String>{
    'copy_me': '🪞',
    'do_what_i_say': '🗣️',
    'my_turn_your_turn': '🔄',
    'match_it': '🧩',
    'sari_sari_sort': '🏪',
    'trace_it': '✏️',
    'hintay': '⏳',
    'anong_susunod': '➡️',
    'sabay_tayo': '🕺',
    'kumusta': '👋',
    'anong_nararamdaman': '💗',
    'tulong_kaibigan': '🤝',
  };

  // ── Helpers ──────────────────────────────────────────────────────────

  static String _summary(AiAssessmentResponse? aiResponse) {
    final summary = aiResponse?.summary;
    if (summary != null && summary.trim().isNotEmpty) return summary;
    return 'Your child completed all the activities. Review each skill area '
        'below to see where they shine and where a little more practice '
        'will help.';
  }

  static String? _runId(List<AssessmentResult> results) {
    for (final result in results) {
      if (result.assessmentRunId != null) return result.assessmentRunId;
    }
    return null;
  }

  static DateTime? _completedAt(List<AssessmentResult> results) {
    DateTime? latest;
    for (final result in results) {
      if (latest == null || result.completedAt.isAfter(latest)) {
        latest = result.completedAt;
      }
    }
    return latest;
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value
        .split(RegExp(r'[\s_]+'))
        .map(
          (word) =>
              word.isEmpty
                  ? word
                  : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}
