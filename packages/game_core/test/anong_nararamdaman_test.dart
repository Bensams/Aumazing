import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart' show GameLanguage;

/// Ano'ng Nararamdaman? — the emotion-recognition game.
///
/// These cover the failures that are invisible until a clinician reads the
/// session and finds it says nothing. An unfair tier-1 pair makes a beginner
/// look worse than they are; a tier-2 trial with no near-miss (or with two)
/// makes `near_miss_rate` meaningless; and a confusion metric that records only
/// "wrong" throws away the one number this game exists to produce.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Warmed here so the game's own await inside onLoad resolves on a
    // microtask; decoding twenty PNGs mid-pump does not, and the widget test
    // below then never gets past the first frame.
    await EmotionArtCache.ensureLoaded('bps');
  });

  AnongNararamdamanGame gameAtTier(int level) => AnongNararamdamanGame(
        childId: 'test-child',
        profile: DifficultyProfile.forLevel(level),
        onStepChanged: (_) {},
        onGameComplete: ({
          required int score,
          required int totalItems,
          required int errorCount,
          required int totalResponseTimeMs,
          required Map<String, dynamic> extras,
          analytics,
        }) {},
      );

  /// Enough repetitions that a rule which only *usually* holds fails here.
  const trials = 200;

  group('near-miss pairs', () {
    test('the confusable pairs are symmetric and never self-pairs', () {
      for (final a in Emotion.values) {
        expect(isNearMiss(a, a), isFalse,
            reason: '${a.slug} cannot be confused with itself');
        for (final b in Emotion.values) {
          expect(isNearMiss(a, b), isNearMiss(b, a),
              reason: '${a.slug}/${b.slug} must read the same either way');
        }
      }
    });

    test('every emotion has both a confusable partner and two safe ones', () {
      // Tier 2 needs the first (it must offer a near-miss) and tier 1 needs
      // the second (it must fill two cards without one). A new emotion that
      // breaks either would silently make a whole tier unbuildable.
      for (final e in Emotion.values) {
        expect(nearTo(e), isNotEmpty,
            reason: '${e.slug} has no near-miss — tier 2 cannot build a trial');
        expect(farFrom(e).length, greaterThanOrEqualTo(2),
            reason: '${e.slug} has too few safe distractors for tier 1');
      }
    });
  });

  group('tier 1 — maximally distinct', () {
    test('never pairs two near-miss emotions', () {
      final game = gameAtTier(1);
      for (var i = 0; i < trials; i++) {
        for (final target in Emotion.values) {
          final options = game.optionsFor(target);
          expect(options, hasLength(2));
          expect(options, contains(target));
          final other = options.firstWhere((e) => e != target);
          expect(isNearMiss(other, target), isFalse,
              reason: 'tier 1 offered ${target.slug} against ${other.slug}, '
                  'which are the pair children confuse');
        }
      }
    });
  });

  group('tier 2 — exactly one near-miss', () {
    test('always includes exactly one near-miss of the target', () {
      final game = gameAtTier(2);
      for (final count in [3, 4]) {
        for (var i = 0; i < trials; i++) {
          for (final target in Emotion.values) {
            final options = game.optionsFor(target, cardCount: count);
            expect(options, hasLength(count));
            expect(options, contains(target));

            final nearMisses =
                options.where((e) => isNearMiss(e, target)).toList();
            expect(nearMisses, hasLength(1),
                reason: 'tier 2 offered ${nearMisses.length} near-misses for '
                    '${target.slug} — one is the whole point, and two makes a '
                    'wrong tap stop identifying which confusion the child has');
          }
        }
      }
    });

    test('offers no duplicate cards', () {
      final game = gameAtTier(2);
      for (var i = 0; i < trials; i++) {
        for (final target in Emotion.values) {
          final options = game.optionsFor(target, cardCount: 4);
          expect(options.toSet(), hasLength(options.length));
        }
      }
    });
  });

  group('tier 3 — four cards, still exactly one near-miss', () {
    test('keeps the near-miss rule at four cards', () {
      final game = gameAtTier(3);
      for (var i = 0; i < trials; i++) {
        for (final target in Emotion.values) {
          final options = game.optionsFor(target);
          expect(options, hasLength(4));
          expect(options.where((e) => isNearMiss(e, target)), hasLength(1));
        }
      }
    });
  });

  group('scenes', () {
    test('every emotion is carried by more than one situation', () {
      // One picture per emotion is memorisable: a child can learn "the ice
      // cream card means sad" without ever reading the face.
      for (final e in Emotion.values) {
        final scenes = kEmotionScenes.where((s) => s.emotion == e);
        expect(scenes.length, greaterThanOrEqualTo(2),
            reason: '${e.slug} has only ${scenes.length} scene(s)');
      }
    });

    test('scene ids are unique', () {
      final ids = kEmotionScenes.map((s) => s.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('the caring response varies within an emotion', () {
      // The response hangs off the scene, not the emotion — see EmotionScene.
      // If every sad scene took the same response the tier-3 step would be a
      // lookup table, and a child could pass it without looking at the picture.
      final byEmotion = <Emotion, Set<CaringResponse>>{};
      for (final s in kEmotionScenes) {
        byEmotion.putIfAbsent(s.emotion, () => {}).add(s.response);
      }
      expect(byEmotion.values.any((r) => r.length > 1), isTrue,
          reason: 'no emotion maps to more than one caring response, so the '
              'response step is derivable from the emotion alone');
    });

    test('every caring response is reachable from some scene', () {
      final used = kEmotionScenes.map((s) => s.response).toSet();
      for (final r in CaringResponse.values) {
        expect(used, contains(r),
            reason: '${r.slug} is only ever a distractor — a card the child is '
                'shown four times a session and never once told is right');
      }
    });
  });

  group('labels', () {
    test('every emotion is named in all three languages, distinctly', () {
      for (final language in GameLanguage.values) {
        final labels =
            Emotion.values.map((e) => e.label(language)).toList();
        for (final label in labels) {
          expect(label.trim(), isNotEmpty);
        }
        expect(labels.toSet(), hasLength(labels.length),
            reason: 'two emotions share a printed word in $language, so two '
                'cards would read identically');
      }
    });

    test('every caring response is named in all three languages', () {
      for (final language in GameLanguage.values) {
        for (final r in CaringResponse.values) {
          expect(r.label(language).trim(), isNotEmpty);
        }
      }
    });

    test('every scene has a caption in all three languages', () {
      for (final language in GameLanguage.values) {
        for (final s in kEmotionScenes) {
          expect(s.caption(language).trim(), isNotEmpty,
              reason: '${s.id} has no caption in $language');
        }
      }
    });
  });

  group('art', () {
    test('every picture points at the emotion_cards bundle', () {
      for (final f in FaceArt.values) {
        expect(f.assetPath,
            'packages/shared_ui/assets/emotion_cards/face_${f.assetName}.png');
      }
      for (final s in SceneArt.values) {
        expect(s.assetPath, contains('assets/emotion_cards/scene_'));
      }
      for (final r in ResponseArt.values) {
        expect(r.assetPath, contains('assets/emotion_cards/do_'));
      }
    });

    test('every scene has its own picture', () {
      final art = kEmotionScenes.map((s) => s.art).toList();
      expect(art.toSet(), hasLength(art.length));
    });
  });

  group('confusion pairs', () {
    /// Driven through a real [GameWidget] rather than by calling the handlers
    /// directly: a bare `FlameGame` in a test is never mounted, so constructed
    /// events carry no component path for `localPosition` to resolve against.
    /// Pumping real pointers exercises what the child actually meets.
    Future<AnongNararamdamanGame> boot(WidgetTester tester) async {
      final game = AnongNararamdamanGame(
        childId: 'test-child',
        profile: DifficultyProfile.medium,
        onStepChanged: (_) {},
        onGameComplete: ({
          required score,
          required totalItems,
          required errorCount,
          required totalResponseTimeMs,
          required extras,
          analytics,
        }) {},
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: GameWidget(game: game))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      return game;
    }

    testWidgets('a wrong tap records which emotion was chosen, not a boolean',
        (tester) async {
      final game = await boot(tester);

      final target = game.currentTarget;
      expect(target, isNotNull,
          reason: 'the game did not open a trial on load');

      final wrong = game.children
          .whereType<EmotionCard>()
          .firstWhere((c) => c.emotion != target);

      await tester.tapAt(
          Offset(wrong.position.x, wrong.position.y));
      await tester.pump(const Duration(milliseconds: 32));

      // The point of the assertion: the key names BOTH emotions. A metric that
      // recorded only "wrong" would pass an error count and lose the reason —
      // a child who reads every scared face as sad is a different child from
      // one tapping at random, and only this map can tell them apart.
      expect(game.confusionPairs,
          contains('${target!.slug}->${wrong.emotion.slug}'));
      expect(game.confusionPairs['${target.slug}->${wrong.emotion.slug}'], 1);

      // And it counts, rather than merely flagging.
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tapAt(Offset(wrong.position.x, wrong.position.y));
      await tester.pump(const Duration(milliseconds: 32));
      expect(game.confusionPairs['${target.slug}->${wrong.emotion.slug}'], 2);

      // Tear the tree down inside the test. The game re-arms its idle prompt
      // for as long as it is alive, so letting the harness dispose the widget
      // after the body has returned leaves that timer pending and fails the
      // test on an invariant that has nothing to do with what it checks.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
