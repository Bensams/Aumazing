// Prepares a finished `flutter build web` output for offline use (AUM-334).
//
//   flutter build web --base-href /app/ --dart-define-from-file=env/dev.json
//   dart run tool/build_offline_web.dart            # defaults to build/web
//
// Writes offline_manifest.json — every build file with a content hash, split
// into "core" (precached when the app is installed) and "lazy" (cached on
// first use or by the background download) — and stamps the build's version
// into offline_sw.js so browsers pick up the new service worker.
//
// Must run after every web build, or the service worker never installs and
// the app is online-only again.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const versionPlaceholder = '__AUMAZING_OFFLINE_VERSION__';
const manifestFile = 'offline_manifest.json';
const serviceWorkerFile = 'offline_sw.js';

/// Where a build file goes in the offline cache.
enum OfflineTier { core, lazy, skip }

/// The CanvasKit builds the default (non-wasm) renderer loads: the generic one
/// and the smaller one Chromium browsers get. The skwasm/wimp variants are
/// only used by `--wasm` builds.
const _coreCanvasKit = {
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
};

const _lazyPrefixes = [
  // Voice lines, sound effects and music: most of the build's weight, and a
  // game only needs its own. Cached as played, then by the background fill.
  'assets/packages/shared_audio/',
  'audio_fallback/',
];

const _mediaExtensions = {'.mp3', '.wav', '.ogg', '.m4a', '.aac', '.mp4', '.webm'};

OfflineTier classify(String path) {
  if (path == manifestFile ||
      path == serviceWorkerFile ||
      path == 'version.json' ||
      path == 'flutter_service_worker.js' ||
      path.endsWith('.symbols') ||
      path.endsWith('.map')) {
    return OfflineTier.skip;
  }
  if (path.startsWith('canvaskit/')) {
    return _coreCanvasKit.contains(path) ? OfflineTier.core : OfflineTier.lazy;
  }
  if (_lazyPrefixes.any(path.startsWith)) return OfflineTier.lazy;
  // The splash and login-background videos play on every launch.
  if (path.startsWith('assets/assets/videos/')) return OfflineTier.core;
  final dot = path.lastIndexOf('.');
  if (dot != -1 && _mediaExtensions.contains(path.substring(dot).toLowerCase())) {
    return OfflineTier.lazy;
  }
  // Only opened from the install banner, or by the licence page.
  if (path == 'ios-install-guide.png' || path == 'assets/NOTICES') {
    return OfflineTier.lazy;
  }
  return OfflineTier.core;
}

/// Builds the manifest from build-relative paths mapped to their content
/// hashes. The version changes exactly when some file's content does.
Map<String, Object> buildManifest(Map<String, String> hashes) {
  final core = <String, String>{};
  final lazy = <String, String>{};
  final paths = hashes.keys.toList()..sort();
  for (final path in paths) {
    switch (classify(path)) {
      case OfflineTier.core:
        core[path] = hashes[path]!;
      case OfflineTier.lazy:
        lazy[path] = hashes[path]!;
      case OfflineTier.skip:
        break;
    }
  }
  final fingerprint = [
    for (final path in paths)
      if (classify(path) != OfflineTier.skip) '$path ${hashes[path]}',
  ].join('\n');
  final version = sha256.convert(utf8.encode(fingerprint)).toString().substring(0, 16);
  return {'version': version, 'core': core, 'lazy': lazy};
}

Future<void> main(List<String> args) async {
  final buildDir = Directory(args.isEmpty ? 'build/web' : args.first);
  final worker = File('${buildDir.path}/$serviceWorkerFile');
  if (!worker.existsSync()) {
    stderr.writeln('No $serviceWorkerFile in ${buildDir.path} — run `flutter build web` first.');
    exit(1);
  }
  final source = worker.readAsStringSync();
  if (!source.contains(versionPlaceholder)) {
    stderr.writeln('${worker.path} is already stamped — rebuild with `flutter build web` first.');
    exit(1);
  }

  final hashes = <String, String>{};
  final sizes = <String, int>{};
  String slashes(String p) => p.replaceAll(r'\', '/');
  var root = slashes(buildDir.absolute.path);
  if (!root.endsWith('/')) root = '$root/';
  for (final entity in buildDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = slashes(entity.absolute.path).substring(root.length);
    final bytes = entity.readAsBytesSync();
    hashes[path] = sha256.convert(bytes).toString().substring(0, 16);
    sizes[path] = bytes.length;
  }

  final manifest = buildManifest(hashes);
  File('${buildDir.path}/$manifestFile').writeAsStringSync(jsonEncode(manifest));
  worker.writeAsStringSync(source.replaceAll(versionPlaceholder, manifest['version']! as String));

  String megabytes(Map<String, String> files) =>
      (files.keys.fold<int>(0, (sum, p) => sum + sizes[p]!) / (1 << 20)).toStringAsFixed(1);
  final core = manifest['core']! as Map<String, String>;
  final lazy = manifest['lazy']! as Map<String, String>;
  stdout.writeln('Offline build ${manifest['version']}: '
      '${core.length} core files (${megabytes(core)} MB), '
      '${lazy.length} lazy files (${megabytes(lazy)} MB).');
}
