import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

import 'mock_audio_channels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAudioChannels mock;

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    mock = MockAudioChannels(messenger);
    messenger.setMockMethodCallHandler(
      MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => call.method == 'create' ? null : 1,
    );
    messenger.setMockMethodCallHandler(
      MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
  });

  test(
    'plays the saved exact track and keeps its category bookkeeping',
    () async {
      final audio = AudioService();
      addTearDown(audio.dispose);
      final category = bgmCategoryByKey('gentle_playful')!;
      final track = category.tracks.last;
      final path = category.trackPath(track);

      await audio.playConfiguredMusic(
        categoryKey: category.key,
        trackPath: path,
      );

      expect(audio.currentCategory, category.key);
      expect(audio.currentTrack, path);

      // A restart starts the same configured asset again rather than selecting
      // a different track from the category.
      await audio.playConfiguredMusic(
        categoryKey: category.key,
        trackPath: path,
        restart: true,
      );
      expect(audio.currentCategory, category.key);
      expect(audio.currentTrack, path);
      expect(mock.lastResumedPlayer, isNotNull);
    },
  );

  test(
    'null, unknown, and mismatched paths use category shuffle safely',
    () async {
      final audio = AudioService();
      addTearDown(audio.dispose);
      final category = bgmCategoryByKey('focus_minimal')!;

      for (final path in <String?>[
        null,
        'bgm/focus_minimal/removed.ogg',
        'bgm/gentle_playful/happy_marimba.ogg',
      ]) {
        await audio.playConfiguredMusic(
          categoryKey: category.key,
          trackPath: path,
          restart: true,
        );
        expect(audio.currentCategory, category.key);
        expect(
          category.tracks.map(category.trackPath),
          contains(audio.currentTrack),
        );
      }
    },
  );

  test('muted playback leaves the saved choice untouched and silent', () async {
    final category = bgmCategoryByKey('filipino_calm')!;
    final path = category.trackPath(category.tracks.first);
    final audio = AudioService(config: const AudioConfig(musicEnabled: false));
    addTearDown(audio.dispose);

    await audio.playConfiguredMusic(categoryKey: category.key, trackPath: path);

    expect(audio.currentCategory, isNull);
    expect(audio.currentTrack, isNull);
  });

  test('replaying the same preview keeps category bookkeeping', () async {
    final audio = AudioService();
    addTearDown(audio.dispose);
    final category = bgmCategoryByKey('nature_ambient')!;
    final track = category.tracks.first;

    await audio.playCategoryTrack(category, track);
    await audio.playCategoryTrack(category, track);

    expect(audio.currentCategory, category.key);
    expect(audio.currentTrack, category.trackPath(track));
  });

  test('Custom Mix chooses one valid track and records custom_mix', () async {
    final audio = AudioService();
    addTearDown(audio.dispose);
    const mix = <String>[
      'bgm/soft_relaxing/breathing_pad.ogg',
      'bgm/nature_ambient/slow_ocean.ogg',
      'bgm/filipino_calm/bamboo_breeze.ogg',
      'bgm/removed/no-longer-shipped.ogg',
    ];

    await audio.playConfiguredMix(mix, restart: true);

    expect(audio.currentCategory, kCustomMixBgmCategory);
    expect(validBgmTrackPaths(mix), contains(audio.currentTrack));
  });

  test(
    'an empty or retired Custom Mix falls back to category shuffle',
    () async {
      final audio = AudioService();
      addTearDown(audio.dispose);

      await audio.playConfiguredMix(const ['bgm/removed/deleted.ogg']);

      expect(audio.currentCategory, kDefaultBgmCategory);
      final category = bgmCategoryByKey(kDefaultBgmCategory)!;
      expect(
        category.tracks.map(category.trackPath),
        contains(audio.currentTrack),
      );
    },
  );
}
