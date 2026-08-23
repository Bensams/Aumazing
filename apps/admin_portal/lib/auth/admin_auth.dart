import 'package:supabase_flutter/supabase_flutter.dart';

/// Browser-safe redirect back to the admin portal origin.
///
/// Strips query and fragment so an in-progress OAuth hash (tokens, errors)
/// is never sent to Google as `redirect_to`.
String adminPortalOAuthRedirectTo(Uri current) {
  final scheme = current.scheme.isEmpty ? 'http' : current.scheme;
  final host = current.host.isEmpty ? 'localhost' : current.host;
  final skipPort =
      !current.hasPort ||
      (scheme == 'http' && current.port == 80) ||
      (scheme == 'https' && current.port == 443);
  return Uri(
    scheme: scheme,
    host: host,
    port: skipPort ? null : current.port,
    path: '/',
  ).toString();
}

/// Surfaces a failed OAuth round-trip on the login form instead of a blank
/// screen. Ignores session fragments (`access_token`, `refresh_token`).
String? oauthErrorFromUri(Uri uri) {
  final params = <String, String>{...uri.queryParameters};
  if (uri.fragment.contains('=')) {
    params.addAll(Uri.splitQueryString(uri.fragment));
  }
  final error = params['error'];
  if (error == null || error.isEmpty) return null;
  final description = params['error_description']?.replaceAll('+', ' ').trim();
  if (description != null && description.isNotEmpty) return description;
  return 'Google sign-in failed. Please try again.';
}

/// Auth operations the login screen needs. Tests inject a fake.
abstract class AdminAuth {
  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  /// Starts Google OAuth. `true` means the browser was launched (or
  /// navigated). Session completion is observed via `onAuthStateChange`.
  Future<bool> signInWithGoogle({required String redirectTo});
}

class SupabaseAdminAuth implements AdminAuth {
  SupabaseAdminAuth([GoTrueClient? auth]) : _auth = auth;

  final GoTrueClient? _auth;

  GoTrueClient get _client => _auth ?? Supabase.instance.client.auth;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _client.signInWithPassword(email: email, password: password);
  }

  @override
  Future<bool> signInWithGoogle({required String redirectTo}) {
    return _client.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
    );
  }
}
