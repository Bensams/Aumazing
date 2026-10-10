import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_release.dart';

/// Where the in-app update is in its life.
enum AppUpdateStatus {
  /// Not the sideloaded Android app (web, desktop, iOS): nothing to offer.
  unsupported,

  /// No check has finished yet.
  idle,
  checking,
  upToDate,

  /// A newer build is published and has not been downloaded.
  available,
  downloading,

  /// Downloaded and verified; waiting for the parent to confirm the install.
  readyToInstall,

  /// Android has not yet allowed Aumazing to install apps. The settings page
  /// has been opened; the parent comes back and taps Install again.
  needsPermission,
  failed,
}

/// Android-only operations, behind a class so tests can swap them out.
class AppUpdatePlatform {
  const AppUpdatePlatform();

  static const MethodChannel _channel = MethodChannel('aumazing/app_update');

  Future<InstalledVersion> installedVersion() async {
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'installedVersion',
    );
    return InstalledVersion(
      code: (map?['code'] as num?)?.toInt() ?? 0,
      name: map?['name'] as String? ?? '',
    );
  }

  Future<bool> canInstallPackages() async =>
      await _channel.invokeMethod<bool>('canInstallPackages') ?? false;

  Future<bool> openInstallPermissionSettings() async =>
      await _channel.invokeMethod<bool>('openInstallPermissionSettings') ??
      false;

  Future<bool> installApk(String path) async =>
      await _channel.invokeMethod<bool>('installApk', {'path': path}) ?? false;

  /// The folder the native FileProvider shares (`res/xml/app_update_paths`).
  Future<Directory> downloadDirectory() async =>
      Directory('${(await getTemporaryDirectory()).path}/app_updates');
}

/// Downloads [url] into [target], reporting progress from 0 to 1 (null when
/// the server gives no length).
typedef ApkDownloader =
    Future<void> Function(
      Uri url,
      File target,
      void Function(double? progress) onProgress,
    );

/// Checks for a newer published APK and installs it in place. The app is
/// sideloaded from GitHub Releases, so no store does this for it.
///
/// The check runs once in the background at launch and never blocks it. A
/// download is checked against the release's SHA-256 before Android sees it,
/// and Android itself refuses an APK not signed with the installed app's key,
/// so a wrong file cannot replace the app. Data is kept across the update
/// because it is the same package.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    Future<AppRelease?> Function()? fetchLatest,
    AppUpdatePlatform platform = const AppUpdatePlatform(),
    ApkDownloader? downloader,
    bool? supported,
  }) : _fetchLatest = fetchLatest ?? _fetchLatestFromSupabase,
       _platform = platform,
       _downloader = downloader ?? _httpDownload,
       _supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static final AppUpdateService instance = AppUpdateService();

  static const _dismissedKey = 'app_update_dismissed_version_code';

  final Future<AppRelease?> Function() _fetchLatest;
  final AppUpdatePlatform _platform;
  final ApkDownloader _downloader;
  final bool _supported;

  AppUpdateStatus _status = AppUpdateStatus.idle;
  InstalledVersion? _installed;
  AppRelease? _latest;
  double? _progress;
  String? _error;
  File? _apk;
  int? _dismissedCode;

  AppUpdateStatus get status =>
      _supported ? _status : AppUpdateStatus.unsupported;
  InstalledVersion? get installed => _installed;

  /// The newer release on offer, or null when up to date or not checked.
  AppRelease? get latest => _latest;

  /// Download progress from 0 to 1, or null when the size is unknown.
  double? get progress => _progress;
  String? get error => _error;

  bool get isRequired =>
      _latest != null &&
      _installed != null &&
      _latest!.isRequiredFor(_installed!.code);

  /// True when the dashboard should invite the parent to update: a newer
  /// build exists and they have not set this version aside. A required
  /// update cannot be set aside.
  bool get shouldPrompt {
    if (_latest == null || status == AppUpdateStatus.unsupported) return false;
    if (isRequired) return true;
    return _dismissedCode != _latest!.versionCode;
  }

  bool get isBusy =>
      _status == AppUpdateStatus.checking ||
      _status == AppUpdateStatus.downloading;

  /// Looks for a newer release. With [quiet] (the launch check) a failure
  /// leaves the last known state alone instead of reporting an error, since
  /// an offline launch is normal.
  Future<void> check({bool quiet = false}) async {
    if (!_supported || isBusy) return;
    // Mid-update states already hold the answer; re-checking would throw the
    // downloaded file away.
    if (_status == AppUpdateStatus.readyToInstall ||
        _status == AppUpdateStatus.needsPermission) {
      return;
    }
    _set(AppUpdateStatus.checking);
    try {
      _installed ??= await _platform.installedVersion();
      final prefs = await SharedPreferences.getInstance();
      _dismissedCode = prefs.getInt(_dismissedKey);
      final release = await _fetchLatest();
      if (release != null && release.isNewerThan(_installed!.code)) {
        _latest = release;
        _set(AppUpdateStatus.available);
      } else {
        _latest = null;
        _set(AppUpdateStatus.upToDate);
      }
    } catch (e) {
      debugPrint('[AppUpdate] Check failed: $e');
      if (quiet) {
        _set(
          _latest == null ? AppUpdateStatus.idle : AppUpdateStatus.available,
        );
      } else {
        _fail(
          "Couldn't check for updates. Check the connection and try again.",
        );
      }
    }
  }

  /// Hides the dashboard prompt for the release on offer until a newer one
  /// is published. Settings still offers it.
  Future<void> dismiss() async {
    final release = _latest;
    if (release == null || isRequired) return;
    _dismissedCode = release.versionCode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedKey, release.versionCode);
  }

  /// Downloads (if needed), verifies and installs the release on offer.
  Future<void> downloadAndInstall() async {
    final release = _latest;
    if (!_supported || release == null || isBusy) return;
    if (_apk == null || !await _apk!.exists()) {
      final file = await _download(release);
      if (file == null) return;
      _apk = file;
    }
    await install();
  }

  /// Hands the verified APK to Android's installer. Safe to call again after
  /// the parent cancelled the installer or came back from the permission
  /// page.
  Future<void> install() async {
    final apk = _apk;
    if (apk == null) return;
    try {
      if (!await _platform.canInstallPackages()) {
        _set(AppUpdateStatus.needsPermission);
        await _platform.openInstallPermissionSettings();
        return;
      }
      if (!await _platform.installApk(apk.path)) {
        _fail("Android couldn't open the installer. Try again.");
        return;
      }
      // There is no result to wait for: a successful install replaces and
      // restarts the app. If the parent cancels, the button is still there.
      _set(AppUpdateStatus.readyToInstall);
    } catch (e) {
      debugPrint('[AppUpdate] Install failed: $e');
      _fail("Android couldn't open the installer. Try again.");
    }
  }

  Future<File?> _download(AppRelease release) async {
    _progress = 0;
    _set(AppUpdateStatus.downloading);
    File? target;
    try {
      final dir = await _platform.downloadDirectory();
      // Older downloads are dead weight once a newer build is on offer.
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      target = File('${dir.path}/aumazing-${release.versionCode}.apk');

      var lastPercent = -1;
      await _downloader(release.downloadUrl, target, (progress) {
        // One notification per whole percent, not one per network chunk.
        final percent = progress == null ? null : (progress * 100).floor();
        if (percent != null && percent == lastPercent) return;
        lastPercent = percent ?? lastPercent;
        _progress = progress;
        notifyListeners();
      });

      final digest = await sha256.bind(target.openRead()).first;
      if (digest.toString() != release.sha256) {
        await target.delete();
        _fail('The download was damaged, so it was not installed. Try again.');
        return null;
      }
      return target;
    } catch (e) {
      debugPrint('[AppUpdate] Download failed: $e');
      if (target != null && await target.exists()) await target.delete();
      _fail("The download didn't finish. Check the connection and try again.");
      return null;
    }
  }

  void _fail(String message) {
    _error = message;
    _set(AppUpdateStatus.failed);
  }

  void _set(AppUpdateStatus status) {
    if (status != AppUpdateStatus.failed) _error = null;
    _status = status;
    notifyListeners();
  }

  static Future<AppRelease?> _fetchLatestFromSupabase() async {
    final row = await Supabase.instance.client
        .from('app_releases')
        .select()
        .eq('platform', 'android')
        .eq('is_published', true)
        .order('version_code', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));
    return row == null ? null : AppRelease.fromRow(row);
  }

  static Future<void> _httpDownload(
    Uri url,
    File target,
    void Function(double? progress) onProgress,
  ) async {
    final client = http.Client();
    try {
      // GitHub release links redirect to their storage host; the request
      // follows that itself.
      final response = await client
          .send(http.Request('GET', url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final total = response.contentLength;
      final sink = target.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 60),
        )) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(total == null || total == 0 ? null : received / total);
        }
      } finally {
        await sink.close();
      }
      if (total != null && received != total) {
        throw HttpException('Got $received of $total bytes', uri: url);
      }
    } finally {
      client.close();
    }
  }
}
