import 'package:aumazing/features/splash/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The test font (Ahem) renders every glyph 1em wide, so some of the login
/// screen's rows overflow the test surface even though real fonts fit. This
/// suite asserts which sign-in options exist, not layout metrics, so the
/// RenderFlex-overflow flavor of FlutterError is ignored.
bool _isOverflowError(FlutterError error) =>
    error.diagnostics.any((d) => d.toString().contains('RenderFlex'));

void main() {
  setUpAll(() async {
    // Video background probes the video_player plugin during initState; the
    // login screen catches the resulting platform errors, but the channel
    // handlers keep the failures synchronous instead of async escapes.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/video_player'),
          (call) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (call) async => ['wifi'],
        );
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-publishable-key',
    );
  });

  setUp(() {
    // Marked as consented so the first-launch Data Privacy notice does not
    // cover the buttons under test.
    SharedPreferences.setMockInitialValues({
      'privacy_consent_accepted_at': '2026-01-01T00:00:00.000Z',
    });
  });

  testWidgets(
    'Facebook sign-in is removed; Google and guest sign-in remain',
    (tester) async {
      // The login layout is designed for phone proportions; the framework's
      // default test surface is much narrower than any real device.
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final realOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final error = details.exception;
        if (error is FlutterError && _isOverflowError(error)) return;
        realOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = realOnError);

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump(const Duration(milliseconds: 950));

      expect(find.textContaining('Facebook'), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue as Guest'), findsOneWidget);
    },
  );
}
