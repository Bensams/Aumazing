import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;
  bool _googleInitialized = false;

  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

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
      googleUser = await googleSignIn.authenticate();
      debugPrint('[GoogleAuth] Interactive auth result: ${googleUser.displayName}');
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
    await _client.auth.signOut();
  }
}
