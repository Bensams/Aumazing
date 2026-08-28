import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';

import '../features/child_mode/game_launcher.dart';
import '../model/area_level.dart';
import '../model/module_recommendation.dart';
import '../providers/assessment_provider.dart';
import 'local_recommendation_rules.dart';

/// One step of the child's recommended learning path.
class LearningPathEntry {
  const LearningPathEntry({
    required this.game,
    required this.difficulty,
    required this.areaKey,
  });

  /// The game to play at this step.
  final GameEntry game;

  /// Starting difficulty (1 Easy … 3 Hard) for this step.
  final int difficulty;

  /// The weakest AI area this game targets
  /// ('communication' / 'social' / 'play' / 'attention').
  final String areaKey;
}

/// Builds the child's recommended learning path from the pre-assessment.
///
/// The path is the AI's recommended modules, made playable. It uses the
/// exact same module list and starting levels as the "AI Recommended
/// Activities" shown to the parent ([AiAssessmentResponse.moduleDetails],
/// or the identical local rules when a prediction carries none), so the
/// parent-facing list and the child's path can never disagree.
class LearningPathService {
  const LearningPathService._();

  /// Builds the ordered learning path.
  ///
  /// Modules needing the most support (lowest starting level) come first;
  /// ties keep the recommender's own order.
  ///
  /// [areaLevels] — the AI's per-area levels (cloud or on-device).
  /// [serverModules] — the prediction's module details; when empty they are
  /// derived locally from [areaLevels] via [LocalRecommendationRules].
  /// [featureValues] — raw features for the local rules' accuracy refinement.
  /// [activeGameIds] — games enabled by the administrator; null = all active.
  static List<LearningPathEntry> buildPath({
    required Map<String, AreaLevel> areaLevels,
    List<ModuleRecommendation> serverModules = const [],
    Map<String, double>? featureValues,
    Set<String>? activeGameIds,
  }) {
    final modules = serverModules.isNotEmpty
        ? serverModules
        : LocalRecommendationRules.deriveModuleDetails(
            areaLevels,
            featureValues: featureValues,
          );
    if (modules.isEmpty) return const [];

    // Most support first (lowest starting level); stable on ties so the
    // recommender's own ordering is preserved.
    final indexed = modules.asMap().entries.toList()
      ..sort((a, b) {
        final byLevel = a.value.startingLevel.compareTo(b.value.startingLevel);
        return byLevel != 0 ? byLevel : a.key.compareTo(b.key);
      });

    final path = <LearningPathEntry>[];
    final seen = <String>{};
    for (final entry in indexed) {
      final module = entry.value;
      if (!seen.add(module.gameId)) continue;
      if (!GameLauncher.supportedGameIds.contains(module.gameId)) continue;
      if (activeGameIds != null && !activeGameIds.contains(module.gameId)) {
        continue;
      }
      final game = GameRegistry.find(module.gameId);
      if (game == null) continue;
      path.add(LearningPathEntry(
        game: game,
        difficulty: module.startingLevel.clamp(1, 3),
        areaKey: _weakestAreaFor(game, areaLevels),
      ));
    }
    return path;
  }

  /// The weakest AI area among the game's skill categories — used for
  /// display/analytics. Falls back to 'attention' (the only area without a
  /// registry category) when none of the game's areas were predicted weak.
  static String _weakestAreaFor(
    GameEntry game,
    Map<String, AreaLevel> areaLevels,
  ) {
    var key = 'attention';
    var weakest = 2;
    for (final cat in game.categories) {
      final areaKey = GameLauncher.areaKeyForCategory[cat];
      final level = areaLevels[areaKey]?.levelInt;
      if (areaKey != null && level != null && level < weakest) {
        weakest = level;
        key = areaKey;
      }
    }
    return key;
  }

  /// Convenience: builds the path from the current provider state.
  /// Returns an empty list when there is no AI prediction yet.
  static List<LearningPathEntry> fromContext(
    BuildContext context, {
    Set<String>? activeGameIds,
  }) {
    final prediction = context.read<AssessmentProvider>().aiPrediction;
    if (prediction == null) return const [];
    return buildPath(
      areaLevels: prediction.areaLevels,
      serverModules: prediction.moduleDetails,
      featureValues: prediction.featureValues,
      activeGameIds: activeGameIds,
    );
  }

  /// Whether the step at [index] is unlocked (sequential progression):
  /// a step is playable when it's already completed, or when every step
  /// before it has been completed. Step 1 is always unlocked.
  static bool isUnlocked(
    List<LearningPathEntry> path,
    int index,
    Set<String> completedGameIds,
  ) {
    if (index <= 0) return true;
    if (completedGameIds.contains(path[index].game.id)) return true;
    return path
        .take(index)
        .every((e) => completedGameIds.contains(e.game.id));
  }

  /// Whether every game on [path] has been completed. False for an empty path
  /// — there is no milestone in finishing nothing.
  static bool isComplete(
    List<LearningPathEntry> path,
    Set<String> completedGameIds,
  ) =>
      path.isNotEmpty &&
      path.every((e) => completedGameIds.contains(e.game.id));

  /// A stable identity for [path] — the ordered game ids joined together.
  ///
  /// Two genuinely different recommendations (different games, or a different
  /// order) produce different signatures, so the milestone victory for a path
  /// can be shown once and a *later* fresh recommendation can earn its own.
  /// An empty path has an empty signature.
  static String signatureFor(List<LearningPathEntry> path) =>
      path.map((e) => e.game.id).join('>');

  /// The path entry after [currentGameId], or null when the current game is
  /// last on the path (or not on it). Used by the post-reward Next choice so
  /// the child moves through the path in the AI's recommended order.
  static LearningPathEntry? nextOnPath(
    List<LearningPathEntry> path,
    String currentGameId,
  ) {
    final i = path.indexWhere((e) => e.game.id == currentGameId);
    if (i < 0 || i + 1 >= path.length) return null;
    return path[i + 1];
  }
}
