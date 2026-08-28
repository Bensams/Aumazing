import 'package:aumazing/core/services/auth_service.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('anonymous Supabase users are treated as guest mode', () {
    final authService = AuthService(
      supabaseAuth: _FakeSupabaseAuthClient(
        currentUser: const User(
          id: 'anon-user',
          appMetadata: {},
          userMetadata: null,
          aud: 'authenticated',
          createdAt: '2026-04-20T00:00:00Z',
          isAnonymous: true,
        ),
      ),
    );

    expect(authService.isGuestMode, isTrue);
  });

  test('guest mode is shared across auth service instances', () {
    final first = AuthService(supabaseAuth: _FakeSupabaseAuthClient());
    final second = AuthService(supabaseAuth: _FakeSupabaseAuthClient());

    final guestId = first.initializeGuestMode();

    expect(second.currentGuestId, guestId);
    expect(second.isGuestMode, isTrue);

    second.clearGuestMode();

    expect(first.currentGuestId, isNull);
    expect(first.isGuestMode, isFalse);
  });

  test('convertAnonymousToPermanent returns bound response identity', () async {
    final supabaseAuth = _FakeSupabaseAuthClient(
      updateUserResponse: UserResponse.fromJson(_boundUserJson('email-user')),
    );
    final authService = AuthService(supabaseAuth: supabaseAuth);
    final guestId = authService.initializeGuestMode();

    final response = await authService.convertAnonymousToPermanent(
      email: 'bound@example.com',
      password: 'password123',
    );

    expect(response.user?.id, 'email-user');
    expect(response.user?.id, isNot(guestId));
    expect(authService.isGuestMode, isFalse);
    expect(authService.isBoundAccount, isTrue);
    expect(authService.effectiveUserId, 'email-user');
  });

  test('bindAnonymousWithGoogle returns bound response identity', () async {
    final googleAuth = _FakeGoogleAuthClient();
    final supabaseAuth = _FakeSupabaseAuthClient(
      linkResponse: AuthResponse(user: _boundUser('google-user')),
    );
    final authService = AuthService(
      googleAuth: googleAuth,
      supabaseAuth: supabaseAuth,
    );
    final guestId = authService.initializeGuestMode();

    final response = await authService.bindAnonymousWithGoogle();

    expect(response.user?.id, 'google-user');
    expect(response.user?.id, isNot(guestId));
    expect(authService.isGuestMode, isFalse);
    expect(authService.isBoundAccount, isTrue);
    expect(authService.effectiveUserId, 'google-user');
  });

  test('bindAnonymousWithGoogle links identity with native tokens', () async {
    final googleAuth = _FakeGoogleAuthClient(
      authenticateResult: const GoogleAuthTokens(
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    );
    final supabaseAuth = _FakeSupabaseAuthClient();
    final authService = AuthService(
      googleAuth: googleAuth,
      supabaseAuth: supabaseAuth,
    );

    final response = await authService.bindAnonymousWithGoogle();

    expect(response, same(supabaseAuth.response));
    expect(supabaseAuth.linkIdentityWithIdTokenCalls, hasLength(1));
    expect(supabaseAuth.linkIdentityWithIdTokenCalls.single, (
      provider: OAuthProvider.google,
      idToken: 'google-id-token',
      accessToken: 'google-access-token',
    ));
  });

  test('signInWithFacebook uses Supabase native token sign-in', () async {
    final facebookAuth = _FakeFacebookAuthClient(
      loginResult: LoginResult(
        status: LoginStatus.success,
        accessToken: ClassicToken(
          userId: 'fb-user',
          tokenString: 'fb-access-token',
          expires: DateTime.now().add(const Duration(hours: 1)),
          applicationId: 'fb-app',
          declinedPermissions: const [],
          grantedPermissions: const ['email', 'public_profile'],
        ),
      ),
      userData: const {'name': 'Benedict'},
    );
    final supabaseAuth = _FakeSupabaseAuthClient();
    final authService = AuthService(
      facebookAuth: facebookAuth,
      supabaseAuth: supabaseAuth,
    );

    final response = await authService.signInWithFacebook();

    expect(response, same(supabaseAuth.response));
    expect(supabaseAuth.signInWithIdTokenCalls, hasLength(1));
    expect(supabaseAuth.signInWithIdTokenCalls.single, (
      provider: OAuthProvider.facebook,
      idToken: 'fb-access-token',
      accessToken: null,
    ));
  });
  test('email binding verification uses email-change OTP semantics', () async {
    final supabaseAuth = _FakeSupabaseAuthClient();
    final authService = AuthService(supabaseAuth: supabaseAuth);

    await authService.verifyEmailChange(
      email: 'parent@example.com',
      token: '123456',
    );

    expect(supabaseAuth.lastOtpType, OtpType.emailChange);
    expect(supabaseAuth.lastOtpEmail, 'parent@example.com');
  });

}

Map<String, dynamic> _boundUserJson(String id) => {
  'id': id,
  'app_metadata': <String, dynamic>{},
  'user_metadata': null,
  'aud': 'authenticated',
  'created_at': '2026-04-20T00:00:00Z',
  'is_anonymous': false,
};

User _boundUser(String id) => User.fromJson(_boundUserJson(id))!;


class _FakeGoogleAuthClient implements GoogleAuthClient {
  _FakeGoogleAuthClient({
    this.authenticateResult = const GoogleAuthTokens(idToken: 'id-token'),
  });

  final GoogleAuthTokens authenticateResult;

  @override
  Future<GoogleAuthTokens?> attemptLightweightAuthentication() async => null;

  @override
  Future<GoogleAuthTokens> authenticate() async => authenticateResult;

  @override
  Future<void> initialize({String? serverClientId, String? clientId}) async {}
}

class _FakeFacebookAuthClient implements FacebookAuthClient {
  _FakeFacebookAuthClient({required this.loginResult, required this.userData});

  final LoginResult loginResult;
  final Map<String, dynamic> userData;

  @override
  Future<Map<String, dynamic>> getUserData({String fields = ''}) async =>
      userData;

  @override
  Future<LoginResult> login({
    List<String> permissions = const ['email', 'public_profile'],
    LoginBehavior loginBehavior = LoginBehavior.nativeWithFallback,
    LoginTracking loginTracking = LoginTracking.limited,
    String? nonce,
  }) async => loginResult;

  @override
  Future<void> logOut() async {}
}

class _FakeSupabaseAuthClient implements SupabaseAuthClient {
  _FakeSupabaseAuthClient({
    User? currentUser,
    this.updateUserResponse,
    this.linkResponse,
  }) : _currentUser = currentUser;

  final UserResponse? updateUserResponse;
  final AuthResponse? linkResponse;
  User? _currentUser;
  OtpType? lastOtpType;
  String? lastOtpEmail;
  final signInWithIdTokenCalls =
      <({OAuthProvider provider, String idToken, String? accessToken})>[];
  final linkIdentityWithIdTokenCalls =
      <({OAuthProvider provider, String idToken, String? accessToken})>[];

  late final AuthResponse response =
      linkResponse ?? AuthResponse(user: _currentUser);
  @override
  User? get currentUser => _currentUser;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Future<AuthResponse> signInAnonymously() async => response;

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) async {
    signInWithIdTokenCalls.add((
      provider: provider,
      idToken: idToken,
      accessToken: accessToken,
    ));
    return response;
  }

  @override
  Future<AuthResponse> linkIdentityWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) async {
    linkIdentityWithIdTokenCalls.add((
      provider: provider,
      idToken: idToken,
      accessToken: accessToken,
    ));
    final bound = linkResponse ?? response;
    _currentUser = bound.user;
    return bound;
  }

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) => throw UnimplementedError();

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
    String? emailRedirectTo,
    String? captchaToken,
  }) => throw UnimplementedError();

  @override
  Future<UserResponse> updateUser(UserAttributes attributes) async {
    final bound =
        updateUserResponse ?? UserResponse.fromJson(_boundUserJson('email-user'));
    _currentUser = bound.user;
    return bound;
  }
  @override
  Future<AuthResponse> verifyEmailChange({
    required String email,
    required String token,
  }) => throw UnimplementedError();

  @override
  Future<ResendResponse> resendEmailChange(String email) =>
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
  }) async {
    lastOtpType = type;
    lastOtpEmail = email;
    return AuthResponse();
  }

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
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {}
}
