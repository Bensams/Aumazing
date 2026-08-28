import 'package:admin_portal/auth/admin_auth.dart';
import 'package:admin_portal/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAdminAuth implements AdminAuth {
  _FakeAdminAuth({this.onGoogle});

  Future<bool> Function(String redirectTo)? onGoogle;

  String? lastRedirectTo;
  int googleCalls = 0;

  @override
  Future<bool> signInWithGoogle({required String redirectTo}) async {
    googleCalls += 1;
    lastRedirectTo = redirectTo;
    if (onGoogle != null) return onGoogle!(redirectTo);
    return true;
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {}
}

void main() {
  testWidgets('keeps email/password sign-in and shows Continue with Google', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(auth: _FakeAdminAuth())),
    );

    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byKey(const Key('admin-email-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('admin-google-sign-in')), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
  });

  testWidgets('Google button invokes OAuth with a browser-safe redirect', (
    tester,
  ) async {
    final fake = _FakeAdminAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          auth: fake,
          currentUri: Uri.parse(
            'http://localhost:1234/#access_token=should-not-leak',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('admin-google-sign-in')));
    await tester.pump();

    expect(fake.googleCalls, 1);
    expect(fake.lastRedirectTo, 'http://localhost:1234/');
    expect(fake.lastRedirectTo, isNot(contains('access_token')));
  });

  testWidgets('OAuth AuthException stays on the login form with the error', (
    tester,
  ) async {
    final fake = _FakeAdminAuth(
      onGoogle: (_) async =>
          throw AuthException('Google provider is not enabled'),
    );
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: fake)));

    await tester.tap(find.byKey(const Key('admin-google-sign-in')));
    await tester.pump();

    expect(find.text('Google provider is not enabled'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('failed OAuth launch shows an error instead of a blank screen', (
    tester,
  ) async {
    final fake = _FakeAdminAuth(onGoogle: (_) async => false);
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: fake)));

    await tester.tap(find.byKey(const Key('admin-google-sign-in')));
    await tester.pump();

    expect(
      find.text('Could not open Google sign-in. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('OAuth redirect error is shown on load', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          auth: _FakeAdminAuth(),
          currentUri: Uri.parse(
            'http://localhost:1234/?error=access_denied&error_description=User+cancelled',
          ),
        ),
      ),
    );

    expect(find.text('User cancelled'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
