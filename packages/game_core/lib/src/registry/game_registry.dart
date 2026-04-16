import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../config/game_config.dart';
import '../games/match_it/match_it_game.dart';
import '../games/copy_me/copy_me_game.dart';
import '../games/do_what_i_say/do_what_i_say_game.dart';
import '../games/my_turn_your_turn/my_turn_your_turn_game.dart';

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
    GameEntry(
      id: 'copy_me',
      name: 'Copy Me',
      description: 'Watch the sequence, then copy it!',
      icon: Icons.content_copy_rounded,
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
          onStepChanged: onStepChanged,
          onGameComplete: onGameComplete,
        );
      },
    ),
    GameEntry(
      id: 'do_what_i_say',
      name: 'Do What I Say',
      description: 'Follow the instructions to tap the right shape!',
      icon: Icons.record_voice_over_rounded,
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
          onStepChanged: onStepChanged,
          onInstructionChanged: (_) {}, // placeholder
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            required Map<String, dynamic> extras,
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
          onStepChanged: onStepChanged,
          onTurnChanged: (_) {}, // placeholder
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            required Map<String, dynamic> extras,
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

  /// The 4 assessment game IDs in play order.
  static const assessmentGameIds = [
    'copy_me',
    'do_what_i_say',
    'my_turn_your_turn',
    'match_it',
  ];
}
