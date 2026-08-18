import 'dart:async';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/core/services/sync_service.dart';
import 'package:aumazing/features/home/home_screen.dart' show HomeScreen;
import 'package:aumazing/features/settings/bind_account_modal.dart';
import 'package:aumazing/features/settings/settings_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/stars_provider.dart';
import 'package:aumazing/providers/progress_provider.dart';
import 'package:aumazing/services/tour_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _profile = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Test',
  birthDate: DateTime(2022, 4, 20),
  avatar: 'bear',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  group('refreshing when a sync lands', () {
    /// Sessions synced down while the parent is already on the dashboard
    /// used to stay invisible: progress is read once per child load, and
    /// nothing re-queried it. The banner listened; the data did not.
    testWidgets('a completed pass that brought rows down re-queries', (
      tester,
    ) async {
      final controller = StreamController<SyncState>.broadcast();
      addTearDown(controller.close);
      final progress = _TestProgressProvider();

      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
          childProvider: _TestChildProvider(initialProfile: _profile),
          progressProvider: progress,
          syncStates: controller.stream,
        ),
      );
      await tester.pump();
      final loadsAfterOpen = progress.progressLoads.length;

      controller.add(
        SyncState(
          status: SyncStatusEnum.completed,
          syncedCount: 3,
          timestamp: DateTime(2026, 6, 1),
        ),
      );
      await tester.pump();

      expect(progress.progressLoads.length, loadsAfterOpen + 1);
      expect(progress.progressLoads.last, 'child-1');

      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('a pass with nothing to bring down does not churn', (
      tester,
    ) async {
      final controller = StreamController<SyncState>.broadcast();
      addTearDown(controller.close);
      final progress = _TestProgressProvider();

      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
          childProvider: _TestChildProvider(initialProfile: _profile),
          progressProvider: progress,
          syncStates: controller.stream,
        ),
      );
      await tester.pump();
      final loadsAfterOpen = progress.progressLoads.length;

      // A clean pass, and a pass still in flight: neither has new rows.
      controller.add(
        SyncState(status: SyncStatusEnum.completed, syncedCount: 0),
      );
      controller.add(SyncState(status: SyncStatusEnum.syncing));
      await tester.pump();

      expect(progress.progressLoads.length, loadsAfterOpen);

      await tester.pump(const Duration(milliseconds: 700));
    });
  });

  /// The child plays while the dashboard sits underneath, and HomeScreen's
  /// initState does not run again on pop — so without this the parent came
  /// back to "No activity yet" however much was played. The re-read is a
  /// local database query; no sync and no network are involved.
  testWidgets('returning from a child-facing route re-reads progress', (
    tester,
  ) async {
    final progress = _TestProgressProvider();

    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildTestApp(
        authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
        childProvider: _TestChildProvider(initialProfile: _profile),
        progressProvider: progress,
      ),
    );
    await tester.pump();
    final loadsAfterOpen = progress.progressLoads.length;

    await tester.ensureVisible(find.text('Enter Child Mode'));
    await tester.tap(find.text('Enter Child Mode'));
    await _settleUi(tester);
    // Still the load from opening the dashboard — the re-read belongs on the
    // way back, not on the way in.
    expect(progress.progressLoads.length, loadsAfterOpen);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await _settleUi(tester);

    expect(progress.progressLoads.length, loadsAfterOpen + 1);
    expect(progress.progressLoads.last, 'child-1');

    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets(
    'home screen defers provider loading until after the first frame',
    (tester) async {
      final authService = AuthService(supabaseAuth: _FakeSupabaseAuthClient());
      final childProvider = _TestChildProvider(
        initialProfile: _profile,
        notifyDuringLoad: true,
      );

      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(authService: authService, childProvider: childProvider),
      );
      expect(tester.takeException(), isNull);

      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(childProvider.loadCalls, 1);

      // Let the home screen's delayed music-verification timer fire so no
      // timer outlives the test.
      await tester.pump(const Duration(milliseconds: 700));
    },
  );

  testWidgets('home screen lays out without overflow on a portrait phone', (
    tester,
  ) async {
    final authService = AuthService(supabaseAuth: _FakeSupabaseAuthClient());
    final childProvider = _TestChildProvider(initialProfile: _profile);

    // A phone in portrait — the parent orientation on mobile.
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildTestApp(authService: authService, childProvider: childProvider),
    );
    await _settleUi(tester);
    expect(tester.takeException(), isNull);

    // The side panel is replaced by the collapsible summary card, which
    // starts collapsed and reveals the quick stats when tapped.
    expect(find.text("Test's Dashboard"), findsOneWidget);
    expect(find.text('Sessions'), findsNothing);

    await tester.tap(find.text("Test's Dashboard"));
    await _settleUi(tester);

    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Assessment'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets(
    'settings and bind account dialogs stay stable in compact layout',
    (tester) async {
      final authService = AuthService(supabaseAuth: _FakeSupabaseAuthClient());
      authService.initializeGuestMode();

      await tester.binding.setSurfaceSize(const Size(640, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildSettingsTestApp(authService: authService));
      await _settleUi(tester);

      expect(find.text('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Bind Account'));
      await tester.tap(find.text('Bind Account'));
      await _settleUi(tester);
      expect(find.text('Bind Account'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bind account modal shows Google and email options before the inline form',
    (tester) async {
      final authService = AuthService(supabaseAuth: _FakeSupabaseAuthClient());
      authService.initializeGuestMode();

      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildBindAccountTestApp(authService: authService),
      );
      await _settleUi(tester);

      expect(find.text('Bind with Google'), findsOneWidget);
      expect(find.text('Bind with Email'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Email'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bind account modal switches to inline email form from the option screen',
    (tester) async {
      final authService = AuthService(supabaseAuth: _FakeSupabaseAuthClient());
      authService.initializeGuestMode();

      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildBindAccountTestApp(authService: authService),
      );
      await _settleUi(tester);

      await tester.tap(find.text('Bind with Email'));
      await _settleUi(tester);

      expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
      expect(find.text('Bind with Google'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the guided tour runs on the first visit and is not repeated after it',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      TourService.instance.resetCache();

      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
          childProvider: _TestChildProvider(initialProfile: _profile),
        ),
      );
      await _settleUi(tester);

      expect(find.textContaining('A quick tour'), findsOneWidget);

      // Step two spotlights the child panel.
      await tester.tap(find.text('Next'));
      await _settleUi(tester);
      expect(find.textContaining('quick stats'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await _settleUi(tester);
      expect(find.textContaining('A quick tour'), findsNothing);
      expect(await TourService.instance.hasSeenParentTour(), isTrue);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 700));
    },
  );

  testWidgets('the help button replays the tour for a parent who has seen it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'parent_dashboard_tour_seen_v1': true,
    });
    TourService.instance.resetCache();

    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildTestApp(
        authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
        childProvider: _TestChildProvider(initialProfile: _profile),
      ),
    );
    await _settleUi(tester);

    expect(find.textContaining('A quick tour'), findsNothing);

    await tester.tap(find.byTooltip('Dashboard guide'));
    await _settleUi(tester);
    expect(find.textContaining('A quick tour'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('the tour explains how to reach child mode and get back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    TourService.instance.resetCache();

    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildTestApp(
        authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
        childProvider: _TestChildProvider(initialProfile: _profile),
      ),
    );
    await _settleUi(tester);

    // Walk forward until the child-mode pair of steps comes up.
    var guard = 0;
    while (find
            .textContaining('hand the device to your child')
            .evaluate()
            .isEmpty &&
        guard++ < 10) {
      await tester.tap(find.text('Next'));
      await _settleUi(tester);
    }
    expect(
      find.textContaining('hand the device to your child'),
      findsOneWidget,
    );

    await tester.tap(find.text('Next'));
    await _settleUi(tester);
    expect(find.textContaining('parent PIN'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 700));
  });
}

Future<void> _settleUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _buildSettingsTestApp({required AuthService authService}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(initialProfile: _profile),
      ),
      Provider<AudioService>(create: (_) => _FakeAudioService()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SettingsScreen(authService: authService)),
    ),
  );
}

Widget _buildBindAccountTestApp({required AuthService authService}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: BindAccountModal(authService: authService)),
  );
}

Widget _buildTestApp({
  required AuthService authService,
  required ChildProvider childProvider,
  ProgressProvider? progressProvider,
  Stream<SyncState>? syncStates,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>.value(value: childProvider),
      ChangeNotifierProvider<StarsProvider>(
        create: (_) => _NoStarsProvider(),
      ),
      ChangeNotifierProvider<AssessmentProvider>(
        create: (_) => _TestAssessmentProvider(),
      ),
      ChangeNotifierProvider<ProgressProvider>.value(
        value: progressProvider ?? _TestProgressProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: HomeScreen(authService: authService, syncStates: syncStates),
    ),
  );
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider({
    required ChildProfile initialProfile,
    this.notifyDuringLoad = false,
  }) : _profile = initialProfile,
       super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  final ChildProfile _profile;
  final bool notifyDuringLoad;
  int loadCalls = 0;
  bool _musicEnabled = true;
  bool _vibrationEnabled = true;

  @override
  ChildProfile? get profile => _profile;

  @override
  bool get musicEnabled => _musicEnabled;

  @override
  bool get vibrationEnabled => _vibrationEnabled;

  @override
  Future<void> loadProfile() async {
    loadCalls += 1;
    if (notifyDuringLoad) {
      notifyListeners();
    }
  }

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
    _musicEnabled = musicEnabled ?? _musicEnabled;
    _vibrationEnabled = vibrationEnabled ?? _vibrationEnabled;
    notifyListeners();
  }
}

class _TestAssessmentProvider extends AssessmentProvider {
  @override
  bool get hasPreAssessment => false;

  @override
  String? get recommendedModuleName => null;

  @override
  int get recommendedLevel => 1;

  @override
  Future<void> loadAssessments(String childId) async {}
}

class _TestProgressProvider extends ProgressProvider {
  final List<GameplaySession> _sessions = const [];

  /// Children whose progress was (re-)queried, in order.
  final List<String> progressLoads = [];

  @override
  int get completedModules => 0;

  @override
  int get totalSessions => _sessions.length;

  @override
  List<GameplaySession> get recentSessions => _sessions;

  @override
  Future<void> loadProgress(String childId) async {
    progressLoads.add(childId);
  }
}

class _FakeAudioService extends AudioService {
  _FakeAudioService() : super(config: const AudioConfig());

  @override
  bool get isMusicPlaying => false;

  @override
  void updateConfig(AudioConfig config) {}

  @override
  Future<void> playMusic(String trackName) async {}

  @override
  Future<void> pauseMusic() async {}

  @override
  Future<void> resumeMusic() async {}

  @override
  Future<void> stopMusic() async {}

  @override
  Future<void> playRandomMusic(List<String> trackNames) async {}

  @override
  Future<void> playCategoryMusic(
    String? categoryKey, {
    bool restart = false,
  }) async {}

  @override
  Future<void> playSfx(String sfxName, {double volumeScale = 1.0}) async {}

  @override
  Future<void> playButtonTap() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeSupabaseAuthClient implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Future<AuthResponse> signInAnonymously() async {
    return AuthResponse(); // Return mock response for testing
  }

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResponse> linkIdentityWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
    String? emailRedirectTo,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UserResponse> updateUser(UserAttributes attributes) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResponse> verifyOTP({
    required OtpType type,
    String? token,
    String? tokenHash,
    String? phone,
    String? email,
    String? redirectTo,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ResendResponse> resend({
    required OtpType type,
    String? email,
    String? phone,
    String? emailRedirectTo,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> resetPasswordForEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResponse> refreshSession([String? refreshToken]) {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {}
}

/// The child lobby reads this for the "got today's star" badge (AUM-285).
/// Nothing here exercises the badge, so it reports nothing earned and never
/// touches a database.
class _NoStarsProvider extends StarsProvider {
  @override
  bool hasEarnedStarToday(String gameId) => false;

  @override
  Future<void> bind(String? childId) async {}

  @override
  Future<void> refresh() async {}
}
