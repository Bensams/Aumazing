import 'web_vibrate_stub.dart'
    if (dart.library.js_interop) 'web_vibrate_web.dart' as impl;

/// Fires a one-shot vibration of [milliseconds] on the web via the Vibration
/// API. No-op on native platforms (they use Flutter's [HapticFeedback]) and on
/// browsers without vibration support (notably iOS Safari).
void webVibrate(int milliseconds) => impl.webVibrate(milliseconds);
