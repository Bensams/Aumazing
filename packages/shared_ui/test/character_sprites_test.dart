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

      test('unknown actions are empty rather than throwing', () async {
        final s = await entry.value();
        expect(s.frames('nope'), isEmpty);
        expect(s.still('nope'), isNull);
      });
    });
  }
}
