import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aumazing/widgets/mascot.dart';
import 'package:shared_ui/shared_ui.dart';

/// End-to-end cover for the one thing mascot_test.dart cannot see: that a
/// gesture actually swaps the pixels on screen. The controller tests prove the
/// tick changes; these prove the sheets load and the frames play.
void main() {
  ImageProvider? shown(WidgetTester tester) {
    final images = tester.widgetList<Image>(find.byType(Image));
    return images.isEmpty ? null : images.last.image;
  }

  /// Blinking is off unless a test asks for it: it swaps the frame list out
  /// from under CalmMascot, so left on it would be indistinguishable from a
  /// gesture frame in every assertion below.
  Widget mascot(Object trigger, MascotGesture gesture, {bool blink = false}) =>
      MaterialApp(
        home: Center(
          child: Mascot(
            gesture: gesture,
            gestureTrigger: trigger,
            entrance: MascotEntrance.none,
            greetOnAppear: false,
            blink: blink,
          ),
        ),
      );

  testWidgets('sprite sheets load and the mascot renders a rest frame',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(mascot(0, MascotGesture.celebrate));
      // Slicing re-encodes 57 cells as PNGs; give it real time.
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();

    expect(shown(tester), isNotNull,
        reason: 'no Image means the sheets never decoded');
  });

  testWidgets('a changed trigger plays the celebrate frames', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(mascot(0, MascotGesture.celebrate));
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();

    final rest = shown(tester);
    expect(rest, isNotNull);

    await tester.pumpWidget(mascot(1, MascotGesture.celebrate));
    await tester.pump();

    expect(shown(tester), isNot(rest),
        reason: 'bumping the trigger must show a celebrate frame, not the '
            'resting idle pose');

    // And it must keep advancing, not freeze on frame 0.
    final first = shown(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(shown(tester), isNot(first));
  });

  testWidgets('an oops sinks the mascot gently and puts it back',
      (tester) async {
    // The sink is the app's own motion, so it is the whole of the reaction on
    // a character whose `oops` sheet hasn't been generated yet — and it must
    // still leave the mascot exactly where it found it.
    await tester.runAsync(() async {
      await tester.pumpWidget(mascot(0, MascotGesture.oops));
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();
    final resting = tester.getTopLeft(find.byType(Image).last).dy;

    await tester.pumpWidget(mascot(1, MascotGesture.oops));
    await tester.pump(MascotGesture.oops.duration ~/ 2);
    expect(tester.getTopLeft(find.byType(Image).last).dy,
        greaterThan(resting + 3),
        reason: 'mid-oops the character should have dipped downward');

    await tester.pump(MascotGesture.oops.duration);
    expect(tester.getTopLeft(find.byType(Image).last).dy,
        closeTo(resting, 2.5),
        reason: 'the dip must resolve — the mascot does not stay slumped');
  });

  testWidgets('celebrate outlasts the reward overlay, a nod does not',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(mascot(0, MascotGesture.celebrate));
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();
    final rest = shown(tester);

    await tester.pumpWidget(mascot(1, MascotGesture.celebrate));
    await tester.pump(const Duration(seconds: 8));
    expect(shown(tester), isNot(rest),
        reason: 'the reward runs ~10 s; the mascot must not have gone back to '
            'resting a third of the way in');

    // A nod is the counterweight: it must stay short.
    await tester.pumpWidget(mascot(2, MascotGesture.nod));
    await tester.pump(const Duration(seconds: 8));
    expect(shown(tester), rest);
  });

  testWidgets('equipping a costume re-dresses a mascot already on screen',
      (tester) async {
    // The bug this pins: the sheets were loaded once, in initState, so a
    // costume bought in the shop left the lobby buddy in its old outfit until
    // something else tore the screen down. The lobby watches the profile and
    // rebuilds this widget in place, so the change has to arrive through
    // didUpdateWidget or it does not arrive at all.
    Widget dressed(String costumeId) => MaterialApp(
          home: Center(
            child: Mascot(
              costumeId: costumeId,
              gestureTrigger: 0,
              entrance: MascotEntrance.none,
              greetOnAppear: false,
              blink: false,
            ),
          ),
        );

    await tester.runAsync(() async {
      await tester.pumpWidget(dressed('none'));
      await Future<void>.delayed(const Duration(seconds: 5));
      await tester.pump();
      final bare = shown(tester);
      expect(bare, isNotNull, reason: 'the base sheets never decoded');

      await tester.pumpWidget(dressed('teddy'));
      await Future<void>.delayed(const Duration(seconds: 5));
      await tester.pump();

      expect(shown(tester), isNot(bare),
          reason: 'the mascot is still wearing its old outfit — a costume '
              'equipped in the shop must show up without the screen being '
              'rebuilt from scratch');
    });
  });

  testWidgets('switching character swaps the mascot on screen', (tester) async {
    // Same mechanism, the other half of the pair: a parent changing the
    // child's character must not leave the previous one standing there.
    Widget who(MascotCharacter character) => MaterialApp(
          home: Center(
            child: Mascot(
              character: character,
              gestureTrigger: 0,
              entrance: MascotEntrance.none,
              greetOnAppear: false,
              blink: false,
            ),
          ),
        );

    await tester.runAsync(() async {
      await tester.pumpWidget(who(MascotCharacter.bps));
      await Future<void>.delayed(const Duration(seconds: 5));
      await tester.pump();
      final bps = shown(tester);
      expect(bps, isNotNull);

      await tester.pumpWidget(who(MascotCharacter.reiz));
      await Future<void>.delayed(const Duration(seconds: 5));
      await tester.pump();

      expect(shown(tester), isNot(bps));
    });
  });

  testWidgets('the mascot blinks by itself, then goes back to resting',
      (tester) async {
    // Resting is a single still, so without this the character is a drawing
    // that happens to breathe. The blink is what makes it read as present.
    //
    // Real time throughout: the blink timer is started from the sprite load's
    // continuation, which lands in the real async zone, so the fake clock
    // would never fire it.
    await tester.runAsync(() async {
      // Take the rest pose from the sheets rather than from whatever is on
      // screen at some arbitrary moment — a blink may already be running.
      final rest = (await CharacterSprites.bps()).rest;

      await tester.pumpWidget(mascot(0, MascotGesture.nod, blink: true));
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
      expect(shown(tester), isNotNull, reason: 'the sheets never decoded');

      // A blink is due within 7 s and holds each of its four non-rest frames
      // for ~167 ms, so sampling every 150 ms cannot step over one.
      ImageProvider? blinked;
      for (var i = 0; i < 60 && blinked == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump();
        final frame = shown(tester);
        if (frame != null && frame != rest) blinked = frame;
      }
      expect(blinked, isNotNull,
          reason: 'the mascot never blinked — the idle sheet has four frames '
              'past the rest pose and nothing was playing them');

      // And it has to end. A blink that stuck would leave the character
      // sitting with its eyes shut, which is worse than never blinking.
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();
      expect(shown(tester), rest);
    });
  });
}
