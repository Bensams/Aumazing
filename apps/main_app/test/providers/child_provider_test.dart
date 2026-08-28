import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

ChildProvider _buildProvider({List<ChildProfile> children = const []}) =>
    ChildProvider(
      localDb: _FakeLocalDbService(children),
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

final _child = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Ana',
  birthDate: DateTime(2020, 1, 1),
  avatar: 'avatar_1',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadProfile leaves profile null when no local child exists', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = _buildProvider();

    await provider.loadProfile();

    expect(provider.profile, isNull);
    expect(provider.hasProfile, isFalse);
  });

  group('voice pack preference', () {
    test('defaults to the active language default pack', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = _buildProvider(children: [_child]);
      await provider.loadProfile();

      expect(provider.voicePack.id, 'en_adult_woman');
      expect(provider.voiceAssetFolder, 'en_adult_woman');
      // The multi-speaker original packs were removed, so the default is now
      // the first generated pack for the language.
      expect(provider.availableVoicePacks.first.id, 'en_adult_woman');
      expect(provider.availableVoicePacks.length, greaterThan(1));
    });

    test('setVoicePack persists per child and survives a reload', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = _buildProvider(children: [_child]);
      await provider.loadProfile();
      await provider.setLanguage(GameLanguage.cebuano);

      await provider.setVoicePack('ceb_lexianne');
      expect(provider.voiceAssetFolder, 'ceb_lexianne');

      final reloaded = _buildProvider(children: [_child]);
      await reloaded.loadProfile();

      expect(reloaded.language, GameLanguage.cebuano);
      expect(reloaded.voicePack.id, 'ceb_lexianne');
      expect(reloaded.voiceAssetFolder, 'ceb_lexianne');
    });

    test('cebuano leads with its default pack and still offers Lexianne',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = _buildProvider(children: [_child]);
      await provider.loadProfile();
      await provider.setLanguage(GameLanguage.cebuano);

      final ids = provider.availableVoicePacks.map((p) => p.id).toList();
      expect(ids.first, 'ceb_adult_woman');
      expect(ids, contains('ceb_child_girl'));
      expect(ids, contains('ceb_lexianne'));
      // Every offered pack must actually speak Cebuano.
      expect(
        provider.availableVoicePacks.every((p) => p.languageSlug == 'ceb'),
        isTrue,
      );
    });

    test('ignores a pack belonging to another language', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = _buildProvider(children: [_child]);
      await provider.loadProfile();

      await provider.setVoicePack('ceb_lexianne');

      expect(provider.voicePack.id, 'en_adult_woman');
    });

    test('switching language resets to the new language default', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = _buildProvider(children: [_child]);
      await provider.loadProfile();
      await provider.setLanguage(GameLanguage.cebuano);
      await provider.setVoicePack('ceb_lexianne');

      await provider.setLanguage(GameLanguage.english);
      expect(provider.voicePack.id, 'en_adult_woman');

      // Documented behaviour: the earlier Lexianne choice is NOT restored.
      await provider.setLanguage(GameLanguage.cebuano);
      expect(provider.voicePack.id, 'ceb_adult_woman');
    });

    test('discards a stored pack that no longer fits the language', () async {
      SharedPreferences.setMockInitialValues({
        'language_child-1': 'en',
        'voice_pack_child-1': 'ceb_lexianne',
      });
      final provider = _buildProvider(children: [_child]);

      await provider.loadProfile();

      expect(provider.voicePack.id, 'en_adult_woman');
    });

    test('discards a stored pack that is no longer registered', () async {
      SharedPreferences.setMockInitialValues({
        'language_child-1': 'ceb',
        'voice_pack_child-1': 'ceb_retired_voice',
      });
      final provider = _buildProvider(children: [_child]);

      await provider.loadProfile();

      expect(provider.voicePack.id, 'ceb_adult_woman');
    });
  });
}

class _FakeLocalDbService extends LocalDbService {
  _FakeLocalDbService(this._children);

  final List<ChildProfile> _children;

  @override
  Future<List<ChildProfile>> getChildren({
    String? userId,
    bool includeDeleted = false,
  }) async => _children;
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
  Future<AuthResponse> verifyEmailChange({
    required String email,
    required String token,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ResendResponse> resendEmailChange(String email) {
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
