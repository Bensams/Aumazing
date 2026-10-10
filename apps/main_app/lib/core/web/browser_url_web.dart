import 'dart:js_interop';

@JS('history')
external _History get _history;

extension type _History(JSObject _) implements JSObject {
  external void replaceState(JSAny? data, String unused, String url);
}

/// Browser: replaces the current history entry, so Back does not return to
/// the old address either.
void replaceBrowserUrl(String url) => _history.replaceState(null, '', url);
