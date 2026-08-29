import 'package:flutter/foundation.dart';

/// Whether the simulated PayMongo checkout is compiled in (AUM-331).
///
/// A demo or test build can walk the whole Premium purchase flow — choose a
/// method, pay, see the features unlock — without contacting PayMongo at all.
/// Nothing is charged because nothing is sent.
///
/// Two independent gates, both of which must hold, mirroring
/// [DeveloperToolsConfig]:
///
///  * [enabled] — a compile-time define, `false` unless the build explicitly
///    passes `--dart-define=MOCK_PAYMONGO=true`. Being `const`, a build
///    without the define tree-shakes the simulation away entirely.
///  * [kDebugMode] — so a define accidentally left in a profile or release
///    build still cannot put a fake checkout in front of a paying parent.
///
/// The second gate is the important one. A simulated checkout that could
/// reach a real family would be worse than no simulation: it would take an
/// intent to pay and answer it with a lie.
///
/// Kept separate from the developer toolbox rather than folded into it: a
/// demo build wants the payment flow, not the assessment shortcuts and the
/// floating DEV overlay, and coupling them would force one to carry the other.
class PaymentSimulationConfig {
  const PaymentSimulationConfig._();

  /// The compile-time define. Default `false` — production builds never
  /// pass it.
  static const bool enabled = bool.fromEnvironment(
    'MOCK_PAYMONGO',
    defaultValue: false,
  );

  /// Test seam. Only ever read inside an `assert`, so it is stripped from
  /// profile and release builds — a test can pretend the simulation is on,
  /// a shipped binary cannot.
  static bool? _debugAvailableOverride;

  /// Forces [isAvailable] for the duration of a test. Pass null to restore.
  @visibleForTesting
  static set debugAvailableOverride(bool? value) {
    _debugAvailableOverride = value;
  }

  @visibleForTesting
  static bool? get debugAvailableOverride => _debugAvailableOverride;

  /// Whether the simulated checkout may be shown and used at all.
  ///
  /// Every entry point checks this rather than [enabled], so there is exactly
  /// one place that decides whether the simulation exists.
  static bool get isAvailable {
    var available = kDebugMode && enabled;
    assert(() {
      final override = _debugAvailableOverride;
      if (override != null) available = override;
      return true;
    }());
    return available;
  }
}
