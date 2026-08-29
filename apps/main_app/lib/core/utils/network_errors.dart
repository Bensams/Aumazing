/// Helpers for turning raw network exceptions into user-friendly messages.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// What a parent is told when nothing more specific is known.
const _genericFailure = 'Something went wrong. Please try again.';

/// Converts raw exceptions into messages a non-technical parent can act on.
///
/// The raw exception is never shown. `error.toString()` used to be the last
/// resort, which is how a cancelled Google sign-in reached the Bind Account
/// dialog as `AuthException(message: Sign-in was cancelled. Please try again.,
/// statusCode: null, code: null)` — the sentence a parent needed was in there,
/// wrapped in three fields that meant nothing to them. So the sentence is
/// unwrapped and the wrapper dropped.
///
/// Anything whose text is not already parent-facing becomes [fallback], or a
/// generic apology. The original always goes to the debug log, so nothing is
/// lost for whoever is debugging — only for whoever is reading the dialog.
String friendly(Object error, {String? fallback}) {
  if (isNetworkError(error)) {
    return 'No internet connection. Please check your network and try again.';
  }

  // A message we wrote ourselves and passed through as-is.
  if (error is String) return error;

  final message = _authorMessage(error);
  if (message != null && message.isNotEmpty) return message;

  debugPrint('[friendly] Unrecognised error surfaced to the user: $error');
  return fallback ?? _genericFailure;
}

/// The already-human sentence carried by [error], or null when it has none.
///
/// [AuthException.message] is written for the person signing in — by Supabase
/// for its own failures, and by `AuthService` for the ones it raises itself
/// (cancelled Google sign-in). [PostgrestException]
/// and friends are the opposite: their messages are database diagnostics, so
/// they deliberately fall through to the generic text.
String? _authorMessage(Object error) {
  if (error is AuthException) return error.message.trim();
  return null;
}
