import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// Guards the sprite-sheet geometry contract. The sheets are generated
/// offline by `scripts/generate_sprites.py`, so these assertions are what
/// catch a mis-cut grid before it reaches a screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> decode(ImageProvider provider) async {
    final codec =
        await ui.instantiateImageCodec((provider as MemoryImage).bytes);
    return (await codec.getNextFrame()).image;
  }

  for (final entry in {
    'bps': CharacterSprites.bps,
    'reiz': CharacterSprites.reiz,
    'lexianne': CharacterSprites.lexianne,
  }.entries) {
    group(entry.key, () {
      // An optional action whose art hasn't been generated yet is absent
      // rather than wrong, and the mascot is built to carry on without it —
      // so the geometry assertions apply to whatever sheets do exist.
      List<String> loaded(CharacterSprites s) => [
            for (final e in CharacterSprites.layout.entries)
              if (!(e.value.optional && s.frames(e.key).isEmpty)) e.key,
          ];

      test('every action slices into its declared frame count', () async {
        final s = await entry.value();
        for (final action in loaded(s)) {
          expect(s.frames(action), hasLength(CharacterSprites.layout[action]!.frames),
              reason: '${entry.key}_$action.png');
        }
      });

      test('a missing required sheet is loud, a missing optional one is not',
          () async {
        // The whole point of `optional`: adding an action ahead of its art
        // must not take the character off screen.
        final s = await entry.value();
        for (final e in CharacterSprites.layout.entries) {
          if (e.value.optional) continue;
          expect(s.frames(e.key), isNotEmpty,
              reason: '${entry.key}_${e.key}.png must exist');
        }
      });

      test('every action shares one cell size', () async {
        // CalmMascot renders frames at a fixed height with BoxFit.contain, so
        // a sheet with a different cell size would make the mascot change
        // size or slide sideways the moment it switches action.
        final s = await entry.value();
        final rest = await decode(s.rest);
        for (final action in loaded(s)) {
          final frame = await decode(s.frames(action).first);
          expect(frame.width, rest.width, reason: '${entry.key}_$action width');
          expect(frame.height, rest.height,
              reason: '${entry.key}_$action height');
        }
      });

      test('still actions expose a single pose', () async {
        final s = await entry.value();
        for (final action in ['encourage', 'listen', 'sleepy', 'think']) {
          expect(s.still(action), isNotNull, reason: action);
          expect(s.frames(action), hasLength(1), reason: action);
        }
      });

      test('the gaze poses form a 3x3 grid around the rest frame', () async {
        // Indexed by where the child's finger is, so each corner of the
        // screen must reach the matching corner pose, and the middle must
        // leave the character looking straight ahead.
        final s = await entry.value();
        if (!s.canGaze) return; // poses not generated for this character yet
        const near = 0.1, far = 0.9, mid = 0.5;
        expect(s.gazeFrameFor(mid, mid), same(s.rest),
            reason: 'a drag through the middle must not stare off-screen');
        for (final (x, y, pose) in [
          (near, mid, 'look_left'),
          (far, mid, 'look_right'),
          (mid, near, 'look_up'),
          (mid, far, 'look_down'),
          (near, near, 'look_up_left'),
          (far, near, 'look_up_right'),
          (near, far, 'look_down_left'),
          (far, far, 'look_down_right'),
        ]) {
          if (s.still(pose) == null) continue; // not generated yet
          expect(s.gazeFrameFor(x, y), same(s.still(pose)), reason: pose);
        }
      });

      test('a fingertip dragged off the screen clamps to a corner', () async {
        final s = await entry.value();
        if (!s.canGaze) return;
        expect(s.gazeFrameFor(-0.4, 0.5), same(s.still('look_left')));
        expect(s.gazeFrameFor(1.7, 0.5), same(s.still('look_right')));
        // Must not throw or return null anywhere in the plane.
        for (var x = -1.0; x <= 2.0; x += 0.25) {
          for (var y = -1.0; y <= 2.0; y += 0.25) {
            expect(s.gazeFrameFor(x, y), isNotNull, reason: '($x, $y)');
          }
        }
      });

      test('a missing corner falls back rather than snapping to centre',
          () async {
        // Corners land in a different generation run from the edges, so this
        // is the state the app is in mid-rollout. Dropping to the rest frame
        // whenever a drag strays high or low would look like the character
        // losing interest.
        final s = await entry.value();
        if (!s.canGaze || s.still('look_up_left') != null) return;
        expect(s.gazeFrameFor(0.1, 0.1), same(s.still('look_left')));
      });

      test('every gaze pose is cut to the same cell as the rest frame',
          () async {
        // They are separate single-frame sheets from separate clips, so
        // nothing but this stops one of them shipping at a different scale
        // and making the mascot jump the moment a child drags sideways.
        final s = await entry.value();
        if (!s.canGaze) return;
        final rest = await decode(s.rest);
        for (final action in CharacterSprites.layout.keys) {
          if (!action.startsWith('look_')) continue;
          final pose = s.still(action);
          if (pose == null) continue;
          final frame = await decode(pose);
          expect(frame.width, rest.width, reason: '${entry.key}_$action width');
          expect(frame.height, rest.height,
              reason: '${entry.key}_$action height');
        }
      });

      test('unknown actions are empty rather than throwing', () async {
        final s = await entry.value();
        expect(s.frames('nope'), isEmpty);
        expect(s.still('nope'), isNull);
      });
    });
  }

  group('precacheCostumed', () {
    // Warming exists so the lobby mascot never flashes its fallback while a
    // costume's sheets decode. It runs fire-and-forget from the child provider,
    // so its one hard promise is that it never throws into that caller — a
    // costume with no sheets must warm the base outfit quietly, not surface an
    // error where nothing is there to catch it.
    test('a costume with no sheets warms quietly instead of throwing', () async {
      await expectLater(
        CharacterSprites.precacheCostumed('bps', 'costume-that-does-not-exist'),
        completes,
      );
    });

    test('an empty or "none" costume warms the base character', () async {
      await expectLater(
        CharacterSprites.precacheCostumed('bps', 'none'),
        completes,
      );
      // The base sheets are now cached, so the mascot resolves without a decode
      // wait — the whole point of warming ahead of the build.
      expect((await CharacterSprites.bps()).rest, isNotNull);
    });
  });
}
