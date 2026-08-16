import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import 'package:aumazing/features/child_mode/time_up_dialog.dart';
import 'package:aumazing/services/screen_time_service.dart';

/// Widget-level evidence for the AUM-162 rest screen: that reaching either
/// limit produces a lock the child cannot dismiss, that only a *successful*
/// parent verification opens the parent choices, and that play time does not
/// accrue while the lock is up.
///
/// The real [ParentVerificationDialog] is driven here exactly as a parent
/// drives it — reading the word code off the screen and typing it back on the
/// on-screen numpad — so nothing about production verification is bypassed or
/// weakened for the test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ScreenTimeService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ScreenTimeService.clock = DateTime.now;
    // No PIN configured → the dialog uses its word-code challenge.
    ParentVerificationDialog.pinDelegate = null;
    TimeUpDialog.debugReset();
  });

  tearDown(() async {
    await service.endSession();
    ScreenTimeService.clock = DateTime.now;
    ParentVerificationDialog.pinDelegate = null;
    TimeUpDialog.debugReset();
  });

  const words = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
  ];

  /// Reads the word-code challenge off the screen the way a parent does.
  String shownCode(WidgetTester tester) {
    final shown =
        tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .where((s) => s != null && words.contains(s))
            .map((s) => words.indexOf(s!).toString())
            .toList();
    expect(shown, hasLength(4));
    return shown.join();
  }

  Future<void> tapDigits(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.byKey(ValueKey('numpad_$digit')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('numpad_submit')));
    await tester.pumpAndSettle();
  }

  /// A stand-in for the child-mode lobby: one screen that raises the lock,
  /// with a first route beneath it so "Exit Child Mode" has somewhere to pop
  /// back to (the dashboard, in the real app).
  Future<void> pumpLockedChildMode(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => Builder(
                                  builder:
                                      (lobbyContext) => Scaffold(
                                        body: Center(
                                          child: ElevatedButton(
                                            onPressed:
                                                () => TimeUpDialog.show(
                                                  lobbyContext,
                                                ),
                                            child: const Text('lock'),
                                          ),
                                        ),
                                      ),
                                ),
                          ),
                        ),
                    child: const Text('enter child mode'),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('enter child mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lock'));
    await tester.pumpAndSettle();
  }

  /// Exhausts the given budget so the lock reflects a real enforcement state.
  Future<void> exhaust({required int dailyMinutes, int? sessionMinutes}) async {
    await service.load('child-a');
    await service.setLimitMinutes(dailyMinutes);
    await service.setSessionLimitMinutes(sessionMinutes);
    await service.startSession();
    await service.addUsage((sessionMinutes ?? dailyMinutes) * 60);
  }

  group('rest screen enforcement (AUM-162)', () {
    testWidgets('session exhaustion opens the full-screen rest experience', (
      tester,
    ) async {
      await exhaust(dailyMinutes: 60, sessionMinutes: 5);
      expect(service.isExhausted, isTrue);
      expect(service.isDailyExhausted, isFalse);

      await pumpLockedChildMode(tester);

      expect(TimeUpDialog.isShowing, isTrue);
      // Featureless by design: no message and no child-facing buttons.
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.text('lock'), findsNothing);
    });

    testWidgets('daily exhaustion opens the same rest experience', (
      tester,
    ) async {
      await exhaust(dailyMinutes: 5);
      expect(service.isDailyExhausted, isTrue);

      await pumpLockedChildMode(tester);

      expect(TimeUpDialog.isShowing, isTrue);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });

    testWidgets('ordinary back cannot dismiss the rest screen', (tester) async {
      await exhaust(dailyMinutes: 60, sessionMinutes: 5);
      await pumpLockedChildMode(tester);
      expect(TimeUpDialog.isShowing, isTrue);

      // The system back gesture/button the child would reach for.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(TimeUpDialog.isShowing, isTrue);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });

    testWidgets('usage does not increase while the rest screen is visible', (
      tester,
    ) async {
      await exhaust(dailyMinutes: 60, sessionMinutes: 5);
      await pumpLockedChildMode(tester);
      final usedAtLock = service.usedTodaySeconds;
      final sessionAtLock = service.sessionUsedSeconds;

      // The lobby ticker pauses on this flag; time passing changes nothing.
      expect(TimeUpDialog.isShowing, isTrue);
      await tester.pump(const Duration(seconds: 30));

      expect(service.usedTodaySeconds, usedAtLock);
      expect(service.sessionUsedSeconds, sessionAtLock);
    });
  });

  group('parent verification gates the rest screen (AUM-162)', () {
    testWidgets('a failed verification leaves the screen locked', (
      tester,
    ) async {
      await exhaust(dailyMinutes: 60, sessionMinutes: 5);
      await pumpLockedChildMode(tester);

      await tester.tap(find.byIcon(Icons.lock_rounded));
      await tester.pumpAndSettle();

      // Type a code that is deliberately not the one shown.
      final code = shownCode(tester);
      final wrong =
          code
              .split('')
              .map((d) => ((int.parse(d) + 1) % 10).toString())
              .join();
      await tapDigits(tester, wrong);

      expect(find.text('Incorrect code. Try again.'), findsOneWidget);
      // No parent choices, and the lock is still in place.
      expect(find.text('Add 15 minutes'), findsNothing);
      expect(find.text('Exit Child Mode'), findsNothing);
      expect(TimeUpDialog.isShowing, isTrue);
    });

    testWidgets('a successful verification opens only the parent choices', (
      tester,
    ) async {
      await exhaust(dailyMinutes: 60, sessionMinutes: 5);
      await pumpLockedChildMode(tester);

      await tester.tap(find.byIcon(Icons.lock_rounded));
      await tester.pumpAndSettle();
      await tapDigits(tester, shownCode(tester));

      expect(find.text('Add 15 minutes'), findsOneWidget);
      expect(find.text('Exit Child Mode'), findsOneWidget);
      // The parent-facing line names which limit ran out.
      expect(
        find.text('This play session has reached its limit.'),
        findsOneWidget,
      );
    });

    testWidgets('Add 15 minutes lifts the lock and resumes play', (
      tester,
    ) async {
      await exhaust(dailyMinutes: 60, sessionMinutes: 5);
      await pumpLockedChildMode(tester);
      expect(service.isExhausted, isTrue);

      await tester.tap(find.byIcon(Icons.lock_rounded));
      await tester.pumpAndSettle();
      await tapDigits(tester, shownCode(tester));
      await tester.tap(find.text('Add 15 minutes'));
      await tester.pumpAndSettle();

      // Back in child mode with time on the clock again.
      expect(TimeUpDialog.isShowing, isFalse);
      expect(service.isExhausted, isFalse);
      expect(find.text('lock'), findsOneWidget);
    });

    testWidgets('Exit Child Mode leaves child mode entirely', (tester) async {
      await exhaust(dailyMinutes: 60, sessionMinutes: 5);
      await pumpLockedChildMode(tester);

      await tester.tap(find.byIcon(Icons.lock_rounded));
      await tester.pumpAndSettle();
      await tapDigits(tester, shownCode(tester));
      await tester.tap(find.text('Exit Child Mode'));
      await tester.pumpAndSettle();

      expect(TimeUpDialog.isShowing, isFalse);
      // Popped all the way back to the first route (the dashboard).
      expect(find.text('enter child mode'), findsOneWidget);
      expect(find.text('lock'), findsNothing);
    });
  });
}
