import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Material breakpoint: a device whose smallest screen width is under this
/// many dp is a phone. Mirrors the `sw600dp` resource qualifier Android uses
/// to pick the activity's startup orientation from the manifest, so the Dart
/// policy and the native one always agree.
const double kTabletSmallestWidthDp = 600;

const MethodChannel _channel = MethodChannel('aumazing/device_form_factor');

/// Smallest width of the *physical display*, cached after the first successful
/// platform query. Null until then.
double? _deviceSmallestWidthDp;

/// Resolves the device form factor from the platform and caches it.
///
/// Call once during startup, before the first orientation lock. Android
/// answers from the system configuration, which — unlike anything visible to
/// Dart — is not shrunk when the app is letterboxed, so a tablet that launched
/// inside a portrait strip is still recognised as a tablet.
///
/// Never throws: on platforms without the channel (iOS, tests) the cache stays
/// empty and [deviceSmallestWidthDp] falls back to the display size.
Future<void> initializeDeviceFormFactor() async {
  try {
    final dp = await _channel.invokeMethod<int>('smallestScreenWidthDp');
    if (dp != null && dp > 0) _deviceSmallestWidthDp = dp.toDouble();
  } catch (_) {
    // Channel not available on this platform — the fallback below applies.
  }
}

/// Overrides the resolved device width. Tests only.
@visibleForTesting
void debugSetDeviceSmallestWidthDp(double? dp) {
  _deviceSmallestWidthDp = dp;
}

/// Smallest screen width in dp, from the platform when [initializeDeviceFormFactor]
/// resolved it, otherwise from the display (or, failing that, the window).
double get deviceSmallestWidthDp {
  final cached = _deviceSmallestWidthDp;
  if (cached != null) return cached;

  final view = PlatformDispatcher.instance.implicitView;
  if (view == null) return kTabletSmallestWidthDp;

  // The display covers the whole screen even while the window is letterboxed,
  // so prefer it over the window's own (possibly constrained) size.
  final display = view.display;
  final dpr = display.devicePixelRatio;
  if (dpr > 0 && display.size.shortestSide > 0) {
    return display.size.shortestSide / dpr;
  }
  return view.physicalSize.shortestSide / view.devicePixelRatio;
}

/// True on tablets (smallest width >= 600dp) — the devices that run landscape
/// everywhere, including the parent-facing screens.
bool get isTabletFormFactor => deviceSmallestWidthDp >= kTabletSmallestWidthDp;

/// True on phones, which keep the parent UI in its single-column portrait
/// layout.
bool get isPhoneFormFactor => !isTabletFormFactor;
