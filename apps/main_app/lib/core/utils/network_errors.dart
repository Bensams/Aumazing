/// Helpers for turning raw network exceptions into user-friendly messages.
library;

/// Returns true if [error] looks like a connectivity failure (offline,
/// DNS failure, unreachable network, refused connection).
bool isNetworkError(Object error) {
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('No address associated') ||
      text.contains('Network is unreachable') ||
      text.contains('Connection refused');
}

/// Converts raw exceptions into friendly messages (esp. offline/network).
///
/// Network-shaped errors become a clear offline message; anything else
/// falls back to [fallback] when given, or the raw error text otherwise.
String friendly(Object error, {String? fallback}) {
  if (isNetworkError(error)) {
    return 'No internet connection. Please check your network and try again.';
  }
  return fallback ?? error.toString();
}
