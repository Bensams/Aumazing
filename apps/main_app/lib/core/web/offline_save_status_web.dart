import 'dart:js_interop';

import 'offline_save_status.dart';

@JS('aumazingOffline')
external _Progress? get _published;

@JS('addEventListener')
external void _addEventListener(String type, JSFunction listener);

extension type _Progress(JSObject _) implements JSObject {
  external String? get status;
  external String? get reason;
  external JSNumber? get done;
  external JSNumber? get total;
}

/// Browser: reads what the loading page (web/offline.js) has published so
/// far, then follows its `aumazing-offline` events.
void watchOfflineSaves(void Function(OfflineSaveProgress?) onChange) {
  void read() {
    final published = _published;
    onChange(
      published == null
          ? null
          : OfflineSaveProgress.parse(
            status: published.status,
            reason: published.reason,
            done: published.done?.toDartDouble,
            total: published.total?.toDartDouble,
          ),
    );
  }

  _addEventListener('aumazing-offline', ((JSAny? _) => read()).toJS);
  read();
}
