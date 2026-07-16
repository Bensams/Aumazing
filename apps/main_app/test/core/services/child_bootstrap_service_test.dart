import 'dart:async';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/core/services/child_bootstrap_service.dart';
import 'package:aumazing/core/services/connectivity_service.dart';
import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/services/supabase_service.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('bootstrap hydrates SQLite from Supabase when online', () async {
    final localDb = _FakeLocalDbService();
    final service = ChildBootstrapService(
      authService: _FakeAuthService.loggedIn(),
      connectivityService: _FakeConnectivityService(online: true),
      supabaseService: _FakeSupabaseService(
        children: [
          {
            'id': 'child-1',
            'parent_user_id': 'user-1',
            'display_name': 'Mika',
            'birth_date': '2022-04-20',
            'created_at': '2026-04-20T00:00:00Z',
            'updated_at': '2026-04-20T00:00:00Z',
          },
        ],
      ),
      localDbService: localDb,
    );

    final result = await service.bootstrap();

    expect(result.destination, BootstrapDestination.home);
    expect(localDb.upsertedChildren, hasLength(1));
    expect(localDb.upsertedChildren.single.displayName, 'Mika');
    expect(localDb.upsertedChildren.single.birthDate, DateTime(2022, 4, 20));
  });

  test('bootstrap routes legacy local records to child setup while offline', () async {
    final legacyChild = ChildProfile.fromMap({
      'id': 'legacy-child',
      'user_id': 'user-1',
      'name': 'Legacy Child',
      'age': 5,
      'avatar': 'lion',
      'created_at': '2026-04-20T00:00:00.000',
      'updated_at': '2026-04-20T00:00:00.000',
    });
    final service = ChildBootstrapService(
      authService: _FakeAuthService.loggedIn(),
      connectivityService: _FakeConnectivityService(online: false),
      supabaseService: _FakeSupabaseService(children: const []),
      localDbService: _FakeLocalDbService(initialChildren: [legacyChild]),
    );

    final result = await service.bootstrap();

    expect(result.destination, BootstrapDestination.childProfileSetup);
    expect(result.errorMessage, isNotEmpty);
  });

  test('bootstrap uses valid local guest child data while offline', () async {
    final service = ChildBootstrapService(
      authService: _FakeAuthService(loggedIn: false, userId: 'guest-1'),
      connectivityService: _FakeConnectivityService(online: false),
      supabaseService: _FakeSupabaseService(children: const []),
      localDbService: _FakeLocalDbService(
        initialChildren: [
          ChildProfile(
            id: 'child-1',
            userId: 'guest-1',
            displayName: 'Mika',
            birthDate: DateTime(2022, 4, 20),
            avatar: 'lion',
            createdAt: DateTime(2026, 4, 20),
            updatedAt: DateTime(2026, 4, 20),
          ),
        ],
      ),
    );

    final result = await service.bootstrap();

    expect(result.destination, BootstrapDestination.home);
    expect(result.errorMessage, isNull);
  });
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({required this.loggedIn, required this.userId})
    : super(supabaseAuth: _NoopSupabaseAuthClient());

  factory _FakeAuthService.loggedIn() =>
      _FakeAuthService(loggedIn: true, userId: 'user-1');

  final bool loggedIn;
  final String? userId;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  String? get effectiveUserId => userId;

  @override
  Future<void> refreshSession() async {}
}

class _NoopSupabaseAuthClient implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream<AuthState>.empty();

  @override
  Future<AuthResponse> signInAnonymously() => throw UnimplementedError();

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
    String? emailRedirectTo,
    String? captchaToken,
  }) => throw UnimplementedError();

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) => throw UnimplementedError();

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) => throw UnimplementedError();

  @override
  Future<AuthResponse> linkIdentityWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) => throw UnimplementedError();

  @override
  Future<UserResponse> updateUser(UserAttributes attributes) =>
      throw UnimplementedError();

  @override
  Future<AuthResponse> verifyOTP({
    required OtpType type,
    String? token,
    String? tokenHash,
    String? phone,
    String? email,
    String? redirectTo,
    String? captchaToken,
  }) => throw UnimplementedError();

  @override
  Future<ResendResponse> resend({
    required OtpType type,
    String? email,
    String? phone,
    String? emailRedirectTo,
    String? captchaToken,
  }) => throw UnimplementedError();

  @override
  Future<void> resetPasswordForEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) => throw UnimplementedError();

  @override
  Future<AuthResponse> refreshSession([String? refreshToken]) =>
      throw UnimplementedError();

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) =>
      throw UnimplementedError();
}

class _FakeConnectivityService implements ConnectivityService {
  _FakeConnectivityService({required this.online});

  final bool online;

  @override
  bool get isOnline => online;

  @override
  bool get isOffline => !online;

  @override
  Stream<bool> get onConnectivityChanged => const Stream<bool>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkConnectivity() async => online;

  @override
  void dispose() {}
}

class _FakeSupabaseService implements SupabaseService {
  _FakeSupabaseService({required this.children});

  final List<Map<String, dynamic>> children;

  @override
  bool get isAuthenticated => true;

  @override
  String? get currentUserId => 'user-1';

  @override
  Future<List<Map<String, dynamic>>> getChildren(String userId) async => children;

  @override
  Future<void> upsertChild(Map<String, dynamic> data, String id) async {}

  @override
  Future<void> upsertBatch(
    String remoteTable,
    List<Map<String, dynamic>> records,
  ) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchRowsByColumn(
    String remoteTable,
    String column,
    List<String> values,
  ) async => const [];

  @override
  Future<void> upsertAssessmentRun(Map<String, dynamic> data, String id) async {}

  @override
  Future<void> upsertGameSession(Map<String, dynamic> data, String id) async {}

  @override
  Future<void> upsertGameSessionsBatch(List<Map<String, dynamic>> records) async {}

  @override
  Future<void> upsertGameRound(Map<String, dynamic> data, String id) async {}

  @override
  Future<void> upsertGameRoundsBatch(List<Map<String, dynamic>> records) async {}

  @override
  Future<void> upsertSessionEvent(Map<String, dynamic> data, String id) async {}

  @override
  Future<void> upsertCaregiverQuestionnaire(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertAssessmentResult(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertAssessmentResultsBatch(
    List<Map<String, dynamic>> records,
  ) async {}

  @override
  Future<void> upsertModuleRecommendation(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertAssessmentComparison(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertSensoryConsent(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertSensoryRoundMetrics(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<void> upsertSensoryPreferences(
    Map<String, dynamic> data,
    String id,
  ) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchLearningModules() async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchModulePaths() async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchModulePathItems() async => const [];

  @override
  Future<DateTime?> getRemoteUpdatedAt(String table, String id) async => null;

  @override
  Future<void> softDeleteRemote(String table, String id) async {}
}

class _FakeLocalDbService extends LocalDbService {
  _FakeLocalDbService({List<ChildProfile>? initialChildren})
    : _children = [...?initialChildren];

  final List<ChildProfile> _children;
  final List<ChildProfile> upsertedChildren = [];

  @override
  Future<void> upsertChild(
    ChildProfile profile, {
    String? ownerId,
    bool markPending = true,
  }) async {
    _children.removeWhere((child) => child.id == profile.id);
    _children.add(profile);
    upsertedChildren.add(profile);
  }

  @override
  Future<List<ChildProfile>> getChildren({
    String? userId,
    bool includeDeleted = false,
  }) async {
    if (userId == null) return List<ChildProfile>.from(_children);
    return _children.where((child) => child.userId == userId).toList();
  }
}
