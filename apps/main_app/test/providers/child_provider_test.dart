import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/services/local_db_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('loadProfile leaves profile null when no local child exists', () async {
    final provider = ChildProvider(
      localDb: _FakeLocalDbService(),
      authService: AuthService(
        supabaseAuth: _FakeSupabaseAuthClient(
          currentUser: const User(
            id: 'user-1',
            appMetadata: {},
            userMetadata: {
              'child_name': 'Legacy Name',
              'child_age': 5,
              'child_avatar': 'bear',
            },
            aud: 'authenticated',
            createdAt: '2026-04-20T00:00:00Z',
          ),
        ),
      ),
    );

    await provider.loadProfile();

    expect(provider.profile, isNull);
    expect(provider.hasProfile, isFalse);
  });
}

class _FakeLocalDbService extends LocalDbService {
  @override
  Future<ChildProfile?> getChildProfile(String userId) async => null;
}

class _FakeSupabaseAuthClient implements SupabaseAuthClient {
  _FakeSupabaseAuthClient({this.currentUser});

  @override
  final User? currentUser;

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
