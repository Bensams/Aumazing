import 'dart:convert';
import 'dart:io';

import 'package:aumazing/features/app_update/app_release.dart';
import 'package:aumazing/features/app_update/app_update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePlatform extends AppUpdatePlatform {
  FakePlatform(this.dir, {this.installedCode = 8, this.canInstall = true});

  final Directory dir;
  final int installedCode;
  bool canInstall;
  final installed = <String>[];
  int settingsOpened = 0;

  @override
  Future<InstalledVersion> installedVersion() async =>
      InstalledVersion(code: installedCode, name: '1.6.0');

  @override
  Future<bool> canInstallPackages() async => canInstall;

  @override
  Future<bool> openInstallPermissionSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<bool> installApk(String path) async {
    installed.add(path);
    return true;
  }

  @override
  Future<Directory> downloadDirectory() async => Directory('${dir.path}/apk');
}

final apkBytes = utf8.encode('pretend this is an APK');
final apkHash = sha256.convert(apkBytes).toString();

AppRelease release({int code = 9, String? hash, int? minSupported}) =>
    AppRelease(
      versionName: '1.6.1',
      versionCode: code,
      downloadUrl: Uri.parse('https://example.com/aumazing.apk'),
      sha256: hash ?? apkHash,
      releaseNotes: 'Fixes',
      minSupportedCode: minSupported,
    );

Future<void> writeApk(
  Uri _,
  File target,
  void Function(double?) onProgress,
) async {
  await target.writeAsBytes(apkBytes);
  onProgress(1);
}

void main() {
  late Directory dir;
  late FakePlatform platform;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('app_update_test');
    platform = FakePlatform(dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  AppUpdateService service({
    AppRelease? latest,
    ApkDownloader downloader = writeApk,
  }) => AppUpdateService(
    fetchLatest: () async => latest,
    platform: platform,
    downloader: downloader,
    supported: true,
  );

  group('check', () {
    test('offers a release with a higher versionCode', () async {
      final s = service(latest: release());
      await s.check();
      expect(s.status, AppUpdateStatus.available);
      expect(s.latest?.versionName, '1.6.1');
      expect(s.shouldPrompt, isTrue);
      expect(s.isRequired, isFalse);
    });

    test(
      'is up to date when the newest release is the installed one',
      () async {
        final s = service(latest: release(code: 8));
        await s.check();
        expect(s.status, AppUpdateStatus.upToDate);
        expect(s.latest, isNull);
        expect(s.shouldPrompt, isFalse);
      },
    );

    test('is up to date when nothing is published', () async {
      final s = service();
      await s.check();
      expect(s.status, AppUpdateStatus.upToDate);
    });

    test('a quiet check that fails says nothing', () async {
      final s = AppUpdateService(
        fetchLatest: () async => throw const SocketException('offline'),
        platform: platform,
        supported: true,
      );
      await s.check(quiet: true);
      expect(s.status, AppUpdateStatus.idle);
      expect(s.error, isNull);
    });

    test('a manual check that fails explains why', () async {
      final s = AppUpdateService(
        fetchLatest: () async => throw const SocketException('offline'),
        platform: platform,
        supported: true,
      );
      await s.check();
      expect(s.status, AppUpdateStatus.failed);
      expect(s.error, contains("Couldn't check"));
    });

    test('does nothing off Android', () async {
      var fetched = false;
      final s = AppUpdateService(
        fetchLatest: () async {
          fetched = true;
          return release();
        },
        platform: platform,
        supported: false,
      );
      await s.check();
      expect(fetched, isFalse);
      expect(s.status, AppUpdateStatus.unsupported);
      expect(s.shouldPrompt, isFalse);
    });
  });

  group('dismiss', () {
    test('hides the prompt for that version only', () async {
      final s = service(latest: release());
      await s.check();
      await s.dismiss();
      expect(s.shouldPrompt, isFalse);

      // The choice survives a restart, and a newer build prompts again.
      final again = service(latest: release());
      await again.check();
      expect(again.shouldPrompt, isFalse);
      final newer = service(latest: release(code: 10));
      await newer.check();
      expect(newer.shouldPrompt, isTrue);
    });

    test('cannot hide a required update', () async {
      final s = service(latest: release(minSupported: 9));
      await s.check();
      expect(s.isRequired, isTrue);
      await s.dismiss();
      expect(s.shouldPrompt, isTrue);
    });
  });

  group('downloadAndInstall', () {
    test('verifies the download and hands it to the installer', () async {
      final s = service(latest: release());
      await s.check();
      await s.downloadAndInstall();
      expect(platform.installed, hasLength(1));
      expect(File(platform.installed.single).readAsBytesSync(), apkBytes);
      expect(s.status, AppUpdateStatus.readyToInstall);
    });

    test('never installs a file whose checksum does not match', () async {
      final s = service(latest: release(hash: 'a' * 64));
      await s.check();
      await s.downloadAndInstall();
      expect(platform.installed, isEmpty);
      expect(s.status, AppUpdateStatus.failed);
      expect(s.error, contains('damaged'));
      expect(Directory('${dir.path}/apk').listSync(), isEmpty);
    });

    test('a failed download can be retried', () async {
      var attempts = 0;
      final s = service(
        latest: release(),
        downloader: (url, target, onProgress) async {
          attempts++;
          if (attempts == 1) throw const SocketException('dropped');
          await writeApk(url, target, onProgress);
        },
      );
      await s.check();
      await s.downloadAndInstall();
      expect(s.status, AppUpdateStatus.failed);
      await s.downloadAndInstall();
      expect(s.status, AppUpdateStatus.readyToInstall);
      expect(platform.installed, hasLength(1));
    });

    test('asks for the install permission, then carries on without '
        're-downloading', () async {
      platform.canInstall = false;
      var downloads = 0;
      final s = service(
        latest: release(),
        downloader: (url, target, onProgress) async {
          downloads++;
          await writeApk(url, target, onProgress);
        },
      );
      await s.check();
      await s.downloadAndInstall();
      expect(s.status, AppUpdateStatus.needsPermission);
      expect(platform.settingsOpened, 1);
      expect(platform.installed, isEmpty);

      // A check while waiting must not throw the download away.
      await s.check();
      expect(s.status, AppUpdateStatus.needsPermission);

      platform.canInstall = true;
      await s.install();
      expect(platform.installed, hasLength(1));
      expect(downloads, 1);
    });
  });

  group('AppRelease.fromRow', () {
    Map<String, dynamic> row() => {
      'version_name': '1.6.1',
      'version_code': 9,
      'download_url': 'https://example.com/aumazing.apk',
      'sha256': apkHash.toUpperCase(),
      'release_notes': '  ',
      'min_supported_code': null,
    };

    test('reads a valid row', () {
      final r = AppRelease.fromRow(row())!;
      expect(r.versionCode, 9);
      expect(r.sha256, apkHash);
      expect(r.releaseNotes, isNull);
    });

    test('rejects a plain-http download link', () {
      expect(
        AppRelease.fromRow(
          row()..['download_url'] = 'http://example.com/a.apk',
        ),
        isNull,
      );
    });

    test('rejects a malformed checksum', () {
      expect(AppRelease.fromRow(row()..['sha256'] = 'abc'), isNull);
    });
  });
}
