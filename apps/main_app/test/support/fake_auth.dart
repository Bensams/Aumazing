import 'package:aumazing/core/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// An [AuthService] that reports a fixed effective user id.
///
/// Covers both parent kinds the app supports: a bound account (a real user
/// id, [FakeAuthService.boundAccount]) and a guest parent (a local
/// `guest_<uuid>` id, [FakeAuthService.guest]).
class FakeAuthService extends AuthService {
  FakeAuthService({
    required this.userId,
    required this.loggedIn,
    this.migratedFromGuestId,
    this.storedGuestId,
  }) : super(supabaseAuth: NoopSupabaseAuthClient());

  factory FakeAuthService.boundAccount([String userId = 'user-1']) =>
      FakeAuthService(userId: userId, loggedIn: true);

  factory FakeAuthService.guest([String guestId = 'guest_abc']) =>
      FakeAuthService(userId: guestId, loggedIn: false);

  final String? userId;
  final bool loggedIn;

  /// Simulates a guest-session restore that failed and minted a new user id
  /// (see [AuthService.previousGuestUserId]).
  final String? migratedFromGuestId;

  /// Simulates the persisted guest user id a converted account grew out of
  /// (see [AuthService.getStoredGuestUserId]).
  final String? storedGuestId;

  @override
  String? get previousGuestUserId => migratedFromGuestId;

  @override
  Future<String?> getStoredGuestUserId() async => storedGuestId;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  bool get isGuestMode => !loggedIn;

  @override
  Future<bool> isGuestEstablished() async => !loggedIn;

  @override
  String? get effectiveUserId => userId;

  @override
  String? get currentGuestId => loggedIn ? null : userId;

  @override
  Future<void> refreshSession() async {}
}

/// A [SupabaseAuthClient] that never touches the network — enough to build an
/// [AuthService] in a test without initializing Supabase.
class NoopSupabaseAuthClient implements SupabaseAuthClient {
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
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {}
}
