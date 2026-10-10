import 'package:game_core/game_core.dart';

import '../model/area_level.dart';
import '../model/module_recommendation.dart';

/// Rule-based module selection for the on-device AI — pure functions with no
/// app-state dependencies that turn per-area levels into `module_details`,
/// starting levels, and summary text. No server needed.
class LocalRecommendationRules {
  const LocalRecommendationRules._();

  /// Canonical area order — drives module and summary ordering.
  static const List<String> areaOrder = [
    'communication',
    'social',
    'play',
    'attention',
  ];

  /// Registry category for each AI area key. Attention is absent — it has
  /// no registry category (it's measured across games).
  static const Map<String, SkillCategory> categoryForAreaKey = {
    'play': SkillCategory.playSkills,
    'communication': SkillCategory.communication,
    'social': SkillCategory.socialInteraction,
  };

  /// Games recommended for attention concerns, including hintay, the newest
  /// attention game.
  static const List<String> attentionGameIds = ['hintay', 'do_what_i_say', 'match_it'];

  /// Human-readable focus fragments per area.
  static const Map<String, String> areaSummary = {
    'communication': 'imitation and verbal instruction skills',
    'social': 'turn-taking and social interaction',
    'play': 'matching and creative play',
    'attention': 'focus and sustained attention',
  };

  /// For every non-Strength area, recommends the registered games that
  /// target it, deduplicated by game with the lowest starting level winning
  /// (the area needing the most support drives difficulty). When
  /// [featureValues] contains a per-game accuracy, a strong raw performance
  /// may *raise* that game's starting level, exactly like the server.
  static List<ModuleRecommendation> deriveModuleDetails(
    Map<String, AreaLevel> areaLevels, {
    Map<String, double>? featureValues,
  }) {
    final byGame = <String, ModuleRecommendation>{};

    for (final area in areaOrder) {
      final level = areaLevels[area];
      if (level == null || level.levelInt >= 2) continue; // Strength — skip

      final games = area == 'attention'
          ? attentionGameIds
              .map(GameRegistry.find)
              .whereType<GameEntry>()
              .toList()
          : GameRegistry.gamesForCategory(categoryForAreaKey[area]!);

      final startingLevel = (level.levelInt + 1).clamp(1, 3);
      for (final game in games) {
        final existing = byGame[game.id];
        if (existing == null || startingLevel < existing.startingLevel) {
          byGame[game.id] = ModuleRecommendation(
            gameId: game.id,
            name: game.name,
            startingLevel: startingLevel,
          );
        }
      }
    }

    // Balanced profile (all areas at Strength): the manuscript's "Mixed
    // Starter Module" — a balanced mix of all activities at the advanced
    // level, so a strong child still gets a learning path.
    if (byGame.isEmpty && areaLevels.isNotEmpty) {
      for (final game in GameRegistry.games) {
        byGame[game.id] = ModuleRecommendation(
          gameId: game.id,
          name: game.name,
          startingLevel: 3,
        );
      }
    }

    // Accuracy refinement: strong raw performance on a game raises its
    // starting level even when another area triggered the recommendation.
    if (featureValues != null) {
      for (final entry in byGame.entries.toList()) {
        final acc = featureValues['${entry.key}_accuracy'];
        if (acc == null) continue;
        final accBased = acc >= 0.8 ? 3 : (acc >= 0.5 ? 2 : 1);
        if (accBased > entry.value.startingLevel) {
          byGame[entry.key] = ModuleRecommendation(
            gameId: entry.value.gameId,
            name: entry.value.name,
            startingLevel: accBased,
          );
        }
      }
    }

    return byGame.values.toList();
  }

  /// Parent-facing summary sentence for the assessment result.
  static String buildSummaryText(Map<String, AreaLevel> areaLevels) {
    final needs = [
      for (final area in areaOrder)
        if ((areaLevels[area]?.levelInt ?? 2) != 2) areaSummary[area]!,
    ];
    if (needs.isEmpty) {
      return 'Your child shows balanced skills across all areas. '
          'A mixed starter module is recommended.';
    }
    if (needs.length == 1) {
      return 'Your child may benefit from activities that build ${needs[0]}.';
    }
    if (needs.length == 2) {
      return 'Your child may benefit from activities that build '
          '${needs[0]} and ${needs[1]}.';
    }
    return 'Your child may benefit from activities that build '
        '${needs.sublist(0, needs.length - 1).join(', ')}, '
        'and ${needs.last}.';
  }
}
