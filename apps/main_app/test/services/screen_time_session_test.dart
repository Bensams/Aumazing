import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/services/screen_time_service.dart';

/// Per-session screen-time limits (AUM-162).
///
/// The session lifecycle under test, as implemented:
/// * a session **starts** when the child enters child mode (the lobby calls
///   [ScreenTimeService.startSession] as it mounts);
/// * it **continues** across games — nothing on the lobby→game→lobby path
///   restarts it, so usage just keeps accumulating;
/// * it **ends** when child mode is left (the lobby's dispose calls
///   [ScreenTimeService.endSession]) — parent exit, child switch, sign-out
///   and the lock screen's "Exit Child Mode" all pop the lobby;
/// * an app kill **suspends** it: usage is persisted on every tick, and a
///   restart within [ScreenTimeService.sessionResumeWindow] resumes the old
///   numbers, while an older suspension starts fresh.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ScreenTimeService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ScreenTimeService.clock = DateTime.now;
  });

  tearDown(() async {
    // The singleton carries state between tests — end any session and
    // restore the real clock so no test leaks into the next.
    await service.endSession();
    ScreenTimeService.clock = DateTime.now;
  });

  group('session limit configuration', () {
    test('persists per child across reloads', () async {
      await service.load('child-a');
      await service.setSessionLimitMinutes(10);

      await service.load('child-b');
      await service.setSessionLimitMinutes(20);

      await service.load('child-a');
      expect(service.sessionLimitMinutes, 10);
      await service.load('child-b');
      expect(service.sessionLimitMinutes, 20);
    });

    test('null and 0 both mean "No session limit"', () async {
      await service.load('child-a');
      await service.setSessionLimitMinutes(15);
      expect(service.sessionLimitEnabled, isTrue);

      await service.setSessionLimitMinutes(null);
      expect(service.sessionLimitEnabled, isFalse);
      expect(service.sessionRemainingSeconds, isNull);

      await service.setSessionLimitMinutes(0);
      expect(service.sessionLimitEnabled, isFalse);
    });

    test('no session limit does not disable the daily limit', () async {
      await service.load('child-a');
      await service.setLimitMinutes(1);
      await service.setSessionLimitMinutes(null);
      await service.startSession();

      await service.addUsage(60);
      expect(
        service.isExhausted,
        isTrue,
        reason: 'daily limit must still enforce with no session limit',
      );
    });
  });

  group('independent daily and session usage', () {
    test(
      'daily usage carries over into a new session, session resets',
      () async {
        await service.load('child-a');
        await service.setLimitMinutes(30);
        await service.setSessionLimitMinutes(10);

        await service.startSession();
        await service.addUsage(300);
        expect(service.usedTodaySeconds, 300);
        expect(service.sessionUsedSeconds, 300);
        await service.endSession();

        await service.startSession();
        expect(
          service.usedTodaySeconds,
          300,
          reason: 'daily usage survives the session boundary',
        );
        expect(
          service.sessionUsedSeconds,
          0,
          reason: 'a new session starts at zero',
        );
      },
    );

    test('stricter remaining limit gates play', () async {
      await service.load('child-a');
      await service.setLimitMinutes(30); // 1800s
      await service.setSessionLimitMinutes(10); // 600s
      await service.startSession();

      // Fresh: session is stricter.
      expect(service.activeRemainingSeconds, 600);

      // Second session on a nearly spent day: daily becomes stricter.
      await service.addUsage(600);
      await service.endSession();
      await service.startSession();
      expect(service.remainingSeconds, 1200);
      expect(service.sessionRemainingSeconds, 600);
      await service.addUsage(590);
      await service.endSession();
      await service.startSession();
      // 1190 used today → 610 left of the day, 600 of the session.
      expect(service.activeRemainingSeconds, 600);
      await service.addUsage(300);
      // 310 left of the day, 300 of the session → session still stricter.
      expect(service.activeRemainingSeconds, 300);
    });

    test(
      'reaching the session limit exhausts even with daily time left',
      () async {
        await service.load('child-a');
        await service.setLimitMinutes(60);
        await service.setSessionLimitMinutes(1);
        await service.startSession();

        await service.addUsage(60);
        expect(service.isExhausted, isTrue);
        expect(service.isDailyExhausted, isFalse);
        expect(service.remainingSeconds, greaterThan(0));
      },
    );
  });

  // The smaller budget must win whichever one it is. These two cases are
  // deliberately mirrored: the first has the session stricter throughout,
  // the second constructs a daily remaining that is *lower than a freshly
  // started session's* full budget, which the earlier coverage never did.
  group('stricter budget wins in both directions (AUM-162)', () {
    test('session remaining lower than daily remaining gates play', () async {
      await service.load('child-a');
      await service.setLimitMinutes(30); // 1800s daily
      await service.setSessionLimitMinutes(5); // 300s session
      await service.startSession();

      expect(service.remainingSeconds, 1800);
      expect(service.sessionRemainingSeconds, 300);
      expect(service.activeRemainingSeconds, 300);

      await service.addUsage(290);
      expect(service.activeRemainingSeconds, 10);
      expect(service.isExhausted, isFalse);

      await service.addUsage(10);
      // Session is spent while the day still has plenty left.
      expect(service.sessionRemainingSeconds, 0);
      expect(service.isExhausted, isTrue);
      expect(service.isDailyExhausted, isFalse);
      expect(service.remainingSeconds, 1500);
    });

    test(
      'daily remaining lower than a fresh session budget gates play',
      () async {
        await service.load('child-b');
        await service.setLimitMinutes(10); // 600s daily
        await service.setSessionLimitMinutes(30); // 1800s session
        await service.startSession();

        // Spend most of the day inside the first sitting.
        await service.addUsage(550);
        await service.endSession();

        // A brand-new session has its full 1800s, but the day has only 50s.
        await service.startSession();
        expect(service.sessionRemainingSeconds, 1800);
        expect(service.remainingSeconds, 50);
        expect(service.activeRemainingSeconds, 50);
        expect(service.isExhausted, isFalse);

        await service.addUsage(50);
        // The daily budget is what stops play, with session time to spare.
        expect(service.activeRemainingSeconds, 0);
        expect(service.isExhausted, isTrue);
        expect(service.isDailyExhausted, isTrue);
        expect(service.sessionRemainingSeconds, 1750);
      },
    );
  });

  // Token ownership exists so a late teardown from the previous child can
  // never touch the child who has since taken over. These drive the actual
  // lifecycle boundaries rather than trusting the comments.
  group('session ownership races (AUM-162)', () {
    test("a stale Child A dispose cannot end Child B's session", () async {
      await service.load('child-a');
      await service.setSessionLimitMinutes(10);
      final tokenA = await service.startSession();
      await service.addUsage(60);

      // The parent switches to Child B, who enters child mode.
      await service.load('child-b');
      await service.setSessionLimitMinutes(10);
      final tokenB = await service.startSession();
      await service.addUsage(30);

      // Child A's lobby finally disposes, long after the switch.
      await service.endSessionOwned(tokenA);

      expect(tokenA, isNot(tokenB));
      expect(service.sessionActive, isTrue);
      expect(service.sessionChildId, 'child-b');
      expect(service.sessionUsedSeconds, 30);
    });

    test("a stale dispose cannot delete Child B's persisted session", () async {
      await service.load('child-a');
      await service.setSessionLimitMinutes(10);
      final tokenA = await service.startSession();

      await service.load('child-b');
      await service.setSessionLimitMinutes(10);
      await service.startSession();
      await service.addUsage(45);

      await service.endSessionOwned(tokenA);

      // Child B's suspended state survives, so a quick restart resumes it
      // instead of handing back a free fresh session.
      await service.load('child-b');
      await service.startSession();
      expect(service.sessionUsedSeconds, 45);
    });

    test('a startSession superseded by a newer load does not attach', () async {
      await service.load('child-a');
      final startFuture = service.startSession();
      // Child B loads while the start is still reading storage.
      await service.load('child-b');
      final token = await startFuture;

      expect(token, isNull);
      expect(service.sessionActive, isFalse);
      expect(service.sessionChildId, isNull);
    });

    test(
      'sign-out during pending persistence does not resurrect a session',
      () async {
        await service.load('child-a');
        await service.setSessionLimitMinutes(10);
        await service.startSession();

        // A tick is still persisting when child mode is torn down.
        final pendingTick = service.addUsage(60);
        await service.endSession();
        await pendingTick;

        expect(service.sessionActive, isFalse);

        // The next sitting starts clean — the in-flight write must not have
        // re-created the session state behind it.
        await service.startSession();
        expect(service.sessionUsedSeconds, 0);
      },
    );
  });

  group('session continuity (multiple games)', () {
    test('usage accumulates across game launches without resetting', () async {
      await service.load('child-a');
      await service.setSessionLimitMinutes(10);
      await service.startSession();

      // Three games in a row — the lobby never restarts the session, so at
      // the service level this is simply consecutive usage ticks with no
      // startSession between them.
      await service.addUsage(120); // game 1
      await service.addUsage(180); // game 2
      await service.addUsage(60); // game 3
      expect(service.sessionUsedSeconds, 360);
      expect(service.sessionRemainingSeconds, 600 - 360);
    });
  });

  group('app restart during an active session', () {
    test('a quick restart resumes the suspended session', () async {
      await service.load('child-a');
      await service.setSessionLimitMinutes(10);
      await service.startSession();
      await service.addUsage(400);

      // Restart: the app is killed (no endSession), relaunched, and the
      // lobby is re-entered a minute later.
      final relaunch = DateTime.now().add(const Duration(minutes: 1));
      ScreenTimeService.clock = () => relaunch;
      await service.load('child-a');
      expect(
        service.sessionUsedSeconds,
        0,
        reason: 'nothing counts until child mode is re-entered',
      );
      await service.startSession();
      expect(
        service.sessionUsedSeconds,
        400,
        reason: 'restart within the resume window cannot reset a session',
      );
    });

    test('a stale suspension (long absence) starts fresh', () async {
      await service.load('child-a');
      await service.setSessionLimitMinutes(10);
      await service.startSession();
      await service.addUsage(400);

      final muchLater = DateTime.now().add(const Duration(hours: 3));
      ScreenTimeService.clock = () => muchLater;
      await service.load('child-a');
      await service.startSession();
      expect(
        service.sessionUsedSeconds,
        0,
        reason: 'the child genuinely stopped playing hours ago',
      );
    });

    test('clock set backwards never makes a session stale', () async {
      await service.load('child-a');
      await service.setSessionLimitMinutes(10);
      await service.startSession();
      await service.addUsage(400);

      // Device clock jumps back a day between kill and relaunch.
      final backwards = DateTime.now().subtract(const Duration(days: 1));
      ScreenTimeService.clock = () => backwards;
      await service.load('child-a');
      await service.startSession();
      expect(
        service.sessionUsedSeconds,
        400,
        reason: 'a rewound clock must not grant a fresh session',
      );
    });
  });

  group('child switching', () {
    test(
      'switching children drops the session and never mixes state',
      () async {
        await service.load('child-a');
        await service.setLimitMinutes(30);
        await service.setSessionLimitMinutes(10);
        await service.startSession();
        await service.addUsage(300);

        // Switching pops the lobby (endSession) then reloads for the new
        // child — the same fan-out switchActiveChild performs.
        await service.endSession();
        await service.load('child-b');
        await service.startSession();
        expect(service.sessionUsedSeconds, 0);
        expect(service.usedTodaySeconds, 0);
        expect(service.sessionLimitMinutes, isNull);

        // Coming back restores child A's limits, spent day and a new session.
        await service.endSession();
        await service.load('child-a');
        await service.startSession();
        expect(service.sessionLimitMinutes, 10);
        expect(service.usedTodaySeconds, 300);
        expect(service.sessionUsedSeconds, 0);
      },
    );
  });

  group('ending child mode', () {
    test(
      'endSession zeroes the session and clears its persisted state',
      () async {
        await service.load('child-a');
        await service.setSessionLimitMinutes(10);
        await service.startSession();
        await service.addUsage(300);

        await service.endSession();
        expect(service.sessionActive, isFalse);
        expect(service.sessionUsedSeconds, 0);

        // The cleared state must not resurrect on the next entry.
        await service.load('child-a');
        await service.startSession();
        expect(service.sessionUsedSeconds, 0);
      },
    );
  });

  group('parent-mode time exclusion', () {
    test('usage outside a session never counts toward the session', () async {
      await service.load('child-a');
      await service.setSessionLimitMinutes(10);

      // No session running (parent screens): the ticker does not exist
      // there, but even a stray tick would not touch session usage.
      await service.addUsage(120);
      expect(service.sessionUsedSeconds, 0);

      await service.startSession();
      expect(service.sessionUsedSeconds, 0);
    });
  });

  group('warning and lock thresholds', () {
    test(
      'isNearLimit turns on inside the warning window, off at zero',
      () async {
        await service.load('child-a');
        await service.setSessionLimitMinutes(5); // 300s
        await service.startSession();

        expect(service.isNearLimit, isFalse);
        await service.addUsage(200); // 100s left — inside the 120s window
        expect(service.isNearLimit, isTrue);
        expect(service.isExhausted, isFalse);

        await service.addUsage(100); // 0 left
        expect(service.isNearLimit, isFalse);
        expect(service.isExhausted, isTrue);
      },
    );

    test('parent extension lifts a session lock and remaining is never '
        'negative', () async {
      await service.load('child-a');
      await service.setSessionLimitMinutes(1);
      await service.startSession();

      await service.addUsage(90); // 30s over
      expect(
        service.sessionRemainingSeconds,
        0,
        reason: 'never negative, even when overshot',
      );
      expect(service.isExhausted, isTrue);

      // The lock screen's parent-verified "Add 15 minutes".
      await service.extendToday(15);
      expect(service.isExhausted, isFalse);
      expect(service.sessionRemainingSeconds, 15 * 60 - 30);
    });
  });

  group('midnight rollover', () {
    test(
      'the day resets at midnight but a spanning session does not',
      () async {
        var now = DateTime(2026, 8, 15, 23, 55);
        ScreenTimeService.clock = () => now;

        await service.load('child-a');
        await service.setLimitMinutes(30);
        await service.setSessionLimitMinutes(10);
        await service.startSession();
        await service.addUsage(300);
        expect(service.usedTodaySeconds, 300);

        now = DateTime(2026, 8, 16, 0, 5);
        await service.addUsage(60);
        expect(
          service.usedTodaySeconds,
          60,
          reason: 'a new day starts a fresh daily budget',
        );
        expect(
          service.sessionUsedSeconds,
          360,
          reason: 'one sitting spanning midnight is still one sitting',
        );
      },
    );
  });

  group('no-limit configurations', () {
    test('neither limit set → unlimited play', () async {
      await service.load('child-a');
      await service.startSession();
      await service.addUsage(10000);
      expect(service.activeRemainingSeconds, isNull);
      expect(service.isExhausted, isFalse);
      expect(service.isNearLimit, isFalse);
    });

    test('session limit only (no daily limit) still enforces', () async {
      await service.load('child-a');
      await service.setSessionLimitMinutes(1);
      await service.startSession();
      expect(service.activeRemainingSeconds, 60);
      await service.addUsage(60);
      expect(service.isExhausted, isTrue);
    });
  });
}
