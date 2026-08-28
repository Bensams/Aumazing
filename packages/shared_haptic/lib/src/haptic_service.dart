import 'package:flutter/services.dart';
import 'haptic_config.dart';

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

  // ── Standard Patterns ──────────────────────────────────────────────

  /// Light tap — for UI selections, minor interactions.
  void lightImpact() {
    if (!_shouldFire) return;
    HapticFeedback.lightImpact();
  }

  /// Medium tap — for confirmations, standard interactions.
  void mediumImpact() {
    if (!_shouldFire) return;
    HapticFeedback.mediumImpact();
  }

  /// Heavy tap — for important events, errors.
  void heavyImpact() {
    if (!_shouldFire) return;
    HapticFeedback.heavyImpact();
  }

  /// Selection click — for picker/selection changes.
  void selectionClick() {
    if (!_shouldFire) return;
    HapticFeedback.selectionClick();
  }

  /// Default vibration pattern.
  void vibrate() {
    if (!_shouldFire) return;
    HapticFeedback.vibrate();
  }

  // ── Game Event Patterns (named convenience methods) ────────────────

  /// Feedback for tapping a game object.
  void tapFeedback() {
    if (!_shouldFire) return;
    HapticFeedback.lightImpact();
  }

  /// Feedback for a correct answer/match.
  void correctFeedback() {
    if (!_shouldFire) return;
    HapticFeedback.mediumImpact();
  }

  /// Feedback for a wrong answer/mismatch.
  void wrongFeedback() {
    if (!_shouldFire) return;
    HapticFeedback.heavyImpact();
  }

  /// Feedback for drag start.
  void dragFeedback() {
    if (!_shouldFire) return;
    HapticFeedback.selectionClick();
  }

  /// Feedback for drop/place.
  void dropFeedback() {
    if (!_shouldFire) return;
    HapticFeedback.mediumImpact();
  }

  /// Feedback for completing a round/level.
  void levelCompleteFeedback() {
    if (!_shouldFire) return;
    // Double medium impact
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.mediumImpact();
    });
  }

  /// Feedback for completing the entire game.
  void gameCompleteFeedback() {
    if (!_shouldFire) return;
    // Success pattern: light → medium → heavy ascending
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 150), () {
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 150), () {
        HapticFeedback.heavyImpact();
      });
    });
  }

  /// Feedback for UI button taps.
  void buttonTapFeedback() {
    if (!_shouldFire) return;
    HapticFeedback.lightImpact();
  }

  /// Feedback for reward/celebration moments.
  void celebrationFeedback() {
    if (!_shouldFire) return;
    // Triple pulse
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 150), () {
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 150), () {
        HapticFeedback.mediumImpact();
      });
    });
  }

  // ── Custom Patterns (for tester/advanced use) ──────────────────────

  /// Double tap pattern.
  void doubleTap() {
    if (!_shouldFire) return;
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.lightImpact();
    });
  }

  /// Triple pulse pattern.
  void triplePulse() {
    if (!_shouldFire) return;
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 150), () {
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 150), () {
        HapticFeedback.mediumImpact();
      });
    });
  }

  /// Success ascending pattern (light → medium → heavy).
  void successPattern() {
    if (!_shouldFire) return;
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 150), () {
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 150), () {
        HapticFeedback.heavyImpact();
      });
    });
  }

  /// Error double-buzz pattern.
  void errorPattern() {
    if (!_shouldFire) return;
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 200), () {
      HapticFeedback.heavyImpact();
    });
  }

  /// Heartbeat pattern (two quick beats, pause, repeat).
  void heartbeatPattern() {
    if (!_shouldFire) return;
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 120), () {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 400), () {
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 120), () {
          HapticFeedback.heavyImpact();
        });
      });
    });
  }
}
