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

/// The parent picks a *style*, but they need to be able to hear each individual
/// track before committing their child to one. These tests pin that every
/// shipped track is reachable and playable from Settings -> Audio, and that
/// auditioning does not quietly change the child's saved choice.
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

  Future<_FakeAudioService> openAudioSettings(WidgetTester tester,
      {required _TestChildProvider childProvider}) async {
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
    expect(find.text('Music Style'), findsOneWidget,
        reason: 'the picker should be on the Audio settings page');
    return audio;
  }

  testWidgets('every shipped track is reachable and playable', (tester) async {
    final childProvider = _TestChildProvider(profile);
    final audio = await openAudioSettings(tester, childProvider: childProvider);

    for (final category in kBgmCategories) {
      // Tracks stay collapsed until the parent asks for them, so the list
      // opens as six calm choices rather than thirty.
      expect(find.text(category.tracks.first.title), findsNothing,
          reason: '${category.key} should start collapsed');

      await tester.tap(find.byKey(ValueKey('bgm-expand-${category.key}')));
      await tester.pumpAndSettle();

      for (final track in category.tracks) {
        expect(find.text(track.title), findsOneWidget,
            reason: '${track.file} cannot be reached by a parent');
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

  testWidgets('auditioning does not change the saved style', (tester) async {
    final childProvider = _TestChildProvider(profile);
    final audio = await openAudioSettings(tester, childProvider: childProvider);

    // Expand and preview a category the child is NOT set to.
    final other = kBgmCategories.firstWhere((c) => c.key != kDefaultBgmCategory);
    await tester.tap(find.byKey(ValueKey('bgm-expand-${other.key}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(other.tracks.first.title));
    await tester.pumpAndSettle();

    expect(audio.lastTrackPlayed, other.trackPath(other.tracks.first));
    expect(childProvider.savedCategory, isNull,
        reason: 'previewing must not commit the child to that style');

    // Tapping the row itself is what commits.
    await tester.tap(find.text(other.label));
    await tester.pumpAndSettle();
    expect(childProvider.savedCategory, other.key);
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
}

class _FakeAudioService implements AudioService {
  String? lastTrackPlayed;

  @override
  Future<void> playCategoryTrack(BgmCategory category, BgmTrack track) async {
    lastTrackPlayed = category.trackPath(track);
  }

  @override
  Future<void> playCategoryMusic(String? categoryKey,
      {bool restart = false}) async {
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
