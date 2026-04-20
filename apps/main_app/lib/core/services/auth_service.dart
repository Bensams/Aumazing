import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';

/// Enhanced AuthService with guest/anonymous mode support.
///
/// Supports offline-first usage patterns:
/// - Guest mode: Creates local-only user ID for pre-authentication data
/// - Anonymous sign-in: Supabase anonymous authentication
/// - Full auth: Regular email/social authentication
///
/// Guest data is automatically backfilled after authentication.
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;
  final Uuid _uuid = const Uuid();
  bool _googleInitialized = false;

  // Guest mode support
  String? _guestId;

  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  /// Current guest ID (valid when in guest mode)
  String? get currentGuestId => _guestId;

  /// Check if currently in guest mode (not authenticated but has guest ID)
  bool get isGuestMode => currentUser == null && _guestId != null;

  /// Get effective user ID - returns authenticated user ID, guest ID, or null
  String? get effectiveUserId => currentUser?.id ?? _guestId;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

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
      final response = await _client.auth.signInAnonymously();
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
      final response = await _client.auth.updateUser(
        UserAttributes(
          email: email,
          password: password,
        ),
      );
      debugPrint('[AuthService] Anonymous account converted to permanent');
      return AuthResponse(user: response.user, session: _client.auth.currentSession);
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
    final response = await _client.auth.signUp(
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
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response;
  }

  // --- Google Sign-In (native, google_sign_in v7.x) ---

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    final googleSignIn = GoogleSignIn.instance;
    await googleSignIn.initialize(
      serverClientId: SupabaseConfig.googleWebClientId,
      clientId: Platform.isIOS ? SupabaseConfig.googleIosClientId : null,
    );
    _googleInitialized = true;
  }

  Future<AuthResponse> signInWithGoogle() async {
    await _ensureGoogleInitialized();
    final googleSignIn = GoogleSignIn.instance;

    debugPrint('[GoogleAuth] Starting Google Sign-In flow...');

    GoogleSignInAccount? googleUser;
    try {
      googleUser = await googleSignIn.attemptLightweightAuthentication();
      debugPrint('[GoogleAuth] Lightweight auth result: ${googleUser?.displayName ?? 'null'}');
    } catch (e) {
      debugPrint('[GoogleAuth] Lightweight auth failed: $e');
    }

    if (googleUser == null) {
      debugPrint('[GoogleAuth] Falling back to interactive authenticate()...');
      try {
        googleUser = await googleSignIn.authenticate();
        debugPrint('[GoogleAuth] Interactive auth result: ${googleUser.displayName}');
      } on Exception catch (e) {
        final errorString = e.toString();
        debugPrint('[GoogleAuth] Interactive auth error: $errorString');

        // Check for cancellation or configuration errors
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
            '3. Package name matches the OAuth configuration'
          );
        }
        rethrow;
      }
    }

    final idToken = googleUser.authentication.idToken;
    debugPrint('[GoogleAuth] ID token obtained: ${idToken != null}');
    if (idToken == null) {
      throw AuthException('Failed to retrieve Google ID token.');
    }

    final scopes = ['email', 'profile'];
    final authorization =
        await googleUser.authorizationClient.authorizationForScopes(scopes) ??
            await googleUser.authorizationClient.authorizeScopes(scopes);
    debugPrint('[GoogleAuth] Access token obtained: ${authorization.accessToken}');

    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization.accessToken,
    );
    debugPrint('[GoogleAuth] Supabase signInWithIdToken succeeded');

    return response;
  }

  // --- Facebook Sign-In ---

  Future<AuthResponse> signInWithFacebook() async {
    debugPrint('[FacebookAuth] Starting Facebook Sign-In flow...');

    try {
      // Trigger Facebook login
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );

      debugPrint('[FacebookAuth] Login result: ${result.status}');

      if (result.status == LoginStatus.success) {
        final String? accessToken = result.accessToken?.tokenString;
        if (accessToken == null) {
          throw AuthException('Failed to retrieve Facebook access token.');
        }
        debugPrint('[FacebookAuth] Access token obtained');

        // Get user data from Facebook
        final userData = await FacebookAuth.instance.getUserData(
          fields: 'email,first_name,last_name,name,picture',
        );
        debugPrint('[FacebookAuth] User data retrieved: ${userData['name']}');

        // Sign in to Supabase using Facebook OAuth with access token
        final response = await _client.auth.signInWithOAuth(
          OAuthProvider.facebook,
          redirectTo: 'com.aumazing.app://login-callback',
        );

        if (!response) {
          throw AuthException('Failed to initiate Facebook OAuth flow.');
        }

        // Wait for the OAuth callback and get the current session
        // The session will be set automatically by Supabase deep link handling
        await for (final state in _client.auth.onAuthStateChange) {
          if (state.event == AuthChangeEvent.signedIn) {
            debugPrint('[FacebookAuth] Supabase sign-in succeeded');
            return AuthResponse(
              session: state.session,
              user: state.session?.user,
            );
          }
          if (state.event == AuthChangeEvent.signedOut) {
            break;
          }
        }

        // If we reach here, check if we have a session
        final currentSession = _client.auth.currentSession;
        if (currentSession != null) {
          return AuthResponse(
            session: currentSession,
            user: _client.auth.currentUser,
          );
        }

        throw AuthException('Failed to complete Facebook sign-in.');
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
    final response = await _client.auth.verifyOTP(
      type: OtpType.signup,
      email: email,
      token: token,
    );
    return response;
  }

  Future<void> resendOTP(String email) async {
    await _client.auth.resend(type: OtpType.signup, email: email);
  }

  // --- Password Reset (OTP-based) ---

  Future<void> sendPasswordResetOTP(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  Future<AuthResponse> verifyPasswordResetOTP({
    required String email,
    required String token,
  }) async {
    final response = await _client.auth.verifyOTP(
      type: OtpType.recovery,
      email: email,
      token: token,
    );
    return response;
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  // --- Child Profile ---

  /// Refreshes the local session so that [currentUser] and its metadata
  /// reflect the latest server-side state. Call this before reading
  /// [hasChildProfile] after a cold start or sign-in.
  Future<void> refreshSession() async {
    try {
      await _client.auth.refreshSession();
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
    await _client.auth.updateUser(
      UserAttributes(data: {
        'child_name': name,
        'child_age': age,
        'child_avatar': avatar,
      }),
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
      await FacebookAuth.instance.logOut();
    } catch (e) {
      debugPrint('Facebook sign-out cleanup: $e');
    }
    await _client.auth.signOut();

    // Re-initialize guest mode for continued offline usage
    initializeGuestMode();
  }
}
