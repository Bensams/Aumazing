import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/settings/settings_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The parent can use category shuffle, an exact track, or a 3–5 track Custom
/// Mix. These tests pin that every shipped track is reachable and that the
/// speaker control auditions without changing the saved choice.
void main() {
  final profile = ChildProfile(
    id: 'child-1',
    userId: 'user-1',
    displayName: 'Test',
    birthDate: DateTime(2022, 4, 20),
    avatar: 'bear',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  Future<_FakeAudioService> openAudioSettings(
    WidgetTester tester, {
    required _TestChildProvider childProvider,
  }) async {
    final audio = _FakeAudioService();
    // Tall enough that all six styles and an expanded track list fit without
    // scrolling, so taps do not need to hunt for off-screen widgets.
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChildProvider>.value(value: childProvider),
          Provider<AudioService>.value(value: audio),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SettingsScreen(
            authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    expect(
      find.text('Music Style'),
      findsOneWidget,
      reason: 'the picker should be on the Audio settings page',
    );
    return audio;
  }

  testWidgets('every shipped track is reachable and playable', (tester) async {
    final childProvider = _TestChildProvider(profile);
    final audio = await openAudioSettings(tester, childProvider: childProvider);

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
          reason: '${track.file} cannot be reached by a parent',
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

    expect(audio.lastTrackPlayed, isNotNull);
  });

  testWidgets('selecting persists and previewing stays non-persistent', (
    tester,
  ) async {
    final childProvider = _TestChildProvider(profile);
    final audio = await openAudioSettings(tester, childProvider: childProvider);

    // Expand a category the child is NOT set to and select one exact track.
    final other = kBgmCategories.firstWhere(
      (c) => c.key != kDefaultBgmCategory,
    );
    await tester.tap(find.byKey(ValueKey('bgm-expand-${other.key}')));
    await tester.pumpAndSettle();
    final selected = other.tracks.first;
    await tester.tap(find.text(selected.title));
    await tester.pumpAndSettle();

    expect(audio.lastTrackPlayed, other.trackPath(selected));
    expect(childProvider.savedCategory, other.key);
    expect(childProvider.profile?.musicTrack, other.trackPath(selected));

    // The dedicated speaker control previews another track without changing
    // the saved exact selection.
    await tester.tap(
      find.byKey(ValueKey('settings-bgm-preview-${other.tracks.last.title}')),
    );
    await tester.pumpAndSettle();
    expect(childProvider.savedCategory, other.key);
    expect(childProvider.profile?.musicTrack, other.trackPath(selected));
  });

  testWidgets('Custom Mix selects three tracks across categories', (
    tester,
  ) async {
    final childProvider = _TestChildProvider(profile);
    final audio = await openAudioSettings(tester, childProvider: childProvider);

    await tester.tap(
      find.byKey(const ValueKey('settings-bgm-custom-mix-expand')),
    );
    await tester.pumpAndSettle();

    final choices = <(BgmCategory, BgmTrack)>[
      (kBgmCategories[0], kBgmCategories[0].tracks[0]),
      (kBgmCategories[2], kBgmCategories[2].tracks[1]),
      (kBgmCategories[5], kBgmCategories[5].tracks[2]),
    ];
    for (final (category, track) in choices) {
      final row = find.byKey(
        ValueKey('settings-bgm-mix-${category.key}-${track.file}'),
      );
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
    }

    expect(childProvider.profile?.musicCategory, kCustomMixBgmCategory);
    expect(childProvider.profile?.musicTracks, hasLength(3));
    expect(audio.lastTrackPlayed, isNotNull);

    final categoryRow = find.byKey(
      ValueKey('settings-bgm-category-${kBgmCategories[1].key}'),
    );
    expect(categoryRow, findsOneWidget);
    await tester.ensureVisible(categoryRow);
    await tester.tap(categoryRow, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(childProvider.profile?.musicCategory, kBgmCategories[1].key);
    expect(childProvider.profile?.musicTrack, isNull);
    expect(childProvider.profile?.musicTracks, isNull);
  });
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider(this._profile)
    : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  ChildProfile _profile;

  /// The category actually persisted, or null if nothing was saved.
  String? savedCategory;

  @override
  ChildProfile? get profile => _profile;

  @override
  String get musicCategory => _profile.musicCategory;

  @override
  String? get musicTrack => _profile.musicTrack;

  @override
  List<String>? get musicTracks => _profile.musicTracks;

  @override
  bool get musicEnabled => _profile.musicEnabled;

  @override
  double get musicVolume => _profile.musicVolume;

  @override
  bool get hasProfile => true;

  @override
  Future<void> updateComfortSettings({
    bool? musicEnabled,
    double? musicVolume,
    String? musicCategory,
    double? sfxVolume,
    bool? vibrationEnabled,
    double? animationIntensity,
    double? promptSpeed,
    bool? sensoryPreferencesSet,
  }) async {
    if (musicCategory != null) {
      savedCategory = musicCategory;
      _profile = _profile.copyWith(musicCategory: musicCategory);
    }
    notifyListeners();
  }

  @override
  Future<void> updateMusicSelection({
    String? musicCategory,
    String? musicTrack,
    List<String>? musicTracks,
    bool clearTrack = false,
    bool clearTracks = false,
  }) async {
    _profile = _profile.copyWith(
      musicCategory: musicCategory,
      musicTrack: musicTrack,
      clearMusicTrack: clearTrack,
      musicTracks: musicTracks,
      clearMusicTracks: clearTracks,
    );
    savedCategory = _profile.musicCategory;
    notifyListeners();
  }
}

class _FakeAudioService implements AudioService {
  String? lastTrackPlayed;

  @override
  Future<void> playCategoryTrack(BgmCategory category, BgmTrack track) async {
    lastTrackPlayed = category.trackPath(track);
  }

  @override
  Future<void> playConfiguredMusic({
    required String? categoryKey,
    String? trackPath,
    bool restart = false,
  }) async {
    lastTrackPlayed = trackPath;
  }

  @override
  Future<void> playConfiguredMix(
    List<String> trackPaths, {
    bool restart = false,
  }) async {
    final valid = validBgmTrackPaths(trackPaths);
    lastTrackPlayed = valid.isEmpty ? null : valid.first;
  }

  @override
  Future<void> playCategoryMusic(
    String? categoryKey, {
    bool restart = false,
  }) async {
    final category = bgmCategoryOrDefault(categoryKey);
    lastTrackPlayed = category.trackPath(category.tracks.first);
  }

  @override
  String? get currentTrack => lastTrackPlayed;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSupabaseAuthClient implements SupabaseAuthClient {
  @override
  Session? get currentSession => null;

  @override
  User? get currentUser => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
