import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/protected_storage.dart';

/// How the parent lock challenges whoever is trying to leave child mode.
enum ParentLockMode {
  /// A freshly randomised 4-digit code, shown on screen as English words
  /// ("seven three zero nine"). Defeated by any child who can read.
  wordCode,

  /// A 4-digit PIN the parent chose. Nothing on screen reveals it.
  customPin,
}

/// Outcome of a single [ParentPinService.verify] call.
enum PinVerifyStatus { correct, incorrect, lockedOut }

/// Result of a PIN attempt, including how many tries remain before the
/// cooldown kicks in.
class PinVerifyResult {
  const PinVerifyResult(this.status, {this.attemptsRemaining, this.lockout});

  final PinVerifyStatus status;

  /// Tries left before a cooldown starts. Null when locked out or correct.
  final int? attemptsRemaining;

  /// How long the caller must wait. Non-null only for [PinVerifyStatus.lockedOut].
  final Duration? lockout;

  bool get isCorrect => status == PinVerifyStatus.correct;
}

/// The parent lock: mode selection, PIN storage, and brute-force throttling.
///
/// The PIN is never stored in a recoverable form and is never transmitted —
/// only a salted PBKDF2-HMAC-SHA256 digest is written to disk. A forgotten
/// PIN is therefore *reset* (via an emailed one-time code) rather than
/// retrieved, so a lost PIN can never leak from storage, logs, or an inbox.
///
/// Note that at four digits the keyspace is only 10,000, so the digest alone
/// would fall in milliseconds to anyone who could read it off the device.
/// The real defence is [maxAttempts]/[lockoutDuration] throttling on the
/// entry path; the hashing exists so the PIN is not sitting in plaintext in
/// a preferences file or a backup.
///
/// All state is device-local and namespaced by account ID, so signing out
/// and handing the tablet to a guest falls back to [ParentLockMode.wordCode]
/// rather than exposing the previous parent's lock.
class ParentPinService extends ChangeNotifier {
  ParentPinService._();

  static final ParentPinService instance = ParentPinService._();

  /// Wrong tries allowed before the cooldown starts.
  static const int maxAttempts = 5;

  /// How long entry stays disabled after [maxAttempts] wrong tries.
  static const Duration lockoutDuration = Duration(seconds: 60);

  /// PIN length. Matches the word-code challenge so the numpad is unchanged.
  static const int pinLength = 4;

  /// PBKDF2 rounds. Enough to cost real time on a brute-force sweep while
  /// staying imperceptible (single-digit ms) on a low-end tablet.
  static const int _iterations = 10000;

  /// Age at (and above) which we recommend a custom PIN: by six most
  /// children can read the number words in the word-code challenge, which
  /// makes that gate decorative. This is a recommendation only — the parent
  /// decides, since reading ability varies widely among ASD learners.
  static const int recommendedPinAge = 6;

  String? _accountId;
  bool _bound = false;
  ParentLockMode _mode = ParentLockMode.wordCode;
  String? _salt;
  String? _hash;
  final ProtectedStorage _protectedStorage = ProtectedStorage();
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  static String _modeKey(String id) => 'parent_lock_mode_$id';
  static String _saltKey(String id) => 'parent_pin_salt_$id';
  static String _hashKey(String id) => 'parent_pin_hash_$id';
  static String _attemptsKey(String id) => 'parent_pin_attempts_$id';
  static String _lockoutKey(String id) => 'parent_pin_lockout_$id';

  // ── Recommendation ──────────────────────────────────────────────────────

  /// True when a child of [ageYears] is old enough that the word-code
  /// challenge is likely readable to them.
  static bool recommendsCustomPin(int ageYears) =>
      ageYears >= recommendedPinAge;

  /// Rejects PINs that are trivially guessable. Returns an error message to
  /// show the parent, or null when the PIN is acceptable.
  static String? validatePin(String pin) {
    if (pin.length != pinLength) {
      return 'Your PIN must be $pinLength digits.';
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return 'Your PIN must be digits only.';
    }
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) {
      return 'Avoid repeating the same digit — try a less obvious PIN.';
    }
    final digits = pin.split('').map(int.parse).toList();
    final ascending = List.generate(
      pinLength - 1,
      (i) => digits[i + 1] - digits[i] == 1,
    ).every((step) => step);
    final descending = List.generate(
      pinLength - 1,
      (i) => digits[i] - digits[i + 1] == 1,
    ).every((step) => step);
    if (ascending || descending) {
      return 'Avoid sequences like 1234 — try a less obvious PIN.';
    }
    return null;
  }

  // ── Loading ─────────────────────────────────────────────────────────────

  /// Call once after `Supabase.initialize`: loads the current account's lock
  /// state and reloads whenever the signed-in user changes (login, logout,
  /// guest upgrade).
  ///
  /// Reloading on sign-out matters: it drops the previous parent's PIN from
  /// memory so handing the tablet to a guest falls back to the word code
  /// rather than presenting a lock nobody present can open.
  void init() {
    if (_bound) return;
    _bound = true;
    Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => load(Supabase.instance.client.auth.currentUser?.id),
    );
    load(Supabase.instance.client.auth.currentUser?.id);
  }

  /// Loads lock state for [accountId] (the Supabase user ID). Pass null when
  /// signed out — the lock falls back to the word code.
  ///
  /// Call on app start and whenever the signed-in account changes.
  Future<void> load(String? accountId) async {
    _accountId = accountId;
    _mode = ParentLockMode.wordCode;
    _salt = null;
    _hash = null;
    _failedAttempts = 0;
    _lockoutUntil = null;

    if (accountId != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final storedMode = prefs.getString(_modeKey(accountId));
        _salt = await _protectedStorage.read(
          _saltKey(accountId),
          legacyKey: _saltKey(accountId),
        );
        _hash = await _protectedStorage.read(
          _hashKey(accountId),
          legacyKey: _hashKey(accountId),
        );
        _failedAttempts = prefs.getInt(_attemptsKey(accountId)) ?? 0;
        final lockoutMs = prefs.getInt(_lockoutKey(accountId));
        _lockoutUntil = lockoutMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lockoutMs);
        // Only honour custom-PIN mode when a PIN actually exists, so a
        // half-finished setup can never lock the parent out.
        if (storedMode == ParentLockMode.customPin.name &&
            _salt != null &&
            _hash != null) {
          _mode = ParentLockMode.customPin;
        }
      } catch (e) {
        debugPrint('[ParentPin] load failed: $e');
      }
    }
    notifyListeners();
  }

  // ── State ───────────────────────────────────────────────────────────────

  /// The active challenge type.
  ParentLockMode get mode => _mode;

  /// True when a custom PIN is set and in use.
  bool get hasPin =>
      _mode == ParentLockMode.customPin && _salt != null && _hash != null;

  /// Wrong attempts recorded since the last success or cooldown.
  int get failedAttempts => _failedAttempts;

  /// Time left on the cooldown, or null when entry is allowed.
  ///
  /// Clamped to [lockoutDuration] so that moving the device clock backwards
  /// cannot strand a parent behind an unreachable expiry.
  Duration? get lockoutRemaining {
    final until = _lockoutUntil;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    if (left <= Duration.zero) return null;
    return left > lockoutDuration ? lockoutDuration : left;
  }

  /// True while the cooldown is running.
  bool get isLockedOut => lockoutRemaining != null;

  // ── Mutations ───────────────────────────────────────────────────────────

  /// Stores [pin] and switches the lock to [ParentLockMode.customPin].
  ///
  /// Callers must confirm the account has a verified email first — that is
  /// the only route back in after a forgotten PIN.
  Future<void> setPin(String pin) async {
    final accountId = _accountId;
    if (accountId == null) return;

    final salt = _generateSalt();
    final hash = _derive(pin, salt);

    _salt = salt;
    _hash = hash;
    _mode = ParentLockMode.customPin;
    _failedAttempts = 0;
    _lockoutUntil = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _protectedStorage.write(_saltKey(accountId), salt);
      await _protectedStorage.write(_hashKey(accountId), hash);
      await prefs.setString(_modeKey(accountId), ParentLockMode.customPin.name);
      await prefs.remove(_attemptsKey(accountId));
      await prefs.remove(_lockoutKey(accountId));
    } catch (e) {
      debugPrint('[ParentPin] setPin failed: $e');
    }
  }

  /// Removes the PIN and returns the lock to the word-code challenge.
  Future<void> clearPin() async {
    final accountId = _accountId;
    if (accountId == null) return;

    _salt = null;
    _hash = null;
    _mode = ParentLockMode.wordCode;
    _failedAttempts = 0;
    _lockoutUntil = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await _protectedStorage.delete(_saltKey(accountId));
      await _protectedStorage.delete(_hashKey(accountId));
      await prefs.remove(_attemptsKey(accountId));
      await prefs.remove(_lockoutKey(accountId));
      await prefs.setString(_modeKey(accountId), ParentLockMode.wordCode.name);
    } catch (e) {
      debugPrint('[ParentPin] clearPin failed: $e');
    }
  }

  /// Checks [pin], applying and advancing the brute-force throttle.
  ///
  /// After [maxAttempts] wrong tries entry is refused for [lockoutDuration];
  /// once that elapses the counter resets and the parent gets a fresh set of
  /// tries. Both counters are persisted, so force-quitting the app does not
  /// clear a cooldown.
  Future<PinVerifyResult> verify(String pin) async {
    final remaining = lockoutRemaining;
    if (remaining != null) {
      return PinVerifyResult(PinVerifyStatus.lockedOut, lockout: remaining);
    }

    final salt = _salt;
    final hash = _hash;
    if (salt == null || hash == null) {
      return const PinVerifyResult(PinVerifyStatus.incorrect);
    }

    if (_constantTimeEquals(_derive(pin, salt), hash)) {
      await _resetThrottle();
      return const PinVerifyResult(PinVerifyStatus.correct);
    }

    _failedAttempts++;
    if (_failedAttempts >= maxAttempts) {
      _failedAttempts = 0;
      _lockoutUntil = DateTime.now().add(lockoutDuration);
      await _persistThrottle();
      notifyListeners();
      return const PinVerifyResult(
        PinVerifyStatus.lockedOut,
        lockout: lockoutDuration,
      );
    }

    await _persistThrottle();
    notifyListeners();
    return PinVerifyResult(
      PinVerifyStatus.incorrect,
      attemptsRemaining: maxAttempts - _failedAttempts,
    );
  }

  /// Clears the cooldown. Called after an emailed reset code is verified, so
  /// a parent who just proved they own the account is not made to wait.
  Future<void> clearThrottle() => _resetThrottle();

  Future<void> _resetThrottle() async {
    _failedAttempts = 0;
    _lockoutUntil = null;
    notifyListeners();
    final accountId = _accountId;
    if (accountId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_attemptsKey(accountId));
      await prefs.remove(_lockoutKey(accountId));
    } catch (e) {
      debugPrint('[ParentPin] throttle reset failed: $e');
    }
  }

  Future<void> _persistThrottle() async {
    final accountId = _accountId;
    if (accountId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_attemptsKey(accountId), _failedAttempts);
      final until = _lockoutUntil;
      if (until == null) {
        await prefs.remove(_lockoutKey(accountId));
      } else {
        await prefs.setInt(
          _lockoutKey(accountId),
          until.millisecondsSinceEpoch,
        );
      }
    } catch (e) {
      debugPrint('[ParentPin] throttle persist failed: $e');
    }
  }

  // ── Hashing ─────────────────────────────────────────────────────────────

  static String _generateSalt() {
    final rng = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => rng.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256, one 32-byte block ([_iterations] rounds).
  static String _derive(String pin, String salt) {
    final saltBytes = base64Decode(salt);
    final hmac = Hmac(sha256, utf8.encode(pin));
    // INT(1) block index, per RFC 8018.
    var u = hmac.convert([...saltBytes, 0, 0, 0, 1]).bytes;
    final out = List<int>.from(u);
    for (var i = 1; i < _iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return base64Encode(out);
  }

  /// Compares digests without an early exit, so timing cannot leak a prefix.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Test seam: drops in-memory state without touching storage.
  @visibleForTesting
  void resetForTest() {
    _accountId = null;
    _mode = ParentLockMode.wordCode;
    _salt = null;
    _hash = null;
    _failedAttempts = 0;
    _lockoutUntil = null;
  }
}
