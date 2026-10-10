import 'package:flutter_test/flutter_test.dart';

import 'package:game_core/game_core.dart';

import 'package:aumazing/features/child_mode/game_launcher.dart';
import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/services/active_games_service.dart';
import 'package:aumazing/services/local_recommendation_rules.dart';
import 'package:aumazing/services/recommendation_filter.dart';

/// Area level helper mirroring `learning_path_service_test.dart`.
///
/// `levelInt` 0 = needs_support, 1 = emerging, 2 = strength.
AreaLevel _level(int levelInt) => AreaLevel(
      level: ['needs_support', 'emerging', 'strength'][levelInt],
      levelInt: levelInt,
      levelName: ['Needs Support', 'Emerging', 'Strength'][levelInt],
      confidence: 0.9,
    );

void main() {
  final registryIds = GameRegistry.games.map((g) => g.id).toSet();
  final supportedIds = GameLauncher.supportedGameIds;

  group('Practice catalog is closed', () {
    test('the registry and the launcher agree on the practice set', () {
      expect(GameRegistry.games, isNotEmpty,
          reason: 'GameRegistry.games must not be empty.');
      // Every registry game is practice-launchable, and no practice game is
      // unregistered. A drift here reveals the other three guard groups.
      expect(supportedIds, registryIds,
          reason: 'GameLauncher.supportedGameIds and GameRegistry.games '
              'must be identical.');
      expect(supportedIds, hasLength(12),
          reason: 'The practice catalog is the 12 known games.');
    });
  });

  group('On-device eligibility (LocalRecommendationRules)', () {
    test('every practice game is reachable when all areas need support', () {
      final modules = LocalRecommendationRules.deriveModuleDetails({
        'communication': _level(0),
        'social': _level(0),
        'play': _level(0),
        'attention': _level(0),
      });
      final ids = modules.map((m) => m.gameId).toSet();
      final unreachable = supportedIds.difference(ids);
      expect(unreachable, isEmpty,
          reason: 'On-device rules failed to reach: $unreachable');
    });

    test('balanced/strength profile yields the mixed starter (all games)',
        () {
      final modules = LocalRecommendationRules.deriveModuleDetails({
        'communication': _level(2),
        'social': _level(2),
        'play': _level(2),
        'attention': _level(2),
      });
      final ids = modules.map((m) => m.gameId).toSet();
      final missing = supportedIds.difference(ids);
      expect(missing, isEmpty,
          reason: 'Mixed-starter profile omitted: $missing');
      expect(modules.every((m) => m.startingLevel == 3), isTrue,
          reason: 'Mixed-starter modules must all start at level 3.');
    });
  });

  group('Attention parity', () {
    test('on-device attention ids match the cloud area exactly', () {
      expect(LocalRecommendationRules.attentionGameIds,
          ['hintay', 'do_what_i_say', 'match_it']);
    });
  });

  group('Display-name join keys', () {
    test('every registry name maps to its game id in both title maps', () {
      for (final game in GameRegistry.games) {
        expect(ActiveGamesService.titleToGameId[game.name], game.id,
            reason: 'ActiveGamesService.titleToGameId is missing or wrong '
                'for "${game.name}" (${game.id}).');
        expect(RecommendationFilter.nameToGameId[game.name], game.id,
            reason: 'RecommendationFilter.nameToGameId is missing or wrong '
                'for "${game.name}" (${game.id}).');
      }
    });
  });

  group('Launchable', () {
    test('every practice game has a wired practice screen', () {
      for (final id in supportedIds) {
        expect(GameLauncher.screenFor(id, 1), isNotNull,
            reason: 'GameLauncher.screenFor("$id", 1) returned null.');
      }
    });
  });
}
