import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

/// Process-wide gate for the developer auto-play hooks.
///
/// The hooks let an automation controller drive a real game by performing the
/// same valid actions a child's taps would — no screen-coordinate simulation,
/// no bypassing of game logic. That is a powerful seam, so it is doubly
/// closed: [enable] only takes effect inside an `assert` (stripped from
/// profile and release builds), and [isEnabled] additionally requires
/// [kDebugMode].
///
/// The host app calls [enable] when, and only when, its developer tools are
/// available. Nothing in this package turns it on by itself.
abstract final class DeveloperAutomation {
  static bool _enabled = false;

  /// Whether automation hooks will do anything at all.
  static bool get isEnabled => kDebugMode && _enabled;

  /// Opens the hooks. A no-op outside debug builds — the body only runs
  /// inside an assert, which release and profile builds drop entirely.
  static void enable() {
    assert(() {
      _enabled = true;
      return true;
    }());
  }

  /// Closes the hooks again.
  static void disable() => _enabled = false;
}

/// The automation surface a game exposes to the developer auto-play
/// controller.
///
/// A game implements the two `…Impl` members in terms of its own state; the
/// public members add the [DeveloperAutomation] gate, so an implementation
/// can never be reached from a build without developer tools. Implementations
/// must perform a *correct* action through the game's own input path, so the
/// resulting score, telemetry and completion callbacks are indistinguishable
/// from genuine play.
mixin DeveloperAutomationHooks on FlameGame {
  /// True when the game is ready to accept a valid action right now.
  ///
  /// False during demos, transitions, animations and buddy turns — the
  /// controller waits rather than forcing input the game would ignore.
  @protected
  bool get debugAwaitingInputImpl;

  /// Performs exactly one valid, correct action through the game's own input
  /// path. Only called when [debugAwaitingInputImpl] is true.
  @protected
  void debugPerformCorrectActionImpl();

  /// Whether a valid action can be performed right now.
  bool get debugIsAwaitingInput =>
      DeveloperAutomation.isEnabled && isMounted && debugAwaitingInputImpl;

  /// Advances the real game by one correct action. Does nothing unless
  /// automation is enabled and the game is actually waiting for input.
  void debugPerformCorrectAction() {
    if (!debugIsAwaitingInput) return;
    debugPerformCorrectActionImpl();
  }
}
