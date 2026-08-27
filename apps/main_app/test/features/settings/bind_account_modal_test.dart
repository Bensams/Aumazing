import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/settings/bind_account_modal.dart';
import '../../support/fake_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() {
    AuthService(supabaseAuth: NoopSupabaseAuthClient()).clearGuestMode();
  });

  testWidgets('email binding clears guest state and centers its label', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      const {'active_child_guest-user': 'child-1'},
    );
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
    await _expectBoundState(auth);
  });

  testWidgets('Google binding clears guest state and uses response identity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      const {'active_child_guest-user': 'child-1'},
    );
    final auth = _BindingTestAuth();
    auth.initializeGuestMode();
    await _pumpModal(tester, auth);

    await tester.tap(find.text('Bind with Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(auth.googleCalls, 1);
    await _expectBoundState(auth);
  });

  testWidgets('Bind with Email label is centered when wrapped on a narrow phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      const {'active_child_guest-user': 'child-1'},
    );
    final auth = _BindingTestAuth();
    auth.initializeGuestMode();

    // Narrow phone surface so the label wraps to multiple lines.
    await tester.binding.setSurfaceSize(const Size(320, 690));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: BindAccountModal(authService: auth)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bind with Email'));
    await tester.pumpAndSettle();

    final button = find.widgetWithText(ElevatedButton, 'Bind with Email');
    final label = find.descendant(
      of: button,
      matching: find.text('Bind with Email'),
    );
    expect(button, findsOneWidget);
    expect(label, findsOneWidget);

    // The label must actually wrap, otherwise this test would not exercise
    // the centering of wrapped lines.
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(paragraph.textAlign, TextAlign.center,
        reason: 'wrapped label lines must be centered via TextAlign');

    // Geometric proof: the first line must start inset from the paragraph's
    // left edge (i.e. centered), not flush against it.
    final firstLineLeft =
        paragraph
            .getOffsetForCaret(const TextPosition(offset: 0), Rect.zero)
            .dx;
    expect(firstLineLeft, greaterThan(0),
        reason:
            'first wrapped line must start inset from the paragraph left edge');
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

Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

Future<void> _expectBoundState(_BindingTestAuth auth) async {
  expect(auth.isGuestMode, isFalse);
  expect(auth.isBoundAccount, isTrue);
  expect(auth.effectiveUserId, 'bound-user');
  expect(auth.currentUser?.isAnonymous, isFalse);
  expect(auth.storedSessionCleared, isTrue);

  final prefs = await _prefs();
  expect(prefs.getString('active_child_guest-user'), isNull);
  expect(prefs.getString('active_child_bound-user'), 'child-1');
}

class _BindingTestAuth extends AuthService {
  _BindingTestAuth() : super(supabaseAuth: NoopSupabaseAuthClient());
  @override
  String initializeGuestMode() {
    _effectiveId = 'guest-user';
    return super.initializeGuestMode();
  }

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
  String? _effectiveId;
  bool storedSessionCleared = false;
  int emailCalls = 0;
  int googleCalls = 0;
  String? email;
  String? password;

  @override
  User? get currentUser => _user;

  @override
  String? get effectiveUserId => _effectiveId ?? super.effectiveUserId;

  @override
  bool get isBoundAccount =>
      _user != null && _user?.isAnonymous != true;

  @override
  Future<AuthResponse> signInAnonymously() async {
    _user = const User(
      id: 'anonymous-user',
      appMetadata: {},
      userMetadata: null,
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
      isAnonymous: true,
    );
    _effectiveId = 'anonymous-user';
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
    _user = const User(
      id: 'current-user',
      appMetadata: {},
      userMetadata: null,
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
      isAnonymous: false,
    );
    _effectiveId = _boundUser.id;
    return AuthResponse(user: _boundUser);
  }

  @override
  Future<AuthResponse> bindAnonymousWithGoogle() async {
    googleCalls += 1;
    _user = const User(
      id: 'current-user',
      appMetadata: {},
      userMetadata: null,
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
      isAnonymous: false,
    );
    _effectiveId = _boundUser.id;
    return AuthResponse(user: _boundUser);
  }

  @override
  Future<void> clearStoredGuestSession() async {
    storedSessionCleared = true;
  }
}
