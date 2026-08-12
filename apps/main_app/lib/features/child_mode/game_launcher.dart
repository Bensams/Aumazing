import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';

import '../../model/area_level.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../games/copy_me/copy_me_screen.dart';
import '../games/do_what_i_say/do_what_i_say_screen.dart';
import '../games/match_it/match_it_screen.dart';
import '../games/my_turn_your_turn/my_turn_your_turn_screen.dart';
import '../games/sari_sari_sort/sari_sari_sort_screen.dart';
import '../games/trace_it/trace_it_screen.dart';
import '../games/hintay/hintay_screen.dart';
import '../games/anong_susunod/anong_susunod_screen.dart';
import '../games/tulong_kaibigan/tulong_kaibigan_screen.dart';
import '../../widgets/mascot_host.dart';

/// Shared launcher for practice (non-assessment) games.
///
/// One source of truth — used by the child lobby and the post-reward
/// Next/Lobby choice — for:
/// - which games have a practice screen wired up,
/// - each game's difficulty (parent override → AI per-area level → fallback),
/// - building the practice screen for a game id.
class GameLauncher {
  GameLauncher._();

  /// Games that have a main_app practice screen wired up.
  static const supportedGameIds = {
    'match_it',
    'copy_me',
    'do_what_i_say',
    'my_turn_your_turn',
    'sari_sari_sort',
    'trace_it',
    'hintay',
    'anong_susunod',
    'tulong_kaibigan',
  };

  /// AI per-area keys for each skill category (matches the on-device model's
  /// area names: communication / social / play / attention).
  static const areaKeyForCategory = {
    SkillCategory.playSkills: 'play',
    SkillCategory.communication: 'communication',
    SkillCategory.socialInteraction: 'social',
  };

  /// All supported games in registry order, deduplicated.
  static List<GameEntry> supportedGames() => GameRegistry.games
      .where((g) => supportedGameIds.contains(g.id))
      .toList();

  /// The game after [currentId] in registry order (wraps around); null when
  /// nothing else is available.
  static GameEntry? nextEntry(String currentId) {
    final games = supportedGames();
    if (games.isEmpty) return null;
    final i = games.indexWhere((g) => g.id == currentId);
    if (i < 0) return games.first;
    return games[(i + 1) % games.length];
  }

  /// Difficulty for one game: the parent's manual override wins; then the
  /// AI's recommended starting level for this exact module (matches the
  /// "AI Recommended Activities" list and the learning path); then the AI's
  /// per-area level for the game's skill area(s) (weakest area = more
  /// support); otherwise [fallback] (the overall recommended level).
  static int difficultyFor(
    BuildContext context,
    GameEntry entry, {
    int? fallback,
  }) {
    final override = context.read<ChildProvider>().difficultyOverride;
    if (override != null) return override.clamp(1, 3);

    final assessment = context.read<AssessmentProvider>();

    // Per-module starting level from the AI recommendation, when this game
    // was recommended — keeps every difficulty chip consistent with the
    // learning path.
    final modules = assessment.aiPrediction?.moduleDetails ?? const [];
    for (final module in modules) {
      if (module.gameId == entry.id) return module.startingLevel.clamp(1, 3);
    }

    final areaLevels =
        assessment.aiPrediction?.areaLevels ?? const <String, AreaLevel>{};

    int? weakest;
    for (final cat in entry.categories) {
      final area = areaLevels[areaKeyForCategory[cat]];
      if (area == null) continue;
      weakest = weakest == null
          ? area.levelInt
          : (area.levelInt < weakest ? area.levelInt : weakest);
    }
    if (weakest != null) return weakest + 1; // 0/1/2 → 1/2/3

    return (fallback ?? assessment.recommendedLevel).clamp(1, 3);
  }

  /// Builds the practice screen for [gameId], or null if unsupported.
  ///
  /// Wrapped in a [MascotHost] so the mascot keeps the child company during
  /// play: the host must be an ANCESTOR of the game screen for the game's
  /// MascotHost.maybeOf lookups to find it.
  static Widget? screenFor(String gameId, int difficulty) {
    final game = _gameFor(gameId, difficulty);
    return game == null ? null : MascotHost(child: game);
  }

  static Widget? _gameFor(String gameId, int difficulty) {
    switch (gameId) {
      case 'match_it':
        return MatchItScreen(
            assessmentContext: 'practice', difficulty: difficulty);
      case 'copy_me':
        return CopyMeScreen(
            assessmentContext: 'practice', difficulty: difficulty);
      case 'do_what_i_say':
        return DoWhatISayScreen(
            assessmentContext: 'practice', difficulty: difficulty);
      case 'my_turn_your_turn':
        return MyTurnYourTurnScreen(
            assessmentContext: 'practice', difficulty: difficulty);
      case 'sari_sari_sort':
        return SariSariSortScreen(
            assessmentContext: 'practice', difficulty: difficulty);
      case 'trace_it':
        return TraceItScreen(
            assessmentContext: 'practice', difficulty: difficulty);
      case 'hintay':
        return HintayScreen(
            assessmentContext: 'practice', difficulty: difficulty);
      case 'anong_susunod':
        return AnongSusunodScreen(
            assessmentContext: 'practice', difficulty: difficulty);
      case 'tulong_kaibigan':
        return TulongKaibiganScreen(
            assessmentContext: 'practice', difficulty: difficulty);
    }
    return null;
  }
}
