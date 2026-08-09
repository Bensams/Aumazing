import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/services/parent_pin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = ParentPinService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.resetForTest();
  });

  group('recommendsCustomPin', () {
    test('kicks in at the age most children can read the word code', () {
      expect(ParentPinService.recommendsCustomPin(4), isFalse);
      expect(ParentPinService.recommendsCustomPin(5), isFalse);
      expect(ParentPinService.recommendsCustomPin(6), isTrue);
      expect(ParentPinService.recommendsCustomPin(9), isTrue);
    });
  });

  group('validatePin', () {
    test('accepts an ordinary four-digit PIN', () {
      expect(ParentPinService.validatePin('4907'), isNull);
      expect(ParentPinService.validatePin('1357'), isNull);
    });

    test('rejects wrong length and non-digits', () {
      expect(ParentPinService.validatePin('123'), isNotNull);
      expect(ParentPinService.validatePin('12345'), isNotNull);
      expect(ParentPinService.validatePin('12a4'), isNotNull);
    });

    test('rejects the PINs a child tries first', () {
      expect(ParentPinService.validatePin('0000'), isNotNull);
      expect(ParentPinService.validatePin('1111'), isNotNull);
      expect(ParentPinService.validatePin('1234'), isNotNull);
      expect(ParentPinService.validatePin('9876'), isNotNull);
    });
  });

  group('mode', () {
    test('defaults to the word code with no PIN set', () async {
      await service.load('account-a');
      expect(service.mode, ParentLockMode.wordCode);
      expect(service.hasPin, isFalse);
    });

    test('setPin switches to custom-PIN mode and survives a reload',
        () async {
      await service.load('account-a');
      await service.setPin('4907');
      expect(service.hasPin, isTrue);
      expect(service.mode, ParentLockMode.customPin);

      await service.load('account-a');
      expect(service.hasPin, isTrue);
      expect((await service.verify('4907')).isCorrect, isTrue);
    });

    test('clearPin returns to the word code', () async {
      await service.load('account-a');
      await service.setPin('4907');
      await service.clearPin();
      expect(service.hasPin, isFalse);
      expect(service.mode, ParentLockMode.wordCode);
    });

    test('signing out drops the PIN so a guest gets the word code', () async {
      await service.load('account-a');
      await service.setPin('4907');

      await service.load(null);
      expect(service.hasPin, isFalse);
      expect(service.mode, ParentLockMode.wordCode);
    });

    test("one account's PIN does not unlock another's", () async {
      await service.load('account-a');
      await service.setPin('4907');

      await service.load('account-b');
      expect(service.hasPin, isFalse);
    });
  });

  group('verify', () {
    test('correct PIN passes, wrong PIN fails', () async {
      await service.load('account-a');
      await service.setPin('4907');

      expect((await service.verify('4907')).isCorrect, isTrue);
      expect((await service.verify('4906')).isCorrect, isFalse);
    });

    test('the PIN is never stored in recoverable form', () async {
      await service.load('account-a');
      await service.setPin('4907');

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getKeys().map(prefs.get).join('|');
      expect(stored.contains('4907'), isFalse);
    });

    test('each PIN gets a distinct salt, so equal PINs hash differently',
        () async {
      await service.load('account-a');
      await service.setPin('4907');
      final prefsA = await SharedPreferences.getInstance();
      final hashA = prefsA.getString('parent_pin_hash_account-a');

      await service.load('account-b');
      await service.setPin('4907');
      final hashB = prefsA.getString('parent_pin_hash_account-b');

      expect(hashA, isNotNull);
      expect(hashB, isNotNull);
      expect(hashA, isNot(hashB));
    });
  });

  group('brute-force throttle', () {
    test('locks out after 5 wrong tries and counts them down', () async {
      await service.load('account-a');
      await service.setPin('4907');

      for (var i = 1; i < ParentPinService.maxAttempts; i++) {
        final result = await service.verify('0001');
        expect(result.status, PinVerifyStatus.incorrect);
        expect(result.attemptsRemaining, ParentPinService.maxAttempts - i);
      }

      final locked = await service.verify('0001');
      expect(locked.status, PinVerifyStatus.lockedOut);
      expect(locked.lockout, ParentPinService.lockoutDuration);
      expect(service.isLockedOut, isTrue);
    });

    test('the correct PIN is refused while the cooldown runs', () async {
      await service.load('account-a');
      await service.setPin('4907');

      for (var i = 0; i < ParentPinService.maxAttempts; i++) {
        await service.verify('0001');
      }

      final result = await service.verify('4907');
      expect(result.status, PinVerifyStatus.lockedOut);
    });

    test('the cooldown survives a restart', () async {
      await service.load('account-a');
      await service.setPin('4907');
      for (var i = 0; i < ParentPinService.maxAttempts; i++) {
        await service.verify('0001');
      }

      // Force-quitting the app must not hand back a fresh set of tries.
      await service.load('account-a');
      expect(service.isLockedOut, isTrue);
      expect((await service.verify('4907')).status, PinVerifyStatus.lockedOut);
    });

    test('a correct PIN resets the attempt counter', () async {
      await service.load('account-a');
      await service.setPin('4907');

      await service.verify('0001');
      await service.verify('0002');
      expect(service.failedAttempts, 2);

      await service.verify('4907');
      expect(service.failedAttempts, 0);
    });

    test('clearThrottle lifts the cooldown after an emailed reset', () async {
      await service.load('account-a');
      await service.setPin('4907');
      for (var i = 0; i < ParentPinService.maxAttempts; i++) {
        await service.verify('0001');
      }
      expect(service.isLockedOut, isTrue);

      await service.clearThrottle();
      expect(service.isLockedOut, isFalse);
      expect((await service.verify('4907')).isCorrect, isTrue);
    });

    test('a backwards clock cannot strand the parent past the cooldown',
        () async {
      // Simulates a device clock moved far forward and then back: the stored
      // expiry is in the distant future, but the wait is capped.
      final farFuture = DateTime.now()
          .add(const Duration(days: 30))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'parent_pin_lockout_account-a': farFuture,
      });

      await service.load('account-a');
      expect(service.lockoutRemaining, ParentPinService.lockoutDuration);
    });

    test('setting a new PIN clears any running cooldown', () async {
      await service.load('account-a');
      await service.setPin('4907');
      for (var i = 0; i < ParentPinService.maxAttempts; i++) {
        await service.verify('0001');
      }
      expect(service.isLockedOut, isTrue);

      await service.setPin('5813');
      expect(service.isLockedOut, isFalse);
      expect((await service.verify('5813')).isCorrect, isTrue);
    });
  });
}
