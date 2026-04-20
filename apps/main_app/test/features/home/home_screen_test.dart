import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/home/home_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/progress_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final profile = ChildProfile(
    id: 'child-1',
    userId: 'user-1',
    name: 'Test',
    age: 5,
    avatar: '🐻',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  testWidgets(
    'home screen defers provider loading until after the first frame',
    (tester) async {
      final authService = AuthService(supabaseAuth: _FakeSupabaseAuthClient());
      final childProvider = _TestChildProvider(
        initialProfile: profile,
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
    },
  );

  testWidgets(
    'settings and bind account dialogs stay stable in compact layout',
    (tester) async {
      final authService = AuthService(supabaseAuth: _FakeSupabaseAuthClient());
      authService.initializeGuestMode();

      await tester.binding.setSurfaceSize(const Size(640, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          authService: authService,
          childProvider: _TestChildProvider(initialProfile: profile),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Bind Account'));
      await tester.tap(find.text('Bind Account'));
      await tester.pumpAndSettle();
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
        _buildTestApp(
          authService: authService,
          childProvider: _TestChildProvider(initialProfile: profile),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bind Account').first);
      await tester.pumpAndSettle();

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
        _buildTestApp(
          authService: authService,
          childProvider: _TestChildProvider(initialProfile: profile),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bind Account').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bind with Email'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
      expect(find.text('Bind with Google'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _buildTestApp({
  required AuthService authService,
  required ChildProvider childProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>.value(value: childProvider),
      ChangeNotifierProvider<AssessmentProvider>(
        create: (_) => _TestAssessmentProvider(),
      ),
      ChangeNotifierProvider<ProgressProvider>(
        create: (_) => _TestProgressProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: HomeScreen(authService: authService),
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
    bool? vibrationEnabled,
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

  @override
  int get completedModules => 0;

  @override
  int get totalSessions => _sessions.length;

  @override
  List<GameplaySession> get recentSessions => _sessions;

  @override
  Future<void> loadProgress(String childId) async {}
}

class _FakeSupabaseAuthClient implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Future<AuthResponse> signInAnonymously() {
    throw UnimplementedError();
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
