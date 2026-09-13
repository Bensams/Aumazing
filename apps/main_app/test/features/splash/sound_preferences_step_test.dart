import 'package:aumazing/features/splash/auth/child_profile_setup_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/features/splash/auth/widgets/sound_preferences_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

/// A parent sets the child's sound world up during profile creation, before
/// the first session ever runs. These tests pin that the choices reach the
/// value the setup screen saves, and that auditioning a style is what the
/// parent hears.
void main() {
  Future<_FakeAudioService> pumpStep(WidgetTester tester) async {
    final audio = _FakeAudioService();
    // Tall enough that every style and both toggles fit without scrolling.
    await tester.binding.setSurfaceSize(const Size(900, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AudioService>.value(value: audio),
          Provider<HapticService>.value(value: HapticService()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: SingleChildScrollView(child: _Host())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return audio;
  }

  SoundPreferences valueOf(WidgetTester tester) =>
      tester.state<_HostState>(find.byType(_Host)).value;

  /// The switch sitting in the row labelled [label].
  Finder switchFor(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
    matching: find.byType(Switch),
  );

  testWidgets('every music style can be chosen and is heard immediately', (
    tester,
  ) async {
    final audio = await pumpStep(tester);
    expect(
      tester.getTopLeft(find.text('Background Music')).dy,
      lessThan(tester.getTopLeft(find.text('Language')).dy),
    );
    expect(
      tester.getTopLeft(find.text(kBgmCategories.last.label)).dy,
      lessThan(tester.getTopLeft(find.text('Language')).dy),
    );
    // A different child's mute/volume must not silently disable setup previews.
    audio.updateConfig(
      audio.config.copyWith(musicEnabled: false, musicVolume: 0),
    );

    for (final category in kBgmCategories) {
      await tester.tap(find.text(category.label));
      await tester.pumpAndSettle();

      expect(
        valueOf(tester).musicCategory,
        category.key,
        reason: '${category.key} did not reach the saved value',
      );
      expect(
        audio.lastCategoryPlayed,
        category.key,
        reason: 'the parent must hear the style they just tapped',
      );
      expect(audio.config.musicEnabled, isTrue);
      expect(audio.config.musicVolume, valueOf(tester).musicVolume);
    }
  });

  testWidgets('every shipped track is reachable and playable', (tester) async {
    final audio = await pumpStep(tester);

    for (final category in kBgmCategories) {
      // Tracks stay collapsed until the parent asks for them, so the list
      // opens as six calm choices rather than thirty.
      expect(
        find.text(category.tracks.first.title),
        findsNothing,
        reason: '${category.key} should start collapsed',
      );

      await tester.tap(find.byKey(ValueKey('bgm-expand-${category.key}')));
      await tester.pumpAndSettle();

      for (final track in category.tracks) {
        expect(
          find.text(track.title),
          findsOneWidget,
          reason: '${track.file} cannot be reached during setup',
        );
      }

      // Playing one must play that exact track, not a random pick.
      final track = category.tracks.last;
      await tester.tap(find.text(track.title));
      await tester.pumpAndSettle();
      expect(audio.lastTrackPlayed, category.trackPath(track));

      await tester.tap(find.byKey(ValueKey('bgm-expand-${category.key}')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('selecting a track persists it and speaker preview is separate', (
    tester,
  ) async {
    final audio = await pumpStep(tester);

    final other = kBgmCategories.firstWhere(
      (c) => c.key != kDefaultBgmCategory,
    );
    await tester.tap(find.byKey(ValueKey('bgm-expand-${other.key}')));
    await tester.pumpAndSettle();
    final track = other.tracks.first;
    await tester.tap(find.text(track.title));
    await tester.pumpAndSettle();

    expect(audio.lastTrackPlayed, other.trackPath(track));
    expect(
      valueOf(tester).musicCategory,
      other.key,
      reason: 'selecting a track must commit its category',
    );
    expect(valueOf(tester).musicTrack, other.trackPath(track));

    // The speaker button auditions another track without changing the saved
    // exact choice.
    await tester.tap(
      find.byKey(ValueKey('bgm-preview-${other.tracks.last.title}')),
    );
    await tester.pumpAndSettle();
    expect(audio.lastTrackPlayed, other.trackPath(other.tracks.last));
    expect(valueOf(tester).musicTrack, other.trackPath(track));
  });

  testWidgets('custom mix accepts three to five tracks across styles', (
    tester,
  ) async {
    final audio = await pumpStep(tester);
    await tester.tap(find.byKey(const ValueKey('bgm-custom-mix-expand')));
    await tester.pumpAndSettle();

    final choices = <(BgmCategory, BgmTrack)>[
      (kBgmCategories[0], kBgmCategories[0].tracks[0]),
      (kBgmCategories[2], kBgmCategories[2].tracks[1]),
      (kBgmCategories[5], kBgmCategories[5].tracks[2]),
    ];
    for (final (category, track) in choices) {
      await tester.tap(
        find.byKey(ValueKey('bgm-mix-track-${category.key}-${track.file}')),
      );
      await tester.pumpAndSettle();
    }

    expect(valueOf(tester).musicCategory, kCustomMixBgmCategory);
    expect(valueOf(tester).musicTracks, hasLength(3));
    expect(audio.lastTrackPlayed, isNotNull);

    // A sixth selection is ignored once the five-track limit is reached.
    for (final index in [3, 4]) {
      final category = kBgmCategories[index];
      final track = category.tracks.first;
      await tester.tap(
        find.byKey(ValueKey('bgm-mix-track-${category.key}-${track.file}')),
      );
      await tester.pumpAndSettle();
    }
    expect(valueOf(tester).musicTracks, hasLength(5));
    final sixthCategory = kBgmCategories[1];
    final sixthTrack = sixthCategory.tracks[1];
    await tester.tap(
      find.byKey(
        ValueKey('bgm-mix-track-${sixthCategory.key}-${sixthTrack.file}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(valueOf(tester).musicTracks, hasLength(5));
  });

  testWidgets(
    'switching language moves the voice to that language\'s default',
    (tester) async {
      await pumpStep(tester);

      expect(valueOf(tester).voicePack.languageSlug, GameLanguage.english.slug);

      await tester.tap(find.text(GameLanguage.cebuano.label));
      await tester.pumpAndSettle();

      // Audio and on-screen text must never drift apart: a pack from the old
      // language may not survive the switch.
      expect(valueOf(tester).language, GameLanguage.cebuano);
      expect(valueOf(tester).voicePack.languageSlug, GameLanguage.cebuano.slug);
      expect(
        valueOf(tester).voicePack.id,
        defaultVoicePackForLanguage(GameLanguage.cebuano.slug).id,
      );
    },
  );

  testWidgets('turning music off stops playback and keeps the chosen style', (
    tester,
  ) async {
    final audio = await pumpStep(tester);

    final style = kBgmCategories.firstWhere(
      (c) => c.key != kDefaultBgmCategory,
    );
    await tester.tap(find.text(style.label));
    await tester.pumpAndSettle();

    await tester.tap(switchFor('Play background music'));
    await tester.pumpAndSettle();

    expect(valueOf(tester).musicEnabled, isFalse);
    expect(audio.stopped, isTrue);
    // Muting keeps all six choices discoverable without restarting playback.
    expect(valueOf(tester).musicCategory, style.key);
    for (final category in kBgmCategories) {
      expect(find.text(category.label), findsOneWidget);
    }
    final other = kBgmCategories.firstWhere((c) => c.key != style.key);
    await tester.tap(find.text(other.label));
    await tester.pumpAndSettle();
    expect(valueOf(tester).musicCategory, other.key);
    expect(valueOf(tester).musicEnabled, isFalse);
    expect(audio.lastCategoryPlayed, style.key);
    expect(audio.stopped, isTrue);

    await tester.tap(switchFor('Play background music'));
    await tester.pumpAndSettle();
    expect(valueOf(tester).musicCategory, other.key);
    expect(audio.lastCategoryPlayed, other.key);
    expect(audio.config.musicEnabled, isTrue);
  });

  for (final musicEnabled in [true, false]) {
    testWidgets(
      'setup keeps music through Back/Continue and saves enabled=$musicEnabled',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final children = _SavingChildProvider();
        await tester.binding.setSurfaceSize(const Size(900, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final haptic = HapticService();
        final audio = _FakeAudioService();
        audio.updateConfig(
          audio.config.copyWith(musicEnabled: false, musicVolume: .12),
        );
        await tester.binding.setSurfaceSize(const Size(900, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<AudioService>.value(value: audio),
              Provider<HapticService>.value(value: haptic),
              ChangeNotifierProvider<ChildProvider>.value(value: children),
            ],
            child: MaterialApp(
              home: Builder(
                builder:
                    (context) => Scaffold(
                      body: TextButton(
                        onPressed:
                            () => Navigator.of(context).push<ChildProfile>(
                              MaterialPageRoute<ChildProfile>(
                                builder:
                                    (_) =>
                                        const ChildProfileSetupScreen.addAnother(),
                              ),
                            ),
                        child: const Text('Add child'),
                      ),
                    ),
              ),
            ),
          ),
        );

        Future<void> tapVisible(Finder target) async {
          await tester.ensureVisible(target);
          await tester.tap(target);
          // The rewards step contains ongoing animations; only advance enough
          // frames for the interaction and route transition to complete.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }

        await tapVisible(find.text('Add child'));
        await tester.enterText(find.byType(TextFormField), 'Sam');
        await tapVisible(find.text('Boy'));
        await tapVisible(find.byKey(const Key('birth-date-button')));
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tapVisible(find.text('OK'));
        await tapVisible(find.text('Continue'));
        expect(find.text('Music, voice & sound'), findsOneWidget);

        final style = kBgmCategories.firstWhere(
          (category) => category.key != kDefaultBgmCategory,
        );
        await tapVisible(find.text(style.label));
        if (!musicEnabled) {
          await tapVisible(switchFor('Play background music'));
        }

        await tapVisible(find.text('Continue'));
        expect(find.text('Save Child Profile'), findsOneWidget);
        await tapVisible(find.text('Go Back'));
        await tapVisible(find.text('Go Back'));
        await tapVisible(find.text('Continue'));
        final restored =
            tester
                .widget<SoundPreferencesStep>(find.byType(SoundPreferencesStep))
                .value;
        expect(restored.musicCategory, style.key);
        expect(restored.musicEnabled, musicEnabled);
        expect(
          tester.widget<Switch>(switchFor('Play background music')).value,
          musicEnabled,
        );

        await tapVisible(find.text('Continue'));
        await tapVisible(find.text('Save Child Profile'));
        expect(children.saved?.musicCategory, style.key);
        expect(audio.config.musicEnabled, isFalse);
        expect(audio.config.musicVolume, .12);
        expect(audio.playing, isFalse);
        expect(children.saved?.musicEnabled, musicEnabled);
        expect(find.text('Add child'), findsOneWidget);
        expect(find.byType(ChildProfileSetupScreen), findsNothing);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets('lays out on a phone in portrait without overflowing', (
    tester,
  ) async {
    // Setup runs on whatever device the parent has; a row that only fits a
    // tablet shows up here as a RenderFlex overflow exception.
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AudioService>.value(value: _FakeAudioService()),
          Provider<HapticService>.value(value: HapticService()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: _Host())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Music Style'), findsOneWidget);
  });

  testWidgets('prompt text can be turned off for pre-readers', (tester) async {
    await pumpStep(tester);

    expect(valueOf(tester).showTextPrompts, isTrue);
    await tester.tap(switchFor('Show instruction text'));
    await tester.pumpAndSettle();
    expect(valueOf(tester).showTextPrompts, isFalse);
  });
}

/// Stands in for the setup screen: owns the value and feeds it back down.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  SoundPreferences value = SoundPreferences.initial();

  @override
  Widget build(BuildContext context) {
    return SoundPreferencesStep(
      value: value,
      onChanged: (next) => setState(() => value = next),
    );
  }
}

class _FakeAudioService implements AudioService {
  String? lastCategoryPlayed;
  String? lastTrackPlayed;
  bool stopped = false;
  bool playing = false;
  @override
  bool get isMusicPlaying => playing;

  @override
  Future<void> playMusic(String trackName) async {
    lastTrackPlayed = trackName;
    playing = true;
    stopped = false;
  }

  @override
  Future<void> playCategoryMusic(
    String? categoryKey, {
    bool restart = false,
  }) async {
    if (!config.musicEnabled) return;
    final category = bgmCategoryOrDefault(categoryKey);
    lastCategoryPlayed = category.key;
    lastTrackPlayed = category.trackPath(category.tracks.first);
    this.category = category.key;
    playing = true;
    stopped = false;
  }

  @override
  Future<void> playCategoryTrack(BgmCategory category, BgmTrack track) async {
    if (!config.musicEnabled) return;
    this.category = category.key;
    lastTrackPlayed = category.trackPath(track);
  }

  @override
  Future<void> playConfiguredMusic({
    required String? categoryKey,
    String? trackPath,
    bool restart = false,
  }) async {
    if (!config.musicEnabled) return;
    final match = trackPath == null ? null : bgmTrackByPath(trackPath);
    if (match == null) {
      await playCategoryMusic(categoryKey, restart: restart);
      return;
    }
    category = match.$1.key;
    lastCategoryPlayed = match.$1.key;
    lastTrackPlayed = trackPath;
    playing = true;
    stopped = false;
  }

  @override
  Future<void> playConfiguredMix(
    List<String> trackPaths, {
    bool restart = false,
  }) async {
    if (!config.musicEnabled) return;
    final valid = validBgmTrackPaths(trackPaths);
    if (valid.isEmpty) return;
    category = kCustomMixBgmCategory;
    lastCategoryPlayed = kCustomMixBgmCategory;
    lastTrackPlayed = valid.first;
    playing = true;
    stopped = false;
  }

  @override
  String? get currentTrack => lastTrackPlayed;

  @override
  Future<void> stopMusic() async {
    stopped = true;
    playing = false;
  }

  @override
  AudioConfig config = AudioConfig.defaults;

  /// Mirrors the real service: category bookkeeping follows the track.
  String? category;

  @override
  String? get currentCategory => category;

  @override
  void setCurrentCategory(String? categoryKey) => category = categoryKey;

  @override
  void updateConfig(AudioConfig config) => this.config = config;

  @override
  Future<void> playButtonTap() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SavingChildProvider extends ChangeNotifier implements ChildProvider {
  ChildProfile? saved;

  @override
  ChildProfile? get profile => null;

  @override
  String? get activeChildId => null;

  @override
  Future<ChildProfile> addChild({
    required String displayName,
    required DateTime birthDate,
    required String avatar,
    ChildSex? sex,
    bool musicEnabled = true,
    double musicVolume = 0.5,
    String musicCategory = kDefaultBgmCategory,
    String? musicTrack,
    List<String>? musicTracks,
    double sfxVolume = 0.7,
    bool vibrationEnabled = true,
    double promptSpeed = 1.0,
    bool sensoryPreferencesSet = false,
    RewardPreference rewardPreference = RewardPreference.bubbles,
    bool useRandomReward = false,
    String characterId = 'bps',
    bool makeActive = false,
  }) async {
    final now = DateTime.now();
    return saved = ChildProfile(
      id: 'new-child',
      userId: 'parent',
      displayName: displayName,
      birthDate: birthDate,
      avatar: avatar,
      musicEnabled: musicEnabled,
      musicVolume: musicVolume,
      musicCategory: musicCategory,
      musicTrack: musicTrack,
      musicTracks: musicTracks,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> applyInitialPreferences({
    required String childId,
    required GameLanguage language,
    required String voicePackId,
  }) async {}

  @override
  Future<void> setShowTextPrompts(bool value) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
