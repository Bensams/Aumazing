import 'package:flutter/material.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aumazing/widgets/mascot.dart';
import 'package:aumazing/widgets/mascot_host.dart';

void main() {
  group('MascotController', () {
    test('play bumps the tick so the widget sees a changed trigger', () {
      final c = MascotController();
      addTearDown(c.dispose);

      final before = c.tick;
      c.play(MascotGesture.celebrate);

      expect(c.gesture, MascotGesture.celebrate);
      expect(c.tick, greaterThan(before),
          reason: 'CalmMascot only replays when the trigger value changes');
    });

    test('repeating the same gesture still replays it', () {
      final c = MascotController();
      addTearDown(c.dispose);

      c.play(MascotGesture.nod);
      final first = c.tick;
      c.play(MascotGesture.nod);

      // Two correct answers in a row must nod twice, not sit still because
      // the gesture name happens to be unchanged.
      expect(c.tick, greaterThan(first));
    });

    test('flash holds a pose then returns to idle', () {
      fakeAsync((async) {
        final c = MascotController();
        addTearDown(c.dispose);

        c.flash(MascotPose.encourage,
            duration: const Duration(milliseconds: 500));
        expect(c.pose, MascotPose.encourage);

        async.elapse(const Duration(milliseconds: 499));
        expect(c.pose, MascotPose.encourage, reason: 'still holding');

        async.elapse(const Duration(milliseconds: 2));
        expect(c.pose, MascotPose.idle);
      });
    });

    test('reassure plays oops, then holds an encouraging pose, then idles', () {
      fakeAsync((async) {
        final c = MascotController();
        addTearDown(c.dispose);

        c.reassure();
        expect(c.gesture, MascotGesture.oops);
        expect(c.pose, MascotPose.idle,
            reason: 'the sad beat is the gesture; the pose changes after it');

        async.elapse(MascotGesture.oops.duration);
        // The whole reason this exists: a wrong answer must not leave the
        // character sad. It must recover into encouragement on its own.
        expect(c.pose, MascotPose.encourage);

        async.elapse(const Duration(seconds: 5));
        expect(c.pose, MascotPose.idle);
      });
    });

    test('a second mistake mid-reaction does not restart it', () {
      fakeAsync((async) {
        final c = MascotController();
        addTearDown(c.dispose);

        c.reassure();
        final first = c.tick;
        async.elapse(MascotGesture.oops.duration);
        c.reassure();

        // Flicking back to sad while the encouragement is still on screen is
        // exactly the unpredictable motion this app avoids.
        expect(c.tick, first);
        expect(c.pose, MascotPose.encourage);
      });
    });

    test('a reaction that has finished can run again', () {
      fakeAsync((async) {
        final c = MascotController();
        addTearDown(c.dispose);

        c.reassure();
        async.elapse(const Duration(seconds: 10));
        expect(c.isReassuring, isFalse);

        final before = c.tick;
        c.reassure();
        expect(c.tick, greaterThan(before));
      });
    });

    test('a deliberate gesture or pose supersedes a pending reaction', () {
      fakeAsync((async) {
        final c = MascotController();
        addTearDown(c.dispose);

        c.reassure();
        c.play(MascotGesture.celebrate);
        async.elapse(const Duration(seconds: 10));

        // The encouraging half must not surface on top of a celebration that
        // was started afterwards.
        expect(c.pose, MascotPose.idle);
        expect(c.gesture, MascotGesture.celebrate);

        c.reassure();
        c.rest(MascotPose.think);
        async.elapse(const Duration(seconds: 10));
        expect(c.pose, MascotPose.think);
      });
    });

    test('an explicit rest cancels a pending flash revert', () {
      fakeAsync((async) {
        final c = MascotController();
        addTearDown(c.dispose);

        c.flash(MascotPose.think, duration: const Duration(seconds: 1));
        c.rest(MascotPose.sleepy);
        async.elapse(const Duration(seconds: 2));

        // The stale revert must not drag the mascot out of a pose that was
        // set deliberately afterwards.
        expect(c.pose, MascotPose.sleepy);
      });
    });

    group('gaze', () {
      test('watch settles toward the point being tracked, on both axes', () {
        final c = MascotController();
        addTearDown(c.dispose);

        // First call snaps: there is no previous gaze to ease from, and
        // starting every drag from the middle of the screen would make the
        // character swing across on pickup.
        c.watch(const Offset(0.9, 0.8));
        expect(c.gaze.value, const Offset(0.9, 0.8));

        // Subsequent calls ease, so a jerky drag doesn't become twitching
        // eyes — but they must actually converge.
        c.watch(const Offset(0.1, 0.2));
        final step = c.gaze.value!;
        expect(step.dx, lessThan(0.9));
        expect(step.dx, greaterThan(0.1), reason: 'eased, not snapped');
        expect(step.dy, lessThan(0.8));
        expect(step.dy, greaterThan(0.2));

        for (var i = 0; i < 120; i++) {
          c.watch(const Offset(0.1, 0.2));
        }
        expect(c.gaze.value!.dx, closeTo(0.1, 0.01));
        expect(c.gaze.value!.dy, closeTo(0.2, 0.01));
      });

      test('watch clamps a finger dragged off the edge of the screen', () {
        final c = MascotController();
        addTearDown(c.dispose);

        c.watch(const Offset(-3, -2));
        expect(c.gaze.value, Offset.zero);
        c.watch(null);
        c.watch(const Offset(4.2, 9));
        expect(c.gaze.value, const Offset(1, 1));
      });

      test('releasing stops the tracking outright', () {
        final c = MascotController();
        addTearDown(c.dispose);

        c.watch(const Offset(0.7, 0.3));
        c.watch(null);

        // Not "eased back to the middle" — nothing is being watched, and the
        // character returns to its resting pose.
        expect(c.gaze.value, isNull);
      });

      test('gaze does not churn the pose/gesture channel', () {
        final c = MascotController();
        addTearDown(c.dispose);

        var notifications = 0;
        c.addListener(() => notifications++);
        for (var i = 0; i < 60; i++) {
          c.watch(Offset(i / 60, i / 60));
        }

        // A drag updates every frame; routing that through the main channel
        // would rebuild the whole mascot's plumbing at 60 fps to move eyes.
        expect(notifications, 0);
      });
    });
  });

  group('MascotHost', () {
    testWidgets('exposes its controller to descendants', (tester) async {
      late MascotController found;
      await tester.pumpWidget(MaterialApp(
        home: MascotHost(
          child: Builder(builder: (context) {
            found = MascotHost.of(context);
            return const SizedBox();
          }),
        ),
      ));
      expect(found, isNotNull);
    });

    testWidgets('maybeOf is null with no host above', (tester) async {
      MascotController? found = MascotController();
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          found = MascotHost.maybeOf(context);
          return const SizedBox();
        }),
      ));
      expect(found, isNull);
    });

    testWidgets('does not dispose a controller it does not own',
        (tester) async {
      final external = MascotController();
      await tester.pumpWidget(MaterialApp(
        home: MascotHost(controller: external, child: const SizedBox()),
      ));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // Still usable after the host is gone — disposing a borrowed controller
      // would throw here.
      expect(() => external.play(MascotGesture.wave), returnsNormally);
      external.dispose();
    });

    testWidgets('mascot does not swallow taps meant for the screen',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: MascotHost(
          alignment: Alignment.center,
          child: GestureDetector(
            key: const Key('screen'),
            onTap: () => taps++,
            child: const SizedBox.expand(child: ColoredBox(color: Colors.red)),
          ),
        ),
      ));
      // Tap dead centre, where the mascot itself is placed.
      await tester.tap(find.byKey(const Key('screen')));
      expect(taps, 1);
    });
  });
}
