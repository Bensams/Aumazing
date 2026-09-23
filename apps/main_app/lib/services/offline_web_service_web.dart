import 'dart:js_interop';

import 'offline_status.dart';

// ── JS bridge (see web/offline.js) ──────────────────────────────────────────
/// Null when the browser has no service workers, or offline.js did not load.
@JS('aumazingOffline')
external _OfflineApi? get _api;

extension type _OfflineApi(JSObject _) implements JSObject {
  external JSPromise<_Status> status();
  external JSPromise<_Status> downloadAll(JSFunction onProgress);
}

extension type _Status(JSObject _) implements JSObject {
  external JSNumber get coreCached;
  external JSNumber get coreTotal;
  external JSNumber get lazyCached;
  external JSNumber get lazyTotal;
}

extension type _Progress(JSObject _) implements JSObject {
  external JSNumber get done;
  external JSNumber get total;
}

OfflineStatus _toStatus(_Status s) => OfflineStatus(
  coreCached: s.coreCached.toDartInt,
  coreTotal: s.coreTotal.toDartInt,
  lazyCached: s.lazyCached.toDartInt,
  lazyTotal: s.lazyTotal.toDartInt,
);

/// Browser build: asks the offline service worker through web/offline.js.
/// Every call resolves to null rather than throwing when the worker is not
/// running (e.g. a build that skipped tool/build_offline_web.dart).
class OfflineWebService {
  const OfflineWebService();

  bool get isSupported => _api != null;

  Future<OfflineStatus?> status() async {
    final api = _api;
    if (api == null) return null;
    try {
      return _toStatus(await api.status().toDart);
    } catch (_) {
      return null;
    }
  }

  Future<OfflineStatus?> downloadAll({
    void Function(int done, int total)? onProgress,
  }) async {
    final api = _api;
    if (api == null) return null;
    void progress(_Progress p) =>
        onProgress?.call(p.done.toDartInt, p.total.toDartInt);
    try {
      return _toStatus(await api.downloadAll(progress.toJS).toDart);
    } catch (_) {
      return null;
    }
  }
}
