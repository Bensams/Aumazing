import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../config/game_config.dart';
import '../games/match_it/match_it_game.dart';
import '../games/copy_me/copy_me_game.dart';
import '../games/do_what_i_say/do_what_i_say_game.dart';
import '../games/my_turn_your_turn/my_turn_your_turn_game.dart';
import '../games/sari_sari_sort/sari_sari_sort_game.dart';
import '../games/trace_it/trace_it_game.dart';
import 'skill_category.dart';

/// Metadata for a single playable mini-game.
class GameEntry {
  /// Unique identifier (e.g. 'match_it').
  final String id;

  /// Human-readable name.
  final String name;

  /// Short description shown in the launcher.
  final String description;

  /// Icon displayed on the game card.
  final IconData icon;

  /// Background gradient colors for the game card.
  final List<Color> gradientColors;

  /// Developmental skill categories this game targets.
  /// A game can belong to multiple categories.
  final List<SkillCategory> categories;

  /// Factory that creates a new instance of the Flame game.
  final FlameGame Function({
    required GameConfig config,
    required void Function(int currentStep) onStepChanged,
    required void Function({
      required int score,
      required int totalItems,
      required int errorCount,
      required int totalResponseTimeMs,
    }) onGameComplete,
  }) create;

  const GameEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.gradientColors,
    required this.categories,
    required this.create,
  });
}

/// Central catalog of all available Aumazing mini-games.
///
/// Used by game_lab's launcher screen to dynamically list games,
/// and by main_app's assessment flow to iterate over games.
class GameRegistry {
  GameRegistry._();

  static final List<GameEntry> games = [
    GameEntry(
      id: 'match_it',
      name: 'Match It',
      description: 'Tap shapes that look the same to make a match.',
      icon: Icons.extension_rounded,
      categories: [SkillCategory.playSkills],
      gradientColors: [
        const Color(0xFFD4F4E8),
        const Color(0xFFD4E8FA),
        const Color(0xFFE8DEFA),
      ],
      create: ({
        required GameConfig config,
        required void Function(int) onStepChanged,
        required void Function({
          required int score,
          required int totalItems,
          required int errorCount,
          required int totalResponseTimeMs,
        }) onGameComplete,
      }) {
        return MatchItGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          onStepChanged: onStepChanged,
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            analytics,
          }) {
            onGameComplete(
              score: score,
              totalItems: totalItems,
              errorCount: errorCount,
              totalResponseTimeMs: totalResponseTimeMs,
            );
          },
        );
      },
    ),
    GameEntry(
      id: 'copy_me',
      name: 'Copy Me',
      description: 'Watch the sequence, then copy it!',
      icon: Icons.content_copy_rounded,
      categories: [SkillCategory.communication, SkillCategory.playSkills],
      gradientColors: [
        const Color(0xFFFFF3D4),
        const Color(0xFFFFDDD4),
        const Color(0xFFD4F4E8),
      ],
      create: ({
        required GameConfig config,
        required void Function(int) onStepChanged,
        required void Function({
          required int score,
          required int totalItems,
          required int errorCount,
          required int totalResponseTimeMs,
        }) onGameComplete,
      }) {
        return CopyMeGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          onStepChanged: onStepChanged,
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            analytics,
          }) {
            onGameComplete(
              score: score,
              totalItems: totalItems,
              errorCount: errorCount,
              totalResponseTimeMs: totalResponseTimeMs,
            );
          },
        );
      },
    ),
    GameEntry(
      id: 'do_what_i_say',
      name: 'Do What I Say',
      description: 'Follow the instructions to tap the right shape!',
      icon: Icons.record_voice_over_rounded,
      categories: [SkillCategory.communication],
      gradientColors: [
        const Color(0xFFE8DEFA),
        const Color(0xFFD4F4E8),
        const Color(0xFFFFF3D4),
      ],
      create: ({
        required GameConfig config,
        required void Function(int) onStepChanged,
        required void Function({
          required int score,
          required int totalItems,
          required int errorCount,
          required int totalResponseTimeMs,
        }) onGameComplete,
      }) {
        return DoWhatISayGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          onStepChanged: onStepChanged,
          onInstructionChanged: (_) {}, // placeholder
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            required Map<String, dynamic> extras,
            analytics,
          }) {
            onGameComplete(
              score: score,
              totalItems: totalItems,
              errorCount: errorCount,
              totalResponseTimeMs: totalResponseTimeMs,
            );
          },
        );
      },
    ),
    GameEntry(
      id: 'my_turn_your_turn',
      name: 'My Turn, Your Turn',
      description: 'Take turns placing shapes with your buddy!',
      icon: Icons.people_rounded,
      categories: [SkillCategory.socialInteraction],
      gradientColors: [
        const Color(0xFFD4E8FA),
        const Color(0xFFE8DEFA),
        const Color(0xFFFFDDD4),
      ],
      create: ({
        required GameConfig config,
        required void Function(int) onStepChanged,
        required void Function({
          required int score,
          required int totalItems,
          required int errorCount,
          required int totalResponseTimeMs,
        }) onGameComplete,
      }) {
        return MyTurnYourTurnGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          onStepChanged: onStepChanged,
          onTurnChanged: (_) {}, // placeholder
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            required Map<String, dynamic> extras,
            analytics,
          }) {
            onGameComplete(
              score: score,
              totalItems: totalItems,
              errorCount: errorCount,
              totalResponseTimeMs: totalResponseTimeMs,
            );
          },
        );
      },
    ),
    GameEntry(
      id: 'sari_sari_sort',
      name: 'Sari-Sari Store Sorting',
      description: 'Drag each item into the right basket at the store!',
      icon: Icons.storefront_rounded,
      categories: [SkillCategory.playSkills, SkillCategory.communication],
      gradientColors: [
        const Color(0xFFFFF3D4),
        const Color(0xFFD4F4E8),
        const Color(0xFFD4E8FA),
      ],
      create: ({
        required GameConfig config,
        required void Function(int) onStepChanged,
        required void Function({
          required int score,
          required int totalItems,
          required int errorCount,
          required int totalResponseTimeMs,
        }) onGameComplete,
      }) {
        return SariSariSortGame(
          totalRounds: config.totalRounds,
          itemsPerRound: config.itemsPerRound,
          childId: config.childId,
          gameVersion: config.gameVersion,
          strings: config.strings,
          onStepChanged: onStepChanged,
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            analytics,
          }) {
            onGameComplete(
              score: score,
              totalItems: totalItems,
              errorCount: errorCount,
              totalResponseTimeMs: totalResponseTimeMs,
            );
          },
        );
      },
    ),
    GameEntry(
      id: 'trace_it',
      name: 'Trace It',
      description: 'Trace the letter or number with your finger!',
      icon: Icons.gesture_rounded,
      categories: [SkillCategory.playSkills],
      gradientColors: [
        const Color(0xFFD4E8FA),
        const Color(0xFFFFF3D4),
        const Color(0xFFE8DEFA),
      ],
      create: ({
        required GameConfig config,
        required void Function(int) onStepChanged,
        required void Function({
          required int score,
          required int totalItems,
          required int errorCount,
          required int totalResponseTimeMs,
        }) onGameComplete,
      }) {
        return TraceItGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          onStepChanged: onStepChanged,
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            analytics,
          }) {
            onGameComplete(
              score: score,
              totalItems: totalItems,
              errorCount: errorCount,
              totalResponseTimeMs: totalResponseTimeMs,
            );
          },
        );
      },
    ),
  ];

  /// Look up a game by its ID. Returns null if not found.
  static GameEntry? find(String id) {
    try {
      return games.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Returns all games that belong to the given category.
  static List<GameEntry> gamesForCategory(SkillCategory category) {
    return games.where((g) => g.categories.contains(category)).toList();
  }

  /// Returns all categories that a given game belongs to.
  static List<SkillCategory> categoriesForGame(String gameId) {
    final game = find(gameId);
    return game?.categories ?? [];
  }

  /// The 4 assessment game IDs in play order.
  static const assessmentGameIds = [
    'copy_me',
    'do_what_i_say',
    'my_turn_your_turn',
    'match_it',
  ];
}
