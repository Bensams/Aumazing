import 'package:flutter/foundation.dart';

/// Whether the optional developer testing toolbox is compiled in.
///
/// Two independent gates, both of which must hold:
///
///  * [enabled] — a compile-time define, `false` unless the build explicitly
///    passes `--dart-define=ENABLE_DEVELOPER_TOOLS=true`. Because it is a
///    `const`, a build without the define tree-shakes the toolbox away.
///  * [kDebugMode] — so a define accidentally left in a profile or release
///    build still cannot surface developer shortcuts to a real family.
///
/// Every entry point into the toolbox (the overlay, the Premium override,
/// the assessment shortcuts) checks [isAvailable] rather than [enabled], so
/// there is exactly one place that decides whether the feature exists.
class DeveloperToolsConfig {
  const DeveloperToolsConfig._();

  /// The compile-time define. Default `false` — production builds never
  /// pass it.
  static const bool enabled = bool.fromEnvironment(
    'ENABLE_DEVELOPER_TOOLS',
    defaultValue: false,
  );

  /// Test seam. Only ever read inside an `assert`, so it is stripped from
  /// profile and release builds — a test can pretend the toolbox is on (or
  /// off), a shipped binary cannot.
  static bool? _debugAvailableOverride;

  /// Forces [isAvailable] for the duration of a test. Pass null to restore.
  @visibleForTesting
  static set debugAvailableOverride(bool? value) {
    _debugAvailableOverride = value;
  }

  @visibleForTesting
  static bool? get debugAvailableOverride => _debugAvailableOverride;

  /// Whether the developer toolbox may be shown and used at all.
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
