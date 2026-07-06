/// Backend + OAuth configuration, injected at build time.
///
/// Prefer `--dart-define-from-file` so secrets stay out of source control:
///
///   flutter run --dart-define-from-file=env/dev.json
///   flutter build apk --release --dart-define-from-file=env/dev.json
///
/// The Supabase URL and anon (publishable) key have safe defaults so the
/// app runs even without the define file — they are public by design (RLS
/// enforces all data access), mirroring [ApiConfig.aiAssessmentBaseUrl].
/// The sensitive OAuth values (Facebook token) have NO default and must be
/// supplied via the define file for social login to work.
class SupabaseConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://lzvvjlcfoyczikaszrbp.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_LmDmXen9C_J8G_SDMi-LCA_sD23uwZv',
  );

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
