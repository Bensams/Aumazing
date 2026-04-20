import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';

class GoogleAuthTokens {
  const GoogleAuthTokens({required this.idToken, this.accessToken});

  final String idToken;
  final String? accessToken;
}

abstract class GoogleAuthClient {
  Future<void> initialize({String? serverClientId, String? clientId});

  Future<GoogleAuthTokens?> attemptLightweightAuthentication();

  Future<GoogleAuthTokens> authenticate();
}

abstract class FacebookAuthClient {
  Future<LoginResult> login({
    List<String> permissions,
    LoginBehavior loginBehavior,
    LoginTracking loginTracking,
    String? nonce,
  });

  Future<Map<String, dynamic>> getUserData({String fields});

  Future<void> logOut();
}

class DefaultFacebookAuthClient implements FacebookAuthClient {
  @override
  Future<Map<String, dynamic>> getUserData({
    String fields = 'name,email,picture.width(200)',
  }) => FacebookAuth.instance.getUserData(fields: fields);

  @override
  Future<LoginResult> login({
    List<String> permissions = const ['email', 'public_profile'],
    LoginBehavior loginBehavior = LoginBehavior.nativeWithFallback,
    LoginTracking loginTracking = LoginTracking.limited,
    String? nonce,
  }) => FacebookAuth.instance.login(
    permissions: permissions,
    loginBehavior: loginBehavior,
    loginTracking: loginTracking,
    nonce: nonce,
  );

  @override
  Future<void> logOut() => FacebookAuth.instance.logOut();
}

class DefaultGoogleAuthClient implements GoogleAuthClient {
  DefaultGoogleAuthClient([GoogleSignIn? googleSignIn])
    : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final GoogleSignIn _googleSignIn;

  @override
  Future<void> initialize({String? serverClientId, String? clientId}) =>
      _googleSignIn.initialize(
        serverClientId: serverClientId,
        clientId: clientId,
      );

  @override
  Future<GoogleAuthTokens?> attemptLightweightAuthentication() async {
    final googleUser = await _googleSignIn.attemptLightweightAuthentication();
    return _tokensForUser(googleUser);
  }

  @override
  Future<GoogleAuthTokens> authenticate() async {
    final googleUser = await _googleSignIn.authenticate();
    final tokens = await _tokensForUser(googleUser);
    if (tokens == null) {
      throw AuthException('Failed to retrieve Google ID token.');
    }
    return tokens;
  }

  Future<GoogleAuthTokens?> _tokensForUser(
    GoogleSignInAccount? googleUser,
  ) async {
    if (googleUser == null) return null;

    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw AuthException('Failed to retrieve Google ID token.');
    }

    final scopes = ['email', 'profile'];
    final authorization =
        await googleUser.authorizationClient.authorizationForScopes(scopes) ??
        await googleUser.authorizationClient.authorizeScopes(scopes);

    return GoogleAuthTokens(
      idToken: idToken,
      accessToken: authorization.accessToken,
    );
  }
}

abstract class SupabaseAuthClient {
  User? get currentUser;
  Session? get currentSession;
  Stream<AuthState> get onAuthStateChange;

  Future<AuthResponse> signInAnonymously();
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
    String? emailRedirectTo,
    String? captchaToken,
  });
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  });
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  });
  Future<AuthResponse> linkIdentityWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  });
  Future<UserResponse> updateUser(UserAttributes attributes);
  Future<AuthResponse> verifyOTP({
    required OtpType type,
    String? token,
    String? tokenHash,
    String? phone,
    String? email,
    String? redirectTo,
    String? captchaToken,
  });
  Future<ResendResponse> resend({
    required OtpType type,
    String? email,
    String? phone,
    String? emailRedirectTo,
    String? captchaToken,
  });
  Future<void> resetPasswordForEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  });
  Future<AuthResponse> refreshSession([String? refreshToken]);
  Future<void> signOut({SignOutScope scope});
}

class DefaultSupabaseAuthClient implements SupabaseAuthClient {
  DefaultSupabaseAuthClient(this._auth);

  final GoTrueClient _auth;

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Session? get currentSession => _auth.currentSession;

  @override
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  @override
  Future<void> resetPasswordForEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) => _auth.resetPasswordForEmail(
    email,
    redirectTo: redirectTo,
    captchaToken: captchaToken,
  );

  @override
  Future<AuthResponse> refreshSession([String? refreshToken]) =>
      _auth.refreshSession(refreshToken);

  @override
  Future<ResendResponse> resend({
    required OtpType type,
    String? email,
    String? phone,
    String? emailRedirectTo,
    String? captchaToken,
  }) => _auth.resend(
    type: type,
    email: email,
    phone: phone,
    emailRedirectTo: emailRedirectTo,
    captchaToken: captchaToken,
  );

  @override
  Future<AuthResponse> signInAnonymously() => _auth.signInAnonymously();

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) => _auth.signInWithIdToken(
    provider: provider,
    idToken: idToken,
    accessToken: accessToken,
    nonce: nonce,
    captchaToken: captchaToken,
  );

  @override
  Future<AuthResponse> linkIdentityWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) => _auth.linkIdentityWithIdToken(
    provider: provider,
    idToken: idToken,
    accessToken: accessToken,
    nonce: nonce,
    captchaToken: captchaToken,
  );

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) => _auth.signInWithPassword(
    email: email,
    password: password,
    captchaToken: captchaToken,
  );

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) =>
      _auth.signOut(scope: scope);

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
    String? emailRedirectTo,
    String? captchaToken,
  }) => _auth.signUp(
    email: email,
    password: password,
    data: data,
    emailRedirectTo: emailRedirectTo,
    captchaToken: captchaToken,
  );

  @override
  Future<UserResponse> updateUser(UserAttributes attributes) =>
      _auth.updateUser(attributes);

  @override
  Future<AuthResponse> verifyOTP({
    required OtpType type,
    String? token,
    String? tokenHash,
    String? phone,
    String? email,
    String? redirectTo,
    String? captchaToken,
  }) => _auth.verifyOTP(
    type: type,
    token: token,
    tokenHash: tokenHash,
    phone: phone,
    email: email,
    redirectTo: redirectTo,
    captchaToken: captchaToken,
  );
}

/// Enhanced AuthService with guest/anonymous mode support.
///
/// Supports offline-first usage patterns:
/// - Guest mode: Creates local-only user ID for pre-authentication data
/// - Anonymous sign-in: Supabase anonymous authentication
/// - Full auth: Regular email/social authentication
///
/// Guest data is automatically backfilled after authentication.
class AuthService {
  final Uuid _uuid = const Uuid();
  final SupabaseAuthClient _supabaseAuth;
  final GoogleAuthClient _googleAuth;
  final FacebookAuthClient _facebookAuth;
  bool _googleInitialized = false;

  // Guest mode support
  static String? _guestId;

  AuthService({
    SupabaseAuthClient? supabaseAuth,
    GoogleAuthClient? googleAuth,
    FacebookAuthClient? facebookAuth,
  }) : _supabaseAuth =
           supabaseAuth ??
           DefaultSupabaseAuthClient(Supabase.instance.client.auth),
       _googleAuth = googleAuth ?? DefaultGoogleAuthClient(),
       _facebookAuth = facebookAuth ?? DefaultFacebookAuthClient();

  User? get currentUser => _supabaseAuth.currentUser;
  bool get isLoggedIn => currentUser != null;

  /// Current guest ID (valid when in guest mode)
  String? get currentGuestId => _guestId;

  /// Check if currently in guest mode (not authenticated but has guest ID)
  bool get isGuestMode =>
      currentUser?.isAnonymous == true ||
      (currentUser == null && _guestId != null);

  /// Get effective user ID - returns authenticated user ID, guest ID, or null
  String? get effectiveUserId => currentUser?.id ?? _guestId;

  Stream<AuthState> get authStateChanges => _supabaseAuth.onAuthStateChange;

  // --- Guest / Anonymous Mode ---

  /// Initialize guest mode with a temporary ID.
  ///
  /// Call this when app starts without authentication to enable
  /// offline data creation before user signs in.
  String initializeGuestMode() {
    if (_guestId == null) {
      _guestId = 'guest_${_uuid.v4()}';
      debugPrint('[AuthService] Guest mode initialized: $_guestId');
    }
    return _guestId!;
  }

  /// Sign in anonymously with Supabase.
  ///
  /// This creates a proper Supabase user session without requiring
  /// email/password or social credentials. Useful for seamless onboarding.
  Future<AuthResponse> signInAnonymously() async {
    try {
      final response = await _supabaseAuth.signInAnonymously();
      debugPrint('[AuthService] Anonymous sign-in: ${response.user?.id}');

      // If we had a guest ID, the caller should handle backfilling
      return response;
    } catch (e) {
      debugPrint('[AuthService] Anonymous sign-in error: $e');
      rethrow;
    }
  }

  /// Convert anonymous user to permanent account.
  ///
  /// Call after anonymous sign-in when user provides email/password.
  Future<AuthResponse> convertAnonymousToPermanent({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabaseAuth.updateUser(
        UserAttributes(email: email, password: password),
      );
      debugPrint('[AuthService] Anonymous account converted to permanent');
      return AuthResponse(
        user: response.user,
        session: _supabaseAuth.currentSession,
      );
    } catch (e) {
      debugPrint('[AuthService] Convert anonymous error: $e');
      rethrow;
    }
  }

  /// Clear guest mode (call after successful authentication)
  void clearGuestMode() {
    final oldGuestId = _guestId;
    _guestId = null;
    if (oldGuestId != null) {
      debugPrint('[AuthService] Guest mode cleared (was: $oldGuestId)');
    }
  }

  // --- Email / Password ---

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await _supabaseAuth.signUp(
      email: email,
      password: password,
      data: displayName != null ? {'display_name': displayName} : null,
    );
    return response;
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _supabaseAuth.signInWithPassword(
      email: email,
      password: password,
    );
    return response;
  }

  // --- Google Sign-In (native, google_sign_in v7.x) ---

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await _googleAuth.initialize(
      serverClientId: SupabaseConfig.googleWebClientId,
      clientId: Platform.isIOS ? SupabaseConfig.googleIosClientId : null,
    );
    _googleInitialized = true;
  }

  Future<GoogleAuthTokens> _getGoogleAuthTokens() async {
    await _ensureGoogleInitialized();

    try {
      final googleUser = await _googleAuth.attemptLightweightAuthentication();
      debugPrint('[GoogleAuth] Lightweight auth result: ${googleUser != null}');
      if (googleUser != null) {
        debugPrint(
          '[GoogleAuth] Access token obtained: ${googleUser.accessToken}',
        );
        return googleUser;
      }
    } catch (e) {
      debugPrint('[GoogleAuth] Lightweight auth failed: $e');
    }

    debugPrint('[GoogleAuth] Falling back to interactive authenticate()...');
    try {
      final tokens = await _googleAuth.authenticate();
      debugPrint('[GoogleAuth] Interactive auth completed');
      debugPrint('[GoogleAuth] Access token obtained: ${tokens.accessToken}');
      return tokens;
    } on Exception catch (e) {
      final errorString = e.toString();
      debugPrint('[GoogleAuth] Interactive auth error: $errorString');

      if (errorString.contains('CancellationException') ||
          errorString.contains('canceled') ||
          errorString.contains('CANCELLED')) {
        throw AuthException('Sign-in was cancelled. Please try again.');
      }
      if (errorString.contains('unknownError') ||
          errorString.contains('10:') ||
          errorString.contains('DEVELOPER_ERROR')) {
        throw AuthException(
          'Google Sign-In configuration error. Please check:\n'
          '1. Android OAuth Client ID is created in Google Cloud Console\n'
          '2. SHA-1 fingerprint is added to the Android OAuth client\n'
          '3. Package name matches the OAuth configuration',
        );
      }
      rethrow;
    }
  }

  Future<AuthResponse> signInWithGoogle() async {
    debugPrint('[GoogleAuth] Starting Google Sign-In flow...');
    final tokens = await _getGoogleAuthTokens();

    final response = await _supabaseAuth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
    );
    debugPrint('[GoogleAuth] Supabase signInWithIdToken succeeded');

    return response;
  }

  Future<AuthResponse> bindAnonymousWithGoogle() async {
    debugPrint('[GoogleAuth] Starting Google bind flow...');
    final tokens = await _getGoogleAuthTokens();

    final response = await _supabaseAuth.linkIdentityWithIdToken(
      provider: OAuthProvider.google,
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
    );
    debugPrint('[GoogleAuth] Supabase linkIdentityWithIdToken succeeded');

    return response;
  }

  // --- Facebook Sign-In ---

  Future<AuthResponse> signInWithFacebook() async {
    debugPrint('[FacebookAuth] Starting Facebook Sign-In flow...');

    try {
      // Trigger Facebook login
      final LoginResult result = await _facebookAuth.login(
        permissions: ['email', 'public_profile'],
        loginBehavior: LoginBehavior.nativeWithFallback,
      );

      debugPrint('[FacebookAuth] Login result: ${result.status}');

      if (result.status == LoginStatus.success) {
        final String? accessToken = result.accessToken?.tokenString;
        if (accessToken == null) {
          throw AuthException('Failed to retrieve Facebook access token.');
        }
        debugPrint('[FacebookAuth] Access token obtained');

        // Get user data from Facebook
        final userData = await _facebookAuth.getUserData(
          fields: 'email,first_name,last_name,name,picture',
        );
        debugPrint('[FacebookAuth] User data retrieved: ${userData['name']}');

        final response = await _supabaseAuth.signInWithIdToken(
          provider: OAuthProvider.facebook,
          idToken: accessToken,
        );
        debugPrint('[FacebookAuth] Supabase native sign-in succeeded');
        return response;
      } else if (result.status == LoginStatus.cancelled) {
        debugPrint('[FacebookAuth] User cancelled login');
        throw AuthException('Facebook sign-in was cancelled.');
      } else if (result.status == LoginStatus.failed) {
        debugPrint('[FacebookAuth] Login failed: ${result.message}');
        throw AuthException(
          result.message ?? 'Facebook sign-in failed. Please try again.',
        );
      } else {
        throw AuthException('Facebook sign-in is already in progress.');
      }
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('[FacebookAuth] Unexpected error: $e');
      throw AuthException('Facebook sign-in error: $e');
    }
  }

  // --- Email OTP Verification ---

  Future<AuthResponse> verifyOTP({
    required String email,
    required String token,
  }) async {
    final response = await _supabaseAuth.verifyOTP(
      type: OtpType.signup,
      email: email,
      token: token,
    );
    return response;
  }

  Future<void> resendOTP(String email) async {
    await _supabaseAuth.resend(type: OtpType.signup, email: email);
  }

  // --- Password Reset (OTP-based) ---

  Future<void> sendPasswordResetOTP(String email) async {
    await _supabaseAuth.resetPasswordForEmail(email);
  }

  Future<AuthResponse> verifyPasswordResetOTP({
    required String email,
    required String token,
  }) async {
    final response = await _supabaseAuth.verifyOTP(
      type: OtpType.recovery,
      email: email,
      token: token,
    );
    return response;
  }

  Future<void> updatePassword(String newPassword) async {
    await _supabaseAuth.updateUser(UserAttributes(password: newPassword));
  }

  // --- Child Profile ---

  /// Refreshes the local session so that [currentUser] and its metadata
  /// reflect the latest server-side state. Call this before reading
  /// [hasChildProfile] after a cold start or sign-in.
  Future<void> refreshSession() async {
    try {
      await _supabaseAuth.refreshSession();
    } catch (e) {
      debugPrint('refreshSession failed (non-fatal): $e');
    }
  }

  bool get hasChildProfile {
    final meta = currentUser?.userMetadata;
    if (meta == null) return false;
    return meta['child_name'] != null && meta['child_age'] != null;
  }

  Map<String, dynamic>? get childProfile {
    final meta = currentUser?.userMetadata;
    if (meta == null || meta['child_name'] == null) return null;
    return {
      'name': meta['child_name'],
      'age': meta['child_age'],
      'avatar': meta['child_avatar'],
    };
  }

  Future<void> saveChildProfile({
    required String name,
    required int age,
    required String avatar,
  }) async {
    await _supabaseAuth.updateUser(
      UserAttributes(
        data: {'child_name': name, 'child_age': age, 'child_avatar': avatar},
      ),
    );
    // Refresh the local session so that currentUser.userMetadata
    // reflects the newly-saved child profile immediately.
    await refreshSession();
  }

  // --- Sign Out ---

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (e) {
      debugPrint('Google sign-out cleanup: $e');
    }
    try {
      await _facebookAuth.logOut();
    } catch (e) {
      debugPrint('Facebook sign-out cleanup: $e');
    }
    await _supabaseAuth.signOut();

    // Re-initialize guest mode for continued offline usage
    initializeGuestMode();
  }
}
