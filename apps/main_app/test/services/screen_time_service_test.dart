import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/services/screen_time_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('recommendedMinutesForAge (AAP/WHO, ASD-adjusted)', () {
    test('follows the age bands, capped at the AAP 1-hour ceiling', () {
      expect(ScreenTimeService.recommendedMinutesForAge(2), 20);
      expect(ScreenTimeService.recommendedMinutesForAge(3), 30);
      expect(ScreenTimeService.recommendedMinutesForAge(4), 30);
      expect(ScreenTimeService.recommendedMinutesForAge(5), 45);
      expect(ScreenTimeService.recommendedMinutesForAge(6), 60);
      expect(ScreenTimeService.recommendedMinutesForAge(9), 60);
    });
  });

  group('daily budget', () {
    test('no limit set → unlimited (never exhausted)', () async {
      final service = ScreenTimeService.instance;
      await service.load('child-a');
      expect(service.limitEnabled, isFalse);
      expect(service.remainingSeconds, isNull);
      expect(service.isExhausted, isFalse);
    });

    test('usage counts down the limit and exhausts at zero', () async {
      final service = ScreenTimeService.instance;
      await service.load('child-a');
      await service.setLimitMinutes(1); // 60 seconds
      expect(service.remainingSeconds, 60);

      // Child play only counts inside an owned child-mode session: the
      // production guard in addUsage rejects usage from parent screens.
      await service.startSession();

      await service.addUsage(45);
      expect(service.remainingSeconds, 15);
      expect(service.isExhausted, isFalse);

      await service.addUsage(30);
      expect(service.remainingSeconds, 0);
      expect(service.isExhausted, isTrue);
    });

    test('parent extension grants extra time for today', () async {
      final service = ScreenTimeService.instance;
      await service.load('child-b');
      await service.setLimitMinutes(1);
      await service.startSession();
      await service.addUsage(60);
      expect(service.isExhausted, isTrue);

      await service.extendToday(15);
      expect(service.isExhausted, isFalse);
      expect(service.remainingSeconds, 15 * 60);
    });

    test('usage persists across a reload and resetToday clears it', () async {
      final service = ScreenTimeService.instance;
      await service.load('child-c');
      await service.setLimitMinutes(30);
      await service.startSession();
      await service.addUsage(120);

      await service.load('child-c'); // simulate re-entering child mode
      expect(service.usedTodaySeconds, 120);

      await service.resetToday();
      expect(service.usedTodaySeconds, 0);
      expect(service.isExhausted, isFalse);
    });

    test('usage is per child', () async {
      final service = ScreenTimeService.instance;
      await service.load('child-d');
      await service.setLimitMinutes(30);
      await service.startSession();
      await service.addUsage(300);
      expect(service.usedTodaySeconds, 300);

      await service.load('child-e');
      expect(service.usedTodaySeconds, 0);
      expect(service.limitEnabled, isFalse);
    });
  });

  // The counters must move only for genuine child play: time spent on parent
  // screens (settings, the dashboard, the lock screen) is not the child's.
  group('parent-mode exclusion (AUM-162)', () {
    test('usage before startSession moves neither counter', () async {
      final service = ScreenTimeService.instance;
      await service.load('child-a');
      await service.setLimitMinutes(10);
      await service.setSessionLimitMinutes(5);

      await service.addUsage(120);

      expect(service.usedTodaySeconds, 0);
      expect(service.sessionUsedSeconds, 0);
    });

    test('usage after endSession moves neither counter', () async {
      final service = ScreenTimeService.instance;
      await service.load('child-a');
      await service.setLimitMinutes(10);
      await service.startSession();
      await service.addUsage(60);
      await service.endSession();

      await service.addUsage(120);

      expect(service.usedTodaySeconds, 60);
      expect(service.sessionUsedSeconds, 0);
    });

    test('usage under a different loaded child is rejected', () async {
      final service = ScreenTimeService.instance;
      await service.load('child-a');
      await service.setLimitMinutes(10);
      await service.startSession();
      await service.addUsage(60);

      // A switch to another child loads them and drops the old session; a
      // late tick from Child A's lobby must not land on Child B.
      await service.load('child-b');
      await service.addUsage(120);

      expect(service.usedTodaySeconds, 0);
      expect(service.sessionUsedSeconds, 0);

      // Child A's own total is untouched by the rejected tick.
      await service.load('child-a');
      expect(service.usedTodaySeconds, 60);
    });

    test('usage after sign-out (no loaded child) is rejected', () async {
      final service = ScreenTimeService.instance;
      await service.load('child-a');
      await service.setLimitMinutes(10);
      await service.startSession();
      await service.addUsage(60);
      await service.endSession();

      await service.addUsage(300);

      await service.load('child-a');
      expect(service.usedTodaySeconds, 60);
    });
  });
}
