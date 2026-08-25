import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/settings/bind_account_modal.dart';
import '../../support/fake_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() {
    AuthService(supabaseAuth: NoopSupabaseAuthClient()).clearGuestMode();
  });

  testWidgets('email binding clears guest state and centers its label', (
    tester,
  ) async {
    final auth = _BindingTestAuth();
    auth.initializeGuestMode();
    await _pumpModal(tester, auth);

    await tester.tap(find.text('Bind with Email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'parent@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'secret');

    final button = find.widgetWithText(ElevatedButton, 'Bind with Email');
    final label = find.descendant(
      of: button,
      matching: find.text('Bind with Email'),
    );
    expect(button, findsOneWidget);
    expect(label, findsOneWidget);
    expect(tester.getCenter(label).dx, closeTo(tester.getCenter(button).dx, 1));

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(auth.emailCalls, 1);
    expect(auth.email, 'parent@example.com');
    expect(auth.password, 'secret');
    _expectBoundState(auth);
  });

  testWidgets('Google binding clears guest state and uses response identity', (
    tester,
  ) async {
    final auth = _BindingTestAuth();
    auth.initializeGuestMode();
    await _pumpModal(tester, auth);

    await tester.tap(find.text('Bind with Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(auth.googleCalls, 1);
    _expectBoundState(auth);
  });
}

Future<void> _pumpModal(WidgetTester tester, AuthService auth) async {
  await tester.binding.setSurfaceSize(const Size(960, 540));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: BindAccountModal(authService: auth)),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectBoundState(_BindingTestAuth auth) {
  expect(auth.isGuestMode, isFalse);
  expect(auth.isBoundAccount, isTrue);
  expect(auth.effectiveUserId, 'bound-user');
  expect(auth.currentUser?.isAnonymous, isFalse);
}

class _BindingTestAuth extends AuthService {
  _BindingTestAuth() : super(supabaseAuth: NoopSupabaseAuthClient());

  static const _boundUser = User(
    id: 'bound-user',
    appMetadata: {},
    userMetadata: null,
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    email: 'parent@example.com',
    isAnonymous: false,
  );

  User? _user;
  int emailCalls = 0;
  int googleCalls = 0;
  String? email;
  String? password;
  @override
  User? get currentUser => _user;

  @override
  bool get isBoundAccount =>
      _user != null && _user?.isAnonymous != true;

  @override
  Future<AuthResponse> signInAnonymously() async {
    _user = const User(
      id: 'guest-user',
      appMetadata: {},
      userMetadata: null,
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
      isAnonymous: true,
    );
    return AuthResponse(user: _user);
  }

  @override
  Future<AuthResponse> convertAnonymousToPermanent({
    required String email,
    required String password,
  }) async {
    emailCalls += 1;
    this.email = email;
    this.password = password;
    _user = _boundUser;
    return AuthResponse(user: _boundUser);
  }

  @override
  Future<AuthResponse> bindAnonymousWithGoogle() async {
    googleCalls += 1;
    _user = _boundUser;
    return AuthResponse(user: _boundUser);
  }

  @override
  Future<void> clearStoredGuestSession() async {}
}
