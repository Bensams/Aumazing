/// Rewrites the address shown in the browser without reloading the page —
/// used to drop one-off query parameters (such as `?payment=success`) once the
/// app has read them. A no-op on Android and iOS.
library;

export 'browser_url_stub.dart'
    if (dart.library.js_interop) 'browser_url_web.dart';
