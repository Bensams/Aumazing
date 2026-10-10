// Prepares a finished `flutter build web` output for offline use (AUM-334).
//
//   flutter build web --base-href /app/ --dart-define-from-file=env/dev.json
//   dart run tool/build_offline_web.dart            # defaults to build/web
//
// Writes offline_manifest.json — every build file with a content hash, split
// into "boot" (needed to open the app), "core" (pictures, models, videos) and
// "lazy" (game audio), plus each file's size — and stamps the build's version
// into offline_sw.js so browsers pick up the new service worker. The loading
// page (web/offline.js) reads the manifest: it saves the boot files before the
// app starts, and everything else in the background while the child plays.
//
// Must run after every web build, or the service worker never installs and
// the app is online-only again.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const versionPlaceholder = '__AUMAZING_OFFLINE_VERSION__';

/// Where Flutter's web engine downloads its fonts from at run time: Roboto
/// (the default text font) on every start, and fallback fonts — emoji,
/// symbols — the first time a glyph needs one.
const fontBaseUrl = 'https://fonts.gstatic.com/s/';

/// Fallback font families the app can need offline. Games draw objects as
/// emoji until (or instead of) their picture cards, so without these a child
/// offline sees crossed-out boxes.
const _offlineFontFamilies = [
  'notocoloremoji/',
  'notosanssymbols/',
  'notosanssymbols2/',
  'notosansmath/',
];

/// The engine's font URLs (relative to [fontBaseUrl]) the loading page saves
/// for offline use, read from this Flutter SDK's own engine sources so they
/// always match the engine that ships in the build.
List<String> offlineFontUrls({
  required String canvasKitFonts,
  required String fallbackData,
}) {
  final urls = <String>{};
  final roboto = RegExp(r"roboto/v\d+/[\w-]+\.woff2").firstMatch(canvasKitFonts);
  if (roboto != null) urls.add(roboto.group(0)!);
  for (final match in RegExp(r"'([a-z0-9]+/v\d+/[^']+\.woff2)'").allMatches(fallbackData)) {
    final url = match.group(1)!;
    if (_offlineFontFamilies.any(url.startsWith)) urls.add(url);
  }
  return urls.toList()..sort();
}

/// Reads [offlineFontUrls] from the Flutter SDK running this tool.
List<String> _sdkFontUrls() {
  // dart lives at <flutter>/bin/cache/dart-sdk/bin/dart.
  final flutterRoot = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent;
  final engine = '${flutterRoot.path}/bin/cache/flutter_web_sdk/lib/_engine/engine';
  final fonts = File('$engine/canvaskit/fonts.dart');
  final fallback = File('$engine/font_fallback_data.dart');
  if (!fonts.existsSync() || !fallback.existsSync()) {
    stderr.writeln('Flutter web engine sources not found under $engine — '
        'fonts will only be saved as they are first used.');
    return const [];
  }
  return offlineFontUrls(
    canvasKitFonts: fonts.readAsStringSync(),
    fallbackData: fallback.readAsStringSync(),
  );
}
const manifestFile = 'offline_manifest.json';
const serviceWorkerFile = 'offline_sw.js';

/// Where a build file goes in the offline cache.
///
/// - [boot]: needed to open the app (code, engine, fonts, asset manifests);
///   saved before the app starts.
/// - [core]: pictures, assessment models and videos; saved first once the
///   app is running.
/// - [lazy]: voice lines, sound effects and music; saved after the core.
/// - [skip]: never cached.
enum OfflineTier { boot, core, lazy, skip }

/// The CanvasKit builds the default (non-wasm) renderer loads: the generic one
/// and the smaller one Chromium browsers get. The skwasm/wimp/experimental
/// variants are only used by `--wasm` builds, so they are never saved.
const _coreCanvasKit = {
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
};

const _lazyPrefixes = [
  // Voice lines, sound effects and music. The loading page saves the ones a
  // child needs; other languages' voices follow in the background.
  'assets/packages/shared_audio/',
  'audio_fallback/',
];

const _mediaExtensions = {'.mp3', '.wav', '.ogg', '.m4a', '.aac', '.mp4', '.webm'};

/// Art and models the app only shows or runs once a screen needs them. Until
/// they are saved they stream from the network like any web page.
const _backgroundPrefixes = [
  'assets/assets/',
  'assets/packages/shared_ui/assets/',
];

const _fontExtensions = {'.ttf', '.otf', '.woff', '.woff2'};

String _extension(String path) {
  final dot = path.lastIndexOf('.');
  return dot == -1 ? '' : path.substring(dot).toLowerCase();
}

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
    return _coreCanvasKit.contains(path) ? OfflineTier.boot : OfflineTier.skip;
  }
  if (_lazyPrefixes.any(path.startsWith)) return OfflineTier.lazy;
  final extension = _extension(path);
  // The splash and login-background videos play on every launch, but stream
  // fine online until they are saved.
  if (path.startsWith('assets/assets/videos/')) return OfflineTier.core;
  if (_mediaExtensions.contains(extension)) return OfflineTier.lazy;
  // Only opened from the install banner, or by the licence page.
  if (path == 'ios-install-guide.png' || path == 'assets/NOTICES') {
    return OfflineTier.lazy;
  }
  // The app's text fonts are needed for its very first frame.
  if (_fontExtensions.contains(extension)) return OfflineTier.boot;
  // The assessment runtime's WASM binary is only fetched when an assessment
  // model first runs; its small JS loader starts with the page.
  if (path.startsWith('ort/') && extension == '.wasm') return OfflineTier.core;
  // The full-size logo is only shown by the iOS install banner.
  if (path == 'aumazing-logo.png') return OfflineTier.core;
  if (_backgroundPrefixes.any(path.startsWith)) return OfflineTier.core;
  return OfflineTier.boot;
}

/// Builds the manifest from build-relative paths mapped to their content
/// hashes, and their sizes in bytes when known. The version changes exactly
/// when some file's content does.
Map<String, Object> buildManifest(
  Map<String, String> hashes, {
  Map<String, int> sizes = const {},
}) {
  final boot = <String, String>{};
  final core = <String, String>{};
  final lazy = <String, String>{};
  final paths = hashes.keys.toList()..sort();
  for (final path in paths) {
    switch (classify(path)) {
      case OfflineTier.boot:
        boot[path] = hashes[path]!;
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
  return {
    'version': version,
    'boot': boot,
    'core': core,
    'lazy': lazy,
    'sizes': {
      for (final path in [...boot.keys, ...core.keys, ...lazy.keys])
        if (sizes[path] != null) path: sizes[path]!,
    },
  };
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

  final manifest = buildManifest(hashes, sizes: sizes)
    ..['fontBaseUrl'] = fontBaseUrl
    ..['fonts'] = _sdkFontUrls();
  File('${buildDir.path}/$manifestFile').writeAsStringSync(jsonEncode(manifest));
  worker.writeAsStringSync(source.replaceAll(versionPlaceholder, manifest['version']! as String));

  String megabytes(Map<String, String> files) =>
      (files.keys.fold<int>(0, (sum, p) => sum + sizes[p]!) / (1 << 20)).toStringAsFixed(1);
  final boot = manifest['boot']! as Map<String, String>;
  final core = manifest['core']! as Map<String, String>;
  final lazy = manifest['lazy']! as Map<String, String>;
  stdout.writeln('Offline build ${manifest['version']}: '
      '${boot.length} boot files (${megabytes(boot)} MB), '
      '${core.length} core files (${megabytes(core)} MB), '
      '${lazy.length} lazy files (${megabytes(lazy)} MB), '
      '${(manifest['fonts']! as List).length} engine fonts.');
}
