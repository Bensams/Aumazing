import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import 'local_db_service.dart';
import 'protected_storage.dart';

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
      throw AuthException(
        'Google Sign-In could not be completed. '
        'Please try again, or sign in with your email instead.',
      );
    }
    return tokens;
  }

  Future<GoogleAuthTokens?> _tokensForUser(
    GoogleSignInAccount? googleUser,
  ) async {
    if (googleUser == null) return null;

    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw AuthException(
        'Google Sign-In could not be completed. '
        'Please try again, or sign in with your email instead.',
      );
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
  Future<AuthResponse> verifyEmailChange({
    required String email,
    required String token,
  });
  Future<ResendResponse> resendEmailChange(String email);
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
  Future<UserResponse> updateUser(UserAttributes attributes);
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
  Future<AuthResponse> verifyEmailChange({
    required String email,
    required String token,
  }) => _auth.verifyOTP(
    type: OtpType.emailChange,
    email: email,
    token: token,
  );

  @override
  Future<ResendResponse> resendEmailChange(String email) => _auth.resend(
    type: OtpType.emailChange,
    email: email,
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

  // SharedPreferences keys for guest session persistence
  static const _guestRefreshTokenKey = 'guest_refresh_token';
  static const _guestUserIdKey = 'guest_user_id';

  // Stores the previous guest user ID when a migration occurred
  String? _previousGuestUserId;

  final LocalDbService _localDb;
  final ProtectedStorage _protectedStorage;

  AuthService({
    SupabaseAuthClient? supabaseAuth,
    GoogleAuthClient? googleAuth,
    FacebookAuthClient? facebookAuth,
    LocalDbService? localDb,
    ProtectedStorage? protectedStorage,
  }) : _supabaseAuth =
           supabaseAuth ??
           DefaultSupabaseAuthClient(Supabase.instance.client.auth),
       _googleAuth = googleAuth ?? DefaultGoogleAuthClient(),
       _facebookAuth = facebookAuth ?? DefaultFacebookAuthClient(),
       _localDb = localDb ?? localDbService,
       _protectedStorage = protectedStorage ?? ProtectedStorage();

  User? get currentUser => _supabaseAuth.currentUser;
  bool get isLoggedIn => currentUser != null;

  /// Whether the in-memory Supabase session has passed its server expiry.
  /// Callers should route to authentication rather than rendering stale data.
  bool get isSessionExpired {
    final expiresAt = _supabaseAuth.currentSession?.expiresAt;
    return expiresAt != null &&
        DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
            .isBefore(DateTime.now());
  }

  /// True when signed in with a permanent (bound) account — i.e. a Supabase
  /// user that is not anonymous. Guest/anonymous sessions return false.
  bool get isBoundAccount =>
      currentUser != null && currentUser?.isAnonymous != true;

  /// The account's confirmed email address, or null when the session is a
  /// guest, has no email, or the address has not been confirmed yet.
  ///
  /// This gates the custom parent PIN: an emailed one-time code is the only
  /// way back in after a forgotten PIN, so without a deliverable address a
  /// parent could lock themselves out of the dashboard permanently.
  String? get verifiedEmail {
    final user = currentUser;
    if (user == null || user.isAnonymous == true) return null;
    final email = user.email;
    if (email == null || email.isEmpty) return null;
    return user.emailConfirmedAt == null ? null : email;
  }

  /// True when [verifiedEmail] is available.
  bool get hasVerifiedEmail => verifiedEmail != null;

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

  /// Sign in anonymously, reusing an existing unbound guest account if one
  /// exists locally. Only creates a new anonymous account when no reusable
  /// guest session is found.
  ///
  /// A guest account is considered "unbound" when [User.isAnonymous] is true
  /// (i.e., it has not been linked to Google/Facebook/email).
  ///
  /// When token restore fails and a new anonymous account is created, child
  /// profiles keyed to the old guest user ID are automatically migrated to
  /// the new user ID in the local SQLite database.
  Future<AuthResponse> signInAnonymouslyOrReuse() async {
    // 1. Try to restore a previously stored guest session
    final storedRefreshToken = await _protectedStorage.read(
      _guestRefreshTokenKey,
      legacyKey: _guestRefreshTokenKey,
    );
    final oldGuestUserId = await _protectedStorage.read(
      _guestUserIdKey,
      legacyKey: _guestUserIdKey,
    );

    if (storedRefreshToken != null) {
      try {
        debugPrint('[AuthService] Found stored guest refresh token, attempting restore...');
        final restored = await _supabaseAuth.refreshSession(storedRefreshToken);

        if (restored.user != null && restored.user!.isAnonymous) {
          debugPrint('[AuthService] Reusing existing guest account: ${restored.user!.id}');
          // Update the stored refresh token in case it was rotated
          final newRefreshToken = restored.session?.refreshToken;
          if (newRefreshToken != null) {
            await _protectedStorage.write(_guestRefreshTokenKey, newRefreshToken);
          }
          // Persist the user ID (may already match, but ensure it's stored)
          await _protectedStorage.write(_guestUserIdKey, restored.user!.id);
          debugPrint('[AuthService] Stored guest user ID: ${restored.user!.id}');
          return restored;
        }

        // User exists but is no longer anonymous (was bound to a provider).
        // Clear the stored token and create a new guest account.
        debugPrint('[AuthService] Stored guest account is bound, creating new guest...');
        await _protectedStorage.delete(_guestRefreshTokenKey);
      } catch (e) {
        // Refresh failed (token expired, revoked, etc.) — create a new guest.
        debugPrint('[AuthService] Guest session restore failed: $e');
        await _protectedStorage.delete(_guestRefreshTokenKey);
      }
    }

    // 2. No reusable guest session — create a new anonymous account
    debugPrint('[AuthService] Creating new anonymous account...');
    final response = await signInAnonymously();
    final newUserId = response.user?.id;

    // 3. Migrate child profiles if the old guest user ID differs from the new one
    if (oldGuestUserId != null &&
        newUserId != null &&
        oldGuestUserId != newUserId) {
      debugPrint(
        '[AuthService] Guest user ID changed: $oldGuestUserId -> $newUserId. '
        'Migrating child profiles...',
      );
      _previousGuestUserId = oldGuestUserId;
      try {
        await _localDb.migrateGuestUserId(oldGuestUserId, newUserId);
        debugPrint('[AuthService] Child profile migration complete');
      } catch (e) {
        debugPrint('[AuthService] Child profile migration failed: $e');
      }
    }

    // 4. Persist the new guest session's refresh token and user ID for future reuse
    final refreshToken = response.session?.refreshToken;
    if (refreshToken != null) {
      await _protectedStorage.write(_guestRefreshTokenKey, refreshToken);
      debugPrint('[AuthService] Stored guest refresh token for reuse');
    }
    if (newUserId != null) {
      await _protectedStorage.write(_guestUserIdKey, newUserId);
      debugPrint('[AuthService] Stored guest user ID: $newUserId');
    }

    return response;
  }

  /// Clear the stored guest refresh token and user ID.
  ///
  /// Call this when the guest account is bound to a provider (Google,
  /// Facebook, email) so that a fresh guest account will be created on
  /// the next guest sign-in.
  Future<void> clearStoredGuestSession() async {
    await _protectedStorage.delete(_guestRefreshTokenKey);
    await _protectedStorage.delete(_guestUserIdKey);
    _previousGuestUserId = null;
    debugPrint('[AuthService] Cleared stored guest session and user ID');
  }

  /// Returns the stored guest user ID from SharedPreferences, or null if
  /// no guest session has been persisted yet.
  Future<String?> getStoredGuestUserId() async {
    return _protectedStorage.read(_guestUserIdKey, legacyKey: _guestUserIdKey);
  }

  /// Returns the previous guest user ID when a migration occurred during
  /// [signInAnonymouslyOrReuse]. This is non-null only when the token
  /// restore failed and child profiles were migrated to a new user ID.
  String? get previousGuestUserId => _previousGuestUserId;

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

  // ── Persistent offline guest ─────────────────────────────────────────

  static const _guestEstablishedKey = 'guest_established';

  /// Loads a persisted local guest id, or creates and persists a new one, so
  /// the guest id is stable across app restarts (offline-first — no network).
  Future<String> restoreOrCreateGuest() async {
    final prefs = await SharedPreferences.getInstance();
    var id = _guestId ?? prefs.getString(_guestUserIdKey);
    if (id == null || id.isEmpty) {
      id = 'guest_${_uuid.v4()}';
      await prefs.setString(_guestUserIdKey, id);
    }
    _guestId = id;
    return id;
  }

  /// Whether the user has explicitly chosen to continue as a guest (persisted).
  Future<bool> isGuestEstablished() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_guestEstablishedKey) ?? false;
  }

  /// Establishes an offline guest session: ensures a persistent local guest id
  /// and marks it as chosen. Works fully offline — no Supabase call.
  Future<String> continueAsGuest() async {
    final id = await restoreOrCreateGuest();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guestEstablishedKey, true);
    debugPrint('[AuthService] Continued as offline guest: $id');
    return id;
  }

  /// Clears the "chosen guest" flag (e.g. on sign-out) so the next launch
  /// returns to login.
  Future<void> clearGuestEstablished() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_guestEstablishedKey);
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
      if (googleUser != null) return googleUser;
    } catch (e) {
      debugPrint('[GoogleAuth] Lightweight auth failed: $e');
    }

    debugPrint('[GoogleAuth] Falling back to interactive authenticate()...');
    try {
      final tokens = await _googleAuth.authenticate();
      debugPrint('[GoogleAuth] Interactive auth completed');
      return tokens;
    } on GoogleSignInException catch (e) {
      // Branch on the plugin's own failure code rather than string-matching
      // its toString(): a real user cancellation and a misconfigured OAuth
      // client are indistinguishable once flattened to text, and reporting
      // the wrong one sends you looking in the wrong place.
      debugPrint(
        '[GoogleAuth] Interactive auth failed: ${e.code} — ${e.description}',
      );
      throw AuthException(_googleFailureMessage(e));
    }
  }

  /// Maps a [GoogleSignInException] to a message that names the real cause.
  /// New codes may be added by the plugin without a breaking change, so
  /// anything unrecognised falls through to the diagnostic branch.
  String _googleFailureMessage(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Sign-in was cancelled. Please try again.';
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Sign-in was interrupted. Please try again.';
      default:
        // The cause here is almost always a build misconfiguration (missing
        // Android OAuth client, mismatched SHA-1 / package name). That is a
        // sentence for the developer reading the log above, not for the parent
        // reading the dialog, who can do nothing with it either way.
        return 'Google Sign-In could not be completed. '
            'Please try again, or sign in with your email instead.';
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
          throw AuthException(
            'Facebook sign-in could not be completed. '
            'Please try again, or sign in with your email instead.',
          );
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
      throw AuthException(
        'Facebook sign-in could not be completed. '
        'Please try again, or sign in with your email instead.',
      );
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
  /// Verifies one step of Supabase's secure email-change flow.
  ///
  /// The first verification can intentionally return without a session;
  /// callers must keep the current anonymous session and submit the second
  /// code before treating the account as bound.
  Future<AuthResponse> verifyEmailChange({
    required String email,
    required String token,
  }) => _supabaseAuth.verifyOTP(
    type: OtpType.emailChange,
    email: email,
    token: token,
  );

  Future<void> resendEmailChange(String email) async {
    await _supabaseAuth.resend(type: OtpType.emailChange, email: email);
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
    final isAnonymous = currentUser?.isAnonymous == true;

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

    if (isAnonymous) {
      // Use local scope to preserve the refresh token on the server so the
      // same anonymous account can be restored on the next guest sign-in.
      await _supabaseAuth.signOut(scope: SignOutScope.local);
      debugPrint('[AuthService] Anonymous user signed out with local scope');
    } else {
      // Fully revoke the session for bound (non-anonymous) accounts and
      // clear the stored guest token so a fresh guest account is created
      // next time.
      await _supabaseAuth.signOut(scope: SignOutScope.global);
      await clearStoredGuestSession();
      debugPrint('[AuthService] Bound user signed out with global scope');
    }
    // Sign-out returns the user to login on next launch.
    await clearGuestEstablished();
  }

  // --- Delete Account ---

  /// Permanently deletes the current account and all its cloud data via the
  /// `delete-account` edge function, then clears every local trace of the
  /// session. Throws if the server-side deletion fails.
  Future<void> deleteAccount() async {
    final response =
        await Supabase.instance.client.functions.invoke('delete-account');
    final data = response.data as Map<String, dynamic>?;
    if (data?['deleted'] != true) {
      throw AuthException(
        (data?['error'] as String?) ?? 'Account deletion failed.',
      );
    }
    debugPrint('[AuthService] Account deleted server-side');

    try {
      await GoogleSignIn.instance.disconnect();
    } catch (e) {
      debugPrint('Google delete-account cleanup: $e');
    }
    try {
      await _facebookAuth.logOut();
    } catch (e) {
      debugPrint('Facebook delete-account cleanup: $e');
    }
    try {
      // The server-side user is gone; local scope just drops the session.
      await _supabaseAuth.signOut(scope: SignOutScope.local);
    } catch (e) {
      debugPrint('Supabase delete-account sign-out cleanup: $e');
    }
    await clearStoredGuestSession();
    await clearGuestEstablished();
    clearGuestMode();
  }
}
