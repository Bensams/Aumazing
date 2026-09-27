import 'package:flutter_test/flutter_test.dart';

import '../../tool/build_offline_web.dart';

void main() {
  group('classify', () {
    test('app shell, code, engine, models, pictures and startup videos are core', () {
      for (final path in [
        'index.html',
        'main.dart.js',
        'flutter_bootstrap.js',
        'manifest.json',
        'sqlite3.wasm',
        'ort/ort-wasm-simd-threaded.wasm',
        'canvaskit/canvaskit.wasm',
        'canvaskit/chromium/canvaskit.wasm',
        'assets/AssetManifest.bin',
        'assets/FontManifest.json',
        'assets/assets/models/play.onnx',
        'assets/packages/shared_ui/assets/google_fonts/Nunito-Regular.ttf',
        'assets/packages/shared_ui/assets/characters/teddy/idle.png',
        'assets/assets/videos/Aumazing_Splash_Screen.mp4',
      ]) {
        expect(classify(path), OfflineTier.core, reason: path);
      }
    });

    test('game audio, music and on-demand pages are lazy', () {
      for (final path in [
        'assets/packages/shared_audio/assets/audio/en/hello.mp3',
        'audio_fallback/bg_music.mp3',
        'assets/packages/shared_ui/assets/seed_cards/audio/en/cat.mp3',
        'ios-install-guide.png',
        'assets/NOTICES',
      ]) {
        expect(classify(path), OfflineTier.lazy, reason: path);
      }
    });

    test('the worker, its manifest, debug symbols and wasm-only engine '
        'variants are never cached', () {
      for (final path in [
        'canvaskit/skwasm.wasm',
        'canvaskit/wimp.wasm',
        'canvaskit/experimental_webparagraph/canvaskit.wasm',
        'offline_sw.js',
        'offline_manifest.json',
        'version.json',
        'flutter_service_worker.js',
        'canvaskit/canvaskit.js.symbols',
        'main.dart.js.map',
      ]) {
        expect(classify(path), OfflineTier.skip, reason: path);
      }
    });
  });

  test('offlineFontUrls picks Roboto, emoji and symbol fonts only', () {
    final urls = offlineFontUrls(
      canvasKitFonts: "String _robotoUrl =\n"
          "    '\${configuration.fontFallbackBaseUrl}roboto/v32/KFOm-Abc.woff2';",
      fallbackData: '''
    'Noto Color Emoji 0',
    'notocoloremoji/v32/Yq6P-a.0.woff2',
    'Noto Sans Symbols 2 0',
    'notosanssymbols2/v24/I_uy-b.woff2',
    'Noto Sans JP 0',
    'notosansjp/v52/-F6j-c.0.woff2',
''',
    );
    expect(urls, [
      'notocoloremoji/v32/Yq6P-a.0.woff2',
      'notosanssymbols2/v24/I_uy-b.woff2',
      'roboto/v32/KFOm-Abc.woff2',
    ]);
  });

  group('buildManifest', () {
    final hashes = {
      'index.html': 'aaa',
      'main.dart.js': 'bbb',
      'audio_fallback/bg_music.mp3': 'ccc',
      'version.json': 'ddd',
    };

    test('splits files into core and lazy and drops skipped ones', () {
      final manifest = buildManifest(hashes);
      expect(manifest['core'], {'index.html': 'aaa', 'main.dart.js': 'bbb'});
      expect(manifest['lazy'], {'audio_fallback/bg_music.mp3': 'ccc'});
    });

    test('records the size of every cached file for the loading page', () {
      final manifest = buildManifest(
        hashes,
        sizes: {
          'index.html': 10,
          'main.dart.js': 20,
          'audio_fallback/bg_music.mp3': 30,
          'version.json': 40,
        },
      );
      expect(manifest['sizes'], {
        'index.html': 10,
        'main.dart.js': 20,
        'audio_fallback/bg_music.mp3': 30,
      });
    });

    test('version changes only when cached content changes', () {
      final version = buildManifest(hashes)['version'];
      expect(buildManifest(Map.of(hashes))['version'], version);
      expect(buildManifest({...hashes, 'version.json': 'zzz'})['version'], version);
      expect(buildManifest({...hashes, 'main.dart.js': 'new'})['version'], isNot(version));
    });
  });
}
