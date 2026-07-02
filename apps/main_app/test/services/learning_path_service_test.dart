import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/model/module_recommendation.dart';
import 'package:aumazing/services/learning_path_service.dart';
import 'package:aumazing/services/local_recommendation_rules.dart';

AreaLevel _level(int levelInt) => AreaLevel(
      level: ['needs_support', 'emerging', 'strength'][levelInt],
      levelInt: levelInt,
      levelName: ['Needs Support', 'Emerging', 'Strength'][levelInt],
      confidence: 0.9,
    );

void main() {
  group('LearningPathService.buildPath', () {
    test('weakest area comes first and sets its games to Easy', () {
      final path = LearningPathService.buildPath(areaLevels: {
        'play': _level(1), // Emerging
        'communication': _level(0), // Needs Support — weakest
        'social': _level(2), // Strength
      });

      expect(path, isNotEmpty);
      // Communication games lead the path at difficulty 1.
      expect(path.first.areaKey, 'communication');
      expect(path.first.difficulty, 1);
      // No game from a Strength-only area (my_turn_your_turn is social-only).
      expect(path.any((e) => e.game.id == 'my_turn_your_turn'), isFalse);
    });

    test('all-Strength profile yields the Mixed Starter (all games, Lvl 3)',
        () {
      final path = LearningPathService.buildPath(areaLevels: {
        'play': _level(2),
        'communication': _level(2),
        'social': _level(2),
        'attention': _level(2),
      });
      expect(path, isNotEmpty);
      expect(path.every((e) => e.difficulty == 3), isTrue);
      // Every supported game participates in the mixed starter.
      expect(path.map((e) => e.game.id).toSet(),
          containsAll(['match_it', 'copy_me', 'trace_it', 'sari_sari_sort']));
    });

    test('games are deduplicated — weakest area claims shared games', () {
      // copy_me belongs to communication AND play in the registry.
      final path = LearningPathService.buildPath(areaLevels: {
        'communication': _level(0),
        'play': _level(1),
      });
      final copyMeEntries = path.where((e) => e.game.id == 'copy_me');
      expect(copyMeEntries.length, 1);
      expect(copyMeEntries.single.areaKey, 'communication');
      expect(copyMeEntries.single.difficulty, 1);
    });

    test('inactive games are excluded', () {
      final path = LearningPathService.buildPath(
        areaLevels: {'play': _level(0)},
        activeGameIds: {'match_it'},
      );
      expect(path.map((e) => e.game.id), ['match_it']);
    });

    test('server starting level overrides the area-derived difficulty', () {
      final path = LearningPathService.buildPath(
        areaLevels: {'play': _level(0)}, // would default to 1
        serverModules: const [
          ModuleRecommendation(
              gameId: 'match_it', name: 'Match It', startingLevel: 2),
        ],
      );
      final matchIt = path.firstWhere((e) => e.game.id == 'match_it');
      expect(matchIt.difficulty, 2);
    });

    test('registered play games (trace_it, sari_sari_sort) join the path',
        () {
      final path =
          LearningPathService.buildPath(areaLevels: {'play': _level(1)});
      final ids = path.map((e) => e.game.id).toSet();
      expect(ids, containsAll(['match_it', 'trace_it', 'sari_sari_sort']));
      // Emerging → Medium
      expect(path.every((e) => e.difficulty == 2), isTrue);
    });
  });

  group('LearningPathService ↔ recommended activities consistency', () {
    test('path mirrors the derived modules (same games, same levels)', () {
      final areaLevels = {
        'communication': _level(0),
        'social': _level(2),
        'play': _level(1),
        'attention': _level(1),
      };
      final modules =
          LocalRecommendationRules.deriveModuleDetails(areaLevels);
      final path = LearningPathService.buildPath(areaLevels: areaLevels);

      expect(path.map((e) => e.game.id).toSet(),
          modules.map((m) => m.gameId).toSet());
      for (final step in path) {
        final module = modules.firstWhere((m) => m.gameId == step.game.id);
        expect(step.difficulty, module.startingLevel,
            reason: '${step.game.id} level must match the activities list');
      }
      // Most-support modules first.
      for (var i = 1; i < path.length; i++) {
        expect(path[i].difficulty, greaterThanOrEqualTo(path[i - 1].difficulty));
      }
    });

    test('attention-driven games appear on the path', () {
      final path = LearningPathService.buildPath(areaLevels: {
        'communication': _level(2),
        'social': _level(2),
        'play': _level(2),
        'attention': _level(0),
      });
      expect(path.map((e) => e.game.id).toSet(),
          {'do_what_i_say', 'match_it'});
      expect(path.every((e) => e.difficulty == 1), isTrue);
    });
  });

  group('LocalRecommendationRules.deriveModuleDetails (on-device rules)', () {
    test('non-Strength areas produce modules; Strength areas none', () {
      final modules = LocalRecommendationRules.deriveModuleDetails({
        'communication': _level(0),
        'social': _level(2),
        'play': _level(2),
        'attention': _level(2),
      });
      final ids = modules.map((m) => m.gameId).toSet();
      expect(ids, contains('copy_me'));
      expect(ids, contains('do_what_i_say'));
      expect(ids.contains('my_turn_your_turn'), isFalse);
      // Needs Support → start at level 1
      expect(modules.every((m) => m.startingLevel == 1), isTrue);
    });

    test('attention concerns recommend its mapped games', () {
      final modules = LocalRecommendationRules.deriveModuleDetails({
        'communication': _level(2),
        'social': _level(2),
        'play': _level(2),
        'attention': _level(1),
      });
      expect(modules.map((m) => m.gameId).toSet(),
          {'do_what_i_say', 'match_it'});
      expect(modules.every((m) => m.startingLevel == 2), isTrue);
    });

    test('lowest starting level wins on dedup; accuracy can raise it', () {
      final modules = LocalRecommendationRules.deriveModuleDetails(
        {
          'communication': _level(0), // copy_me → 1
          'play': _level(1), // copy_me also targets play → 2
        },
        featureValues: {'copy_me_accuracy': 0.85}, // raises to 3
      );
      final copyMe = modules.firstWhere((m) => m.gameId == 'copy_me');
      expect(copyMe.startingLevel, 3);
    });

    test('summary mirrors the cloud wording', () {
      expect(
        LocalRecommendationRules.buildSummaryText({
          'communication': _level(2),
          'social': _level(2),
          'play': _level(2),
          'attention': _level(2),
        }),
        contains('balanced skills'),
      );
      expect(
        LocalRecommendationRules.buildSummaryText({
          'communication': _level(0),
          'social': _level(2),
          'play': _level(2),
          'attention': _level(2),
        }),
        'Your child may benefit from activities that build '
        'imitation and verbal instruction skills.',
      );
    });
  });

  group('LearningPathService.isUnlocked (sequential progression)', () {
    test('only step 1 is open at the start; steps unlock in order', () {
      final path = LearningPathService.buildPath(areaLevels: {
        'communication': _level(0),
        'play': _level(1),
      });
      expect(path.length, greaterThanOrEqualTo(3));

      // Nothing completed: only the first step is playable.
      expect(LearningPathService.isUnlocked(path, 0, const {}), isTrue);
      expect(LearningPathService.isUnlocked(path, 1, const {}), isFalse);
      expect(LearningPathService.isUnlocked(path, 2, const {}), isFalse);

      // Completing step 1 opens step 2 but not step 3.
      final oneDone = {path[0].game.id};
      expect(LearningPathService.isUnlocked(path, 1, oneDone), isTrue);
      expect(LearningPathService.isUnlocked(path, 2, oneDone), isFalse);

      // Completed steps stay playable (replay).
      expect(LearningPathService.isUnlocked(path, 0, oneDone), isTrue);
    });

    test('a completed later step is playable even if earlier ones are not',
        () {
      final path = LearningPathService.buildPath(areaLevels: {
        'communication': _level(0),
        'play': _level(1),
      });
      final lastId = path.last.game.id;
      expect(
        LearningPathService.isUnlocked(path, path.length - 1, {lastId}),
        isTrue,
      );
    });
  });

  group('LearningPathService.nextOnPath', () {
    test('returns the following entry and null at the end', () {
      final path = LearningPathService.buildPath(areaLevels: {
        'communication': _level(0),
        'play': _level(1),
      });
      expect(path.length, greaterThanOrEqualTo(2));

      final next = LearningPathService.nextOnPath(path, path.first.game.id);
      expect(next?.game.id, path[1].game.id);

      expect(
          LearningPathService.nextOnPath(path, path.last.game.id), isNull);
      expect(LearningPathService.nextOnPath(path, 'not_a_game'), isNull);
    });
  });
}
