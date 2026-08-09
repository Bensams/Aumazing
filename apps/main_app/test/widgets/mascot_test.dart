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
