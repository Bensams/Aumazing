import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

/// Cards and slots now print the step's name under its picture, and both are
/// laid out from whatever canvas the device hands the game — a 3-slot row on a
/// short landscape phone gets small. The label divides by that size, so the
/// sizes worth testing are the extreme ones.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Draws [component] to a throwaway canvas, returning nothing but throwing
  /// whatever the render throws.
  void render(PositionComponent component) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    component.render(canvas);
    recorder.endRecording().dispose();
  }

  // "Kumain ng almusal" / "Mokaon og pamahaw" are the longest labels in the
  // set, so they are the ones that decide whether the strip is wide enough.
  final longestStep = kRoutines[0].steps[2];

  group('a routine card renders its label at every card size', () {
    for (final size in const [
      Size(40, 52), // absurdly small: a 4-card tray on a narrow phone
      Size(90, 120),
      Size(220, 280),
    ]) {
      for (final language in GameLanguage.values) {
        test('${size.width.toInt()}x${size.height.toInt()} in ${language.slug}',
            () {
          final card = RoutineCard(
            step: longestStep,
            language: language,
            position: Vector2.zero(),
            size: Vector2(size.width, size.height),
          );
          expect(() => render(card), returnsNormally);
        });
      }
    }
  });

  group('a sequence slot renders its seated step at every slot size', () {
    for (final size in const [Size(48, 64), Size(120, 160), Size(260, 340)]) {
      test('${size.width.toInt()}x${size.height.toInt()}', () {
        final slot = SequenceSlot(
          index: 0,
          language: GameLanguage.cebuano,
          position: Vector2.zero(),
          size: Vector2(size.width, size.height),
        )..filled = longestStep;
        expect(() => render(slot), returnsNormally);
      });
    }

    test('an empty slot renders without a label', () {
      final slot = SequenceSlot(
        index: 2,
        language: GameLanguage.tagalog,
        position: Vector2.zero(),
        size: Vector2(120, 160),
      );
      expect(() => render(slot), returnsNormally);
    });
  });
}
