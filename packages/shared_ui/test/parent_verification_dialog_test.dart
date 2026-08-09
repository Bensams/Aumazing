import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_ui/shared_ui.dart';

/// Scriptable stand-in for the app's real PIN service.
class _FakePinDelegate implements ParentPinDelegate {
  _FakePinDelegate({
    this.hasPin = true,
    this.correctPin = '4907',
    this.lockoutRemaining,
    this.forgotResult = false,
  });

  @override
  bool hasPin;

  String correctPin;

  @override
  Duration? lockoutRemaining;

  bool forgotResult;
  int forgotCalls = 0;
  final List<String> attempted = [];

  /// When set, the next [verify] returns this instead of comparing.
  ParentPinAttempt? nextOutcome;

  @override
  Future<ParentPinAttempt> verify(String pin) async {
    attempted.add(pin);
    final forced = nextOutcome;
    if (forced != null) {
      nextOutcome = null;
      return forced;
    }
    return pin == correctPin
        ? ParentPinAttempt.correct
        : ParentPinAttempt.incorrect;
  }

  @override
  Future<bool> onForgotPin(BuildContext context) async {
    forgotCalls++;
    return forgotResult;
  }
}

void main() {
  tearDown(() => ParentVerificationDialog.pinDelegate = null);

  /// Pumps a host that opens the dialog and records its result.
  Future<List<bool?>> openDialog(WidgetTester tester) async {
    final results = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                results.add(await ParentVerificationDialog.show(context));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> tapDigits(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.byKey(ValueKey('numpad_$digit')));
      await tester.pump();
    }
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('numpad_submit')));
    await tester.pumpAndSettle();
  }

  const words = [
    'zero', 'one', 'two', 'three', 'four',
    'five', 'six', 'seven', 'eight', 'nine',
  ];

  /// Reads the word-code challenge off the screen the way a parent does.
  String shownCode(WidgetTester tester) {
    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((s) => s != null && words.contains(s))
        .map((s) => words.indexOf(s!).toString())
        .toList();
    expect(shown, hasLength(4));
    return shown.join();
  }

  group('word-code mode (no delegate)', () {
    testWidgets('shows the code as words and accepts it typed back',
        (tester) async {
      final results = await openDialog(tester);

      expect(find.text('Enter the code shown below:'), findsOneWidget);
      expect(find.text('Forgot PIN?'), findsNothing);

      await tapDigits(tester, shownCode(tester));
      await submit(tester);

      expect(results.single, isTrue);
    });

    testWidgets('rejects a wrong code and clears the entry', (tester) async {
      final results = await openDialog(tester);

      // Bump the last digit of the real code so the attempt is wrong on
      // every run, whatever the dialog randomised.
      final code = shownCode(tester);
      final wrong = code.substring(0, 3) +
          ((int.parse(code[3]) + 1) % 10).toString();

      await tapDigits(tester, wrong);
      await submit(tester);

      expect(find.text('Incorrect code. Try again.'), findsOneWidget);
      expect(results, isEmpty);

      // Entry is cleared, so the next attempt starts from scratch.
      await tapDigits(tester, code);
      await submit(tester);
      expect(results.single, isTrue);
    });
  });

  group('custom-PIN mode', () {
    testWidgets('never renders the PIN or the word code', (tester) async {
      ParentVerificationDialog.pinDelegate = _FakePinDelegate();
      await openDialog(tester);

      expect(find.text('Enter your parent PIN:'), findsOneWidget);
      // No number words on screen — that is the whole point of PIN mode.
      for (final word in ['zero', 'one', 'seven', 'nine']) {
        expect(find.text(word), findsNothing);
      }

      await tapDigits(tester, '49');
      // Entered digits are masked, not echoed back.
      expect(find.text('4'), findsOneWidget); // the numpad key only
      expect(find.text('9'), findsOneWidget);
    });

    testWidgets('correct PIN closes the dialog as verified', (tester) async {
      final delegate = _FakePinDelegate(correctPin: '4907');
      ParentVerificationDialog.pinDelegate = delegate;
      final results = await openDialog(tester);

      await tapDigits(tester, '4907');
      await submit(tester);

      expect(delegate.attempted, ['4907']);
      expect(results.single, isTrue);
    });

    testWidgets('wrong PIN shows an error and stays open', (tester) async {
      ParentVerificationDialog.pinDelegate =
          _FakePinDelegate(correctPin: '4907');
      final results = await openDialog(tester);

      await tapDigits(tester, '0001');
      await submit(tester);

      expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('lockout disables the keypad and counts down', (tester) async {
      final delegate = _FakePinDelegate(correctPin: '4907')
        ..nextOutcome = ParentPinAttempt.lockedOut
        ..lockoutRemaining = const Duration(seconds: 60);
      ParentVerificationDialog.pinDelegate = delegate;
      await openDialog(tester);

      await tapDigits(tester, '0001');
      await submit(tester);

      expect(find.text('Too many tries. Try again in 60s.'), findsOneWidget);

      // Keypad is inert while the cooldown runs.
      delegate.attempted.clear();
      await tapDigits(tester, '4907');
      await submit(tester);
      expect(delegate.attempted, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Too many tries. Try again in 59s.'), findsOneWidget);

      // Let the timer finish so the test does not leave it pending.
      await tester.pump(const Duration(seconds: 59));
      await tester.pumpAndSettle();
    });

    testWidgets('an in-progress cooldown is honoured when the dialog opens',
        (tester) async {
      ParentVerificationDialog.pinDelegate = _FakePinDelegate(
        lockoutRemaining: const Duration(seconds: 30),
      );
      await openDialog(tester);

      expect(find.text('Too many tries. Try again in 30s.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
    });

    testWidgets('a successful reset opens the gate', (tester) async {
      final delegate = _FakePinDelegate(forgotResult: true);
      ParentVerificationDialog.pinDelegate = delegate;
      final results = await openDialog(tester);

      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();

      expect(delegate.forgotCalls, 1);
      expect(results.single, isTrue);
    });

    testWidgets('an abandoned reset leaves the dialog open', (tester) async {
      ParentVerificationDialog.pinDelegate =
          _FakePinDelegate(forgotResult: false);
      final results = await openDialog(tester);

      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your parent PIN:'), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('a delegate without a PIN falls back to the word code',
        (tester) async {
      ParentVerificationDialog.pinDelegate = _FakePinDelegate(hasPin: false);
      await openDialog(tester);

      expect(find.text('Enter the code shown below:'), findsOneWidget);
      expect(find.text('Forgot PIN?'), findsNothing);
    });
  });
}
