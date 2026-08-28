import 'package:aumazing/features/splash/auth/widgets/sound_preferences_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
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
          home: const Scaffold(
            body: SingleChildScrollView(child: _Host()),
          ),
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
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(Row),
        ),
        matching: find.byType(Switch),
      );

  testWidgets('every music style can be chosen and is heard immediately',
      (tester) async {
    final audio = await pumpStep(tester);

    for (final category in kBgmCategories) {
      await tester.tap(find.text(category.label));
      await tester.pumpAndSettle();

      expect(valueOf(tester).musicCategory, category.key,
          reason: '${category.key} did not reach the saved value');
      expect(audio.lastCategoryPlayed, category.key,
          reason: 'the parent must hear the style they just tapped');
    }
  });

  testWidgets('every shipped track is reachable and playable', (tester) async {
    final audio = await pumpStep(tester);

    for (final category in kBgmCategories) {
      // Tracks stay collapsed until the parent asks for them, so the list
      // opens as six calm choices rather than thirty.
      expect(find.text(category.tracks.first.title), findsNothing,
          reason: '${category.key} should start collapsed');

      await tester.tap(find.byKey(ValueKey('bgm-expand-${category.key}')));
      await tester.pumpAndSettle();

      for (final track in category.tracks) {
        expect(find.text(track.title), findsOneWidget,
            reason: '${track.file} cannot be reached during setup');
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

  testWidgets('auditioning a track does not change the chosen style',
      (tester) async {
    final audio = await pumpStep(tester);

    final other = kBgmCategories.firstWhere((c) => c.key != kDefaultBgmCategory);
    await tester.tap(find.byKey(ValueKey('bgm-expand-${other.key}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(other.tracks.first.title));
    await tester.pumpAndSettle();

    expect(audio.lastTrackPlayed, other.trackPath(other.tracks.first));
    expect(valueOf(tester).musicCategory, kDefaultBgmCategory,
        reason: 'previewing must not commit the child to that style');
  });

  testWidgets('switching language moves the voice to that language\'s default',
      (tester) async {
    await pumpStep(tester);

    expect(valueOf(tester).voicePack.languageSlug, GameLanguage.english.slug);

    await tester.tap(find.text(GameLanguage.cebuano.label));
    await tester.pumpAndSettle();

    // Audio and on-screen text must never drift apart: a pack from the old
    // language may not survive the switch.
    expect(valueOf(tester).language, GameLanguage.cebuano);
    expect(valueOf(tester).voicePack.languageSlug, GameLanguage.cebuano.slug);
    expect(valueOf(tester).voicePack.id,
        defaultVoicePackForLanguage(GameLanguage.cebuano.slug).id);
  });

  testWidgets('turning music off stops playback and keeps the chosen style',
      (tester) async {
    final audio = await pumpStep(tester);

    final style = kBgmCategories.firstWhere((c) => c.key != kDefaultBgmCategory);
    await tester.tap(find.text(style.label));
    await tester.pumpAndSettle();

    await tester.tap(switchFor('Play background music'));
    await tester.pumpAndSettle();

    expect(valueOf(tester).musicEnabled, isFalse);
    expect(audio.stopped, isTrue);
    // The style list is hidden while music is off, but the choice survives so
    // switching music back on does not reset the parent's pick.
    expect(valueOf(tester).musicCategory, style.key);
    expect(find.text(style.description), findsNothing);
  });

  testWidgets('lays out on a phone in portrait without overflowing',
      (tester) async {
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

  @override
  Future<void> playCategoryMusic(String? categoryKey,
      {bool restart = false}) async {
    final category = bgmCategoryOrDefault(categoryKey);
    lastCategoryPlayed = category.key;
    lastTrackPlayed = category.trackPath(category.tracks.first);
    stopped = false;
  }

  @override
  Future<void> playCategoryTrack(BgmCategory category, BgmTrack track) async {
    lastTrackPlayed = category.trackPath(track);
  }

  @override
  String? get currentTrack => lastTrackPlayed;

  @override
  Future<void> stopMusic() async {
    stopped = true;
  }

  @override
  AudioConfig get config => AudioConfig.defaults;

  @override
  void updateConfig(AudioConfig config) {}

  @override
  Future<void> playButtonTap() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
