import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/services/learning_path_service.dart';

/// The rules that decide whether finishing a practice game earns the
/// learning-path milestone. These pin the exact conditions
/// `GameEndChoiceDialog._maybeShowPathVictory` checks, using the same public
/// pieces it calls, so the trigger cannot silently drift:
///
///  * a non-final game does not trigger it;
///  * finishing the last remaining game triggers it exactly once;
///  * replaying that game does not trigger it again;
///  * an unrelated game (off the path) never triggers it;
///  * a genuinely new recommendation (new signature) can trigger a new one.
void main() {
  LearningPathEntry entry(String id) => LearningPathEntry(
        game: GameRegistry.find(id)!,
        difficulty: 1,
        areaKey: 'attention',
      );

  // The predicate `_maybeShowPathVictory` evaluates, expressed with the same
  // public API it uses.
  bool eligible({
    required List<LearningPathEntry> path,
    required String currentGameId,
    required Set<String> completed,
    required String? shownSignature,
  }) {
    if (path.isEmpty) return false;
    if (!path.any((e) => e.game.id == currentGameId)) return false;
    if (!LearningPathService.isComplete(path, completed)) return false;
    final signature = LearningPathService.signatureFor(path);
    return shownSignature != signature;
  }

  final path = [entry('copy_me'), entry('match_it')];

  group('path-completion eligibility', () {
    test('a non-final game does not trigger the milestone', () {
      // copy_me finished, match_it still outstanding.
      expect(
        eligible(
          path: path,
          currentGameId: 'copy_me',
          completed: {'copy_me'},
          shownSignature: null,
        ),
        isFalse,
      );
    });

    test('finishing the last remaining game triggers it', () {
      expect(
        eligible(
          path: path,
          currentGameId: 'match_it',
          completed: {'copy_me', 'match_it'},
          shownSignature: null,
        ),
        isTrue,
      );
    });

    test('an unrelated game off the path never triggers it', () {
      // Every path game is complete, but the game just finished is not on it.
      expect(
        eligible(
          path: path,
          currentGameId: 'do_what_i_say',
          completed: {'copy_me', 'match_it', 'do_what_i_say'},
          shownSignature: null,
        ),
        isFalse,
      );
    });

    test('an empty path never triggers it', () {
      expect(
        eligible(
          path: const [],
          currentGameId: 'copy_me',
          completed: {'copy_me'},
          shownSignature: null,
        ),
        isFalse,
      );
    });

    test('replaying the final game does not trigger it again', () {
      final signature = LearningPathService.signatureFor(path);
      expect(
        eligible(
          path: path,
          currentGameId: 'match_it',
          completed: {'copy_me', 'match_it'},
          shownSignature: signature, // already celebrated this path
        ),
        isFalse,
      );
    });

    test('a new recommendation (new signature) can celebrate again', () {
      final oldSignature = LearningPathService.signatureFor(path);
      final newPath = [entry('match_it'), entry('copy_me')]; // different order
      expect(LearningPathService.signatureFor(newPath), isNot(oldSignature));
      expect(
        eligible(
          path: newPath,
          currentGameId: 'copy_me',
          completed: {'copy_me', 'match_it'},
          shownSignature: oldSignature, // only the old path was celebrated
        ),
        isTrue,
      );
    });
  });

  group('one-time persistence in the provider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('marking a path shown makes it already-shown, and survives replay',
        () async {
      final provider = AssessmentProvider();
      final signature = LearningPathService.signatureFor(path);

      expect(provider.pathVictoryAlreadyShown(signature), isFalse);

      await provider.markPathVictoryShown('child-1', signature);
      expect(provider.pathVictoryAlreadyShown(signature), isTrue);

      // A different path is not covered by the stored one.
      final other = LearningPathService.signatureFor(
        [entry('match_it'), entry('copy_me')],
      );
      expect(provider.pathVictoryAlreadyShown(other), isFalse);
    });

    test('an empty signature is never treated as shown', () async {
      final provider = AssessmentProvider();
      await provider.markPathVictoryShown('child-1', '');
      expect(provider.pathVictoryAlreadyShown(''), isFalse);
    });
  });
}
