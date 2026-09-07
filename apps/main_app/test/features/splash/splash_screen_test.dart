import 'dart:async';
import 'dart:convert';

import 'package:aumazing/features/splash/splash_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as platform;

const _splashAsset = 'assets/videos/Aumazing_Splash_Screen.mp4';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late platform.VideoPlayerPlatform originalPlatform;
  late _SplashVideoPlatform video;
  late _ReplacementObserver navigation;
  late List<String> loadedAssets;

  setUp(() {
    originalPlatform = platform.VideoPlayerPlatform.instance;
    video = _SplashVideoPlatform();
    platform.VideoPlayerPlatform.instance = video;
    navigation = _ReplacementObserver();
    loadedAssets = [];
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final asset = utf8.decode(
        message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      loadedAssets.add(asset);
      // Only the selected splash asset exists in this isolated launch test.
      return asset == _splashAsset ? ByteData(1) : null;
    });
  });

  tearDown(() {
    platform.VideoPlayerPlatform.instance = originalPlatform;
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
  });

  Future<void> showSplash(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [navigation],
        home: const AumazingSplashScreen(),
      ),
    );
    await tester.pump();
  }

  testWidgets('uses the updated splash and applies volume before autoplay', (
    tester,
  ) async {
    video.volumeGate = Completer<void>();
    await showSplash(tester);

    expect(loadedAssets, contains(_splashAsset));
    expect(video.dataSource?.sourceType, platform.DataSourceType.asset);
    expect(video.dataSource?.asset, _splashAsset);

    video.initialize();
    await tester.pump();

    // Browser autoplay needs mute to have completed before play is requested.
    // Native launches keep the soundtrack; this assertion also runs on web.
    expect(video.requestedVolumes.last, kIsWeb ? 0.0 : 1.0);
    expect(video.playCalls, 0);
    video.volumeGate!.complete();
    // Let the awaited volume update finish and schedule the ready-state
    // rebuild before rendering the next frame.
    await tester.idle();
    await tester.pump();

    expect(video.playCalls, 1);
    expect(video.volumeAtPlay, kIsWeb ? 0.0 : 1.0);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(navigation.replacements, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a rejected play request continues launch instead of stalling', (
    tester,
  ) async {
    video.playGate = Completer<void>();
    await showSplash(tester);
    video.initialize();
    await tester.pump();
    expect(video.playCalls, 1);
    expect(navigation.replacements, 0);

    video.playGate!.completeError(
      PlatformException(
        code: 'playback_failed',
        message: 'Playback unavailable',
      ),
    );
    // Flush the async failure and navigation without building LoadingScreen,
    // whose authentication and asset-preload dependencies are outside this test.
    await tester.idle();
    expect(navigation.replacements, 1);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('video completion advances launch only once', (tester) async {
    await showSplash(tester);
    video.initialize();
    await tester.pump();

    video.events.add(
      platform.VideoEvent(eventType: platform.VideoEventType.completed),
    );
    await tester.idle();
    expect(navigation.replacements, 1);

    video.events.add(
      platform.VideoEvent(eventType: platform.VideoEventType.completed),
    );
    await tester.idle();
    expect(navigation.replacements, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _ReplacementObserver extends NavigatorObserver {
  int replacements = 0;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacements++;
  }
}

class _SplashVideoPlatform extends platform.VideoPlayerPlatform {
  final events = StreamController<platform.VideoEvent>();
  final requestedVolumes = <double>[];
  platform.DataSource? dataSource;
  Completer<void>? volumeGate;
  Completer<void>? playGate;
  double? appliedVolume;
  double? volumeAtPlay;
  int playCalls = 0;
  Duration position = Duration.zero;

  void initialize() {
    events.add(
      platform.VideoEvent(
        eventType: platform.VideoEventType.initialized,
        duration: const Duration(seconds: 8),
        size: const Size(1920, 1080),
      ),
    );
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(platform.VideoCreationOptions options) async {
    dataSource = options.dataSource;
    return 1;
  }

  @override
  Stream<platform.VideoEvent> videoEventsFor(int playerId) => events.stream;

  @override
  Future<void> setVolume(int playerId, double volume) async {
    requestedVolumes.add(volume);
    await volumeGate?.future;
    appliedVolume = volume;
  }

  @override
  Future<void> play(int playerId) async {
    playCalls++;
    volumeAtPlay = appliedVolume;
    await playGate?.future;
  }

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Future<void> seekTo(int playerId, Duration value) async {
    position = value;
  }

  @override
  Widget buildViewWithOptions(platform.VideoViewOptions options) {
    return const SizedBox.expand();
  }

  @override
  Future<void> dispose(int playerId) => events.close();
}
