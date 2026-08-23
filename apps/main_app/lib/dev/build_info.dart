/// Provenance stamp shown in Developer Tools, so a tester can confirm which
/// build is actually running - the updated code, or a stale one left over from
/// an earlier `flutter run`.
///
/// Two independent signals, strongest first:
///
///  * [marker] is a plain source constant compiled into the app. Bump it in the
///    same change whenever you want an unmistakable "this is the new code"
///    signal that needs no build tooling at all: if Developer Tools shows the
///    new marker, the new code is definitely what is running. A stale build
///    shows the old marker (or none).
///  * [gitCommit], [gitBranch] and [buildTime] are filled from `--dart-define`
///    at build time - see `scripts/run-dev.ps1`, which stamps the real values.
///    A plain `flutter run` leaves them as `local` / `dev run`, which is
///    expected and simply means "not stamped", not "wrong build".
class BuildInfo {
  BuildInfo._();

  /// Bump this in any change you want to be able to spot-check on the device.
  /// Kept short - it shares one line in the Developer Tools readout.
  static const String marker = 'AUMZ-12 - gameplay export CSV JSON PDF';

  static const String gitCommit =
      String.fromEnvironment('GIT_COMMIT', defaultValue: 'local');

  static const String gitBranch =
      String.fromEnvironment('GIT_BRANCH', defaultValue: 'local');

  static const String buildTime =
      String.fromEnvironment('BUILD_TIME', defaultValue: 'dev run');

  /// One-line summary for the Developer Tools "Build" row: the marker, then the
  /// git provenance in parentheses (branch, short commit when stamped, time).
  static String get summary {
    final commit = gitCommit == 'local' ? '' : ' @ $gitCommit';
    return '$marker  ($gitBranch$commit - $buildTime)';
  }
}
