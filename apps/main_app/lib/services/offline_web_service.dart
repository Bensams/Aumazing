/// Offline play for the web build (AUM-334): reports how much of the app the
/// service worker has saved, and asks it to download everything else.
///
/// The browser build talks to `window.aumazingOffline` (web/offline.js); every
/// other platform ships the whole app on the device, so the stub reports the
/// feature as unsupported.
library;

export 'offline_web_service_stub.dart'
    if (dart.library.js_interop) 'offline_web_service_web.dart';
export 'offline_status.dart';
