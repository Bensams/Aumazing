import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'haptic_config.dart';
import 'web_vibrate.dart';

/// Provides haptic feedback for game events and UI interactions.
///
/// Uses Flutter's built-in [HapticFeedback] API. Only works on physical
/// mobile devices — no effect on desktop or emulators.
class HapticService {
  HapticConfig _config;

  HapticService({HapticConfig? config})
      : _config = config ?? HapticConfig.defaults;

  /// The current haptic configuration.
  HapticConfig get config => _config;

  /// Updates the haptic configuration at runtime.
  void updateConfig(HapticConfig config) {
    _config = config;
  }

  // ── Guard ──────────────────────────────────────────────────────────
  bool get _shouldFire => _config.enabled;

  // ── Platform routers ───────────────────────────────────────────────
  // Flutter's [HapticFeedback] is a no-op on the web, so on web we fall back
  // to the browser Vibration API (Android; a no-op on iOS which has none).
  // Native platforms keep the exact HapticFeedback behaviour they had before.
  void _light() =>
      kIsWeb ? webVibrate(12) : HapticFeedback.lightImpact();
  void _medium() =>
      kIsWeb ? webVibrate(22) : HapticFeedback.mediumImpact();
  void _heavy() =>
      kIsWeb ? webVibrate(35) : HapticFeedback.heavyImpact();
  void _selection() =>
      kIsWeb ? webVibrate(10) : HapticFeedback.selectionClick();
  void _defaultVibrate() =>
      kIsWeb ? webVibrate(40) : HapticFeedback.vibrate();

  // ── Standard Patterns ──────────────────────────────────────────────

  /// Light tap — for UI selections, minor interactions.
  void lightImpact() {
    if (!_shouldFire) return;
    _light();
  }

  /// Medium tap — for confirmations, standard interactions.
  void mediumImpact() {
    if (!_shouldFire) return;
    _medium();
  }

  /// Heavy tap — for important events, errors.
  void heavyImpact() {
    if (!_shouldFire) return;
    _heavy();
  }

  /// Selection click — for picker/selection changes.
  void selectionClick() {
    if (!_shouldFire) return;
    _selection();
  }

  /// Default vibration pattern.
  void vibrate() {
    if (!_shouldFire) return;
    _defaultVibrate();
  }

  // ── Game Event Patterns (named convenience methods) ────────────────

  /// Feedback for tapping a game object.
  void tapFeedback() {
    if (!_shouldFire) return;
    _light();
  }

  /// Feedback for a correct answer/match.
  void correctFeedback() {
    if (!_shouldFire) return;
    _medium();
  }

  /// Feedback for a wrong answer/mismatch.
  void wrongFeedback() {
    if (!_shouldFire) return;
    _heavy();
  }

  /// Feedback for drag start.
  void dragFeedback() {
    if (!_shouldFire) return;
    _selection();
  }

  /// Feedback for drop/place.
  void dropFeedback() {
    if (!_shouldFire) return;
    _medium();
  }

  /// Feedback for completing a round/level.
  void levelCompleteFeedback() {
    if (!_shouldFire) return;
    // Double medium impact
    _medium();
    Future.delayed(const Duration(milliseconds: 100), () {
      _medium();
    });
  }

  /// Feedback for completing the entire game.
  void gameCompleteFeedback() {
    if (!_shouldFire) return;
    // Success pattern: light → medium → heavy ascending
    _light();
    Future.delayed(const Duration(milliseconds: 150), () {
      _medium();
      Future.delayed(const Duration(milliseconds: 150), () {
        _heavy();
      });
    });
  }

  /// Feedback for UI button taps.
  void buttonTapFeedback() {
    if (!_shouldFire) return;
    _light();
  }

  /// Feedback for reward/celebration moments.
  void celebrationFeedback() {
    if (!_shouldFire) return;
    // Triple pulse
    _medium();
    Future.delayed(const Duration(milliseconds: 150), () {
      _medium();
      Future.delayed(const Duration(milliseconds: 150), () {
        _medium();
      });
    });
  }

  // ── Custom Patterns (for tester/advanced use) ──────────────────────

  /// Double tap pattern.
  void doubleTap() {
    if (!_shouldFire) return;
    _light();
    Future.delayed(const Duration(milliseconds: 100), () {
      _light();
    });
  }

  /// Triple pulse pattern.
  void triplePulse() {
    if (!_shouldFire) return;
    _medium();
    Future.delayed(const Duration(milliseconds: 150), () {
      _medium();
      Future.delayed(const Duration(milliseconds: 150), () {
        _medium();
      });
    });
  }

  /// Success ascending pattern (light → medium → heavy).
  void successPattern() {
    if (!_shouldFire) return;
    _light();
    Future.delayed(const Duration(milliseconds: 150), () {
      _medium();
      Future.delayed(const Duration(milliseconds: 150), () {
        _heavy();
      });
    });
  }

  /// Error double-buzz pattern.
  void errorPattern() {
    if (!_shouldFire) return;
    _heavy();
    Future.delayed(const Duration(milliseconds: 200), () {
      _heavy();
    });
  }

  /// Heartbeat pattern (two quick beats, pause, repeat).
  void heartbeatPattern() {
    if (!_shouldFire) return;
    _heavy();
    Future.delayed(const Duration(milliseconds: 120), () {
      _heavy();
      Future.delayed(const Duration(milliseconds: 400), () {
        _heavy();
        Future.delayed(const Duration(milliseconds: 120), () {
          _heavy();
        });
      });
    });
  }
}
