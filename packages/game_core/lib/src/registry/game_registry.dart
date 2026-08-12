import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../config/game_config.dart';
import '../games/match_it/match_it_game.dart';
import '../games/copy_me/copy_me_game.dart';
import '../games/do_what_i_say/do_what_i_say_game.dart';
import '../games/my_turn_your_turn/my_turn_your_turn_game.dart';
import '../games/sari_sari_sort/sari_sari_sort_game.dart';
import '../games/trace_it/trace_it_game.dart';
import '../games/hintay/hintay_game.dart';
import '../games/anong_susunod/anong_susunod_game.dart';
import '../games/sabay_tayo/sabay_tayo_game.dart';
import '../games/kumusta/kumusta_game.dart';
import '../games/anong_nararamdaman/anong_nararamdaman_game.dart';
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
  ///
  /// Kept alongside [logoAsset] as the small-space and fallback form: it is
  /// what a monochrome chip or a failed SVG decode falls back to.
  final IconData icon;

  /// The game's own illustrated logo tile, as a shared_ui asset path.
  ///
  /// Rendered by `GameLogo`. Full path (`packages/shared_ui/assets/...`) so any
  /// app in the workspace can show it without declaring the asset itself.
  final String logoAsset;

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
    required this.logoAsset,
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

  /// Path to a game's illustrated logo tile, which lives in shared_ui so
  /// main_app and game_lab both get it from the package bundle.
  static String _logo(String id) =>
      'packages/shared_ui/assets/game_logos/$id.svg';

  static final List<GameEntry> games = [
    GameEntry(
      id: 'match_it',
      name: 'Match It',
      description: 'Tap shapes that look the same to make a match.',
      icon: Icons.extension_rounded,
      logoAsset: _logo('match_it'),
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
      logoAsset: _logo('copy_me'),
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
      logoAsset: _logo('do_what_i_say'),
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
      logoAsset: _logo('my_turn_your_turn'),
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
      description:
          'Move each picture to the right basket — toys, food, or things!',
      icon: Icons.storefront_rounded,
      logoAsset: _logo('sari_sari_sort'),
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
      logoAsset: _logo('trace_it'),
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
    GameEntry(
      id: 'hintay',
      name: 'Hintay!',
      description: 'Wait for the star to wake up, then tap it!',
      icon: Icons.hourglass_top_rounded,
      logoAsset: _logo('hintay'),
      // Tagged Play Skills because the enum carries no `attention` value yet
      // (it mirrors `skill_categories.slug` in Supabase, so adding one needs a
      // migration first). The attention routing lives in the AI service, where
      // `rules.py` already has an `attention` area and now recommends this game
      // for it.
      categories: [SkillCategory.playSkills],
      gradientColors: [
        const Color(0xFFE8DEFA),
        const Color(0xFFD4E8FA),
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
        return HintayGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          onStepChanged: onStepChanged,
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
      id: 'anong_susunod',
      name: "Ano'ng Susunod?",
      description: 'Put the steps of the routine in the right order!',
      icon: Icons.checklist_rounded,
      logoAsset: _logo('anong_susunod'),
      // A visual schedule is a communication support as much as a play task:
      // the child is reading a sequence of pictures and acting on it.
      categories: [SkillCategory.playSkills, SkillCategory.communication],
      gradientColors: [
        const Color(0xFFD4F4E8),
        const Color(0xFFFFF3D4),
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
        return AnongSusunodGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          strings: config.strings,
          onStepChanged: onStepChanged,
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
      id: 'sabay_tayo',
      name: 'Sabay Tayo!',
      description: 'Look where your buddy is looking, then tap what they see!',
      icon: Icons.visibility_rounded,
      logoAsset: _logo('sabay_tayo'),
      // Social Interaction first and foremost: following another person's gaze
      // to a shared referent is the earliest social skill on the developmental
      // ladder, and the only game here that trains it directly. Play Skills is
      // secondary — the tap-the-object layer is a play task wrapped around it.
      categories: [SkillCategory.socialInteraction, SkillCategory.playSkills],
      gradientColors: [
        const Color(0xFFFFE4D4),
        const Color(0xFFD4F4E8),
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
        return SabayTayoGame(
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
      id: 'kumusta',
      name: 'Kumusta!',
      description: 'Your buddy says hello — greet them back!',
      icon: Icons.waving_hand_rounded,
      logoAsset: _logo('kumusta'),
      // The one game aimed squarely at social interaction: responding to
      // another person's bid. Also tagged communication, since a returned
      // greeting is a non-verbal conversational turn.
      categories: [
        SkillCategory.socialInteraction,
        SkillCategory.communication,
      ],
      gradientColors: [
        const Color(0xFFFFE8D4),
        const Color(0xFFFFF3D4),
        const Color(0xFFD4EEFA),
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
        return KumustaGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          onStepChanged: onStepChanged,
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
      id: 'anong_nararamdaman',
      name: "Ano'ng Nararamdaman?",
      description: 'How is your friend feeling? Find the face that matches!',
      icon: Icons.sentiment_satisfied_alt_rounded,
      logoAsset: _logo('anong_nararamdaman'),
      // Social interaction first: reading a friend's face is the target skill.
      // Communication is not a courtesy tag — every trial ends with the emotion
      // word spoken back, so the game is also an emotion-vocabulary drill.
      categories: [
        SkillCategory.socialInteraction,
        SkillCategory.communication,
      ],
      gradientColors: [
        const Color(0xFFFFDDD4),
        const Color(0xFFE8DEFA),
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
        return AnongNararamdamanGame(
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
