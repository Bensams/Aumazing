/// One published Android build, as stored in `public.app_releases`.
class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.sha256,
    this.releaseNotes,
    this.minSupportedCode,
  });

  /// Reads a Supabase row. Returns null for a row the app cannot use rather
  /// than throwing, so a bad row never breaks the launch check.
  static AppRelease? fromRow(Map<String, dynamic> row) {
    final code = row['version_code'];
    final name = row['version_name'];
    final url = Uri.tryParse(row['download_url'] as String? ?? '');
    final hash = (row['sha256'] as String?)?.toLowerCase();
    if (code is! int || name is! String || url == null || hash == null) {
      return null;
    }
    if (url.scheme != 'https' || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      return null;
    }
    final notes = (row['release_notes'] as String?)?.trim();
    return AppRelease(
      versionName: name,
      versionCode: code,
      downloadUrl: url,
      sha256: hash,
      releaseNotes: notes == null || notes.isEmpty ? null : notes,
      minSupportedCode: row['min_supported_code'] as int?,
    );
  }

  final String versionName;

  /// Android versionCode: the number after `+` in pubspec's `version:`.
  final int versionCode;
  final Uri downloadUrl;

  /// Lower-case hex SHA-256 the downloaded APK must match.
  final String sha256;
  final String? releaseNotes;

  /// Installed builds below this code are told the update is required.
  final int? minSupportedCode;

  bool isNewerThan(int installedCode) => versionCode > installedCode;

  bool isRequiredFor(int installedCode) =>
      minSupportedCode != null && installedCode < minSupportedCode!;
}

/// The version of the build that is running, read from Android.
class InstalledVersion {
  const InstalledVersion({required this.code, required this.name});

  final int code;
  final String name;
}
