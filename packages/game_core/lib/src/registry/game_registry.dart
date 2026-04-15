import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../config/game_config.dart';
import '../games/match_it/match_it_game.dart';

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
          onStepChanged: onStepChanged,
          onGameComplete: onGameComplete,
        );
      },
    ),

    // TODO: Add more games here as they are implemented:
    // - Copy Me (drag-and-drop)
    // - Do What I Say (tapping / following instructions)
    // - My Turn Your Turn (turn-taking)
    // - Trace It (tracing / fine motor)
  ];

  /// Look up a game by its ID. Returns null if not found.
  static GameEntry? find(String id) {
    try {
      return games.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }
}
