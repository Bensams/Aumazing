/// Backend + OAuth configuration, injected at build time.
///
/// Values come from `--dart-define` / `--dart-define-from-file` so no
/// credential lives in source control:
///
///   flutter run --dart-define-from-file=env/dev.json
///   flutter build apk --release --dart-define-from-file=env/dev.json
///
/// Copy `env/dev.example.json` to `env/dev.json` (gitignored) and fill in
/// the project's values. The Supabase anon key is public-by-design (RLS
/// enforces access) but is still kept out of the repo as good hygiene.
class SupabaseConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Google OAuth **Web** client ID (not Android) — required by the
  /// Supabase OAuth flow.
  static const String googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Google OAuth iOS client ID (only needed for iOS builds).
  static const String googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  // ── Facebook OAuth ───────────────────────────────────────────────────
  static const String facebookAppId =
      String.fromEnvironment('FACEBOOK_APP_ID');
  static const String facebookClientToken =
      String.fromEnvironment('FACEBOOK_CLIENT_TOKEN');

  /// True when the required backend values were provided at build time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
