import 'dart:js_interop';

@JS('navigator.vibrate')
external JSBoolean _navigatorVibrate(JSAny pattern);

/// Vibrates via the browser Vibration API. Works on Android Chrome; on browsers
/// without support (iOS Safari) `navigator.vibrate` is undefined and the call
/// throws, which we swallow so haptics degrade to a silent no-op.
void webVibrate(int milliseconds) {
  try {
    _navigatorVibrate(milliseconds.toJS);
  } catch (_) {
    // Vibration API unavailable (e.g. iOS) — silently ignore.
  }
}
