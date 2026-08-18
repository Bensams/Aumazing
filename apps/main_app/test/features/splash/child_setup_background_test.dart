import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/splash/auth/child_profile_setup_screen.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The game background is offered while the child's own details are being
/// filled in, not only after a parent finds Settings. The parents who need
/// it — a child who cannot pick the yellow shapes out of a pale screen —
/// need it from the first game.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: ChildProfileSetupScreen()),
    );
    await tester.pump();
  }

  group('the section on step 1', () {
    testWidgets('portrait offers it, collapsed and optional', (tester) async {
      await pumpAt(tester, const Size(500, 1600));

      expect(find.text('Game screen background'), findsOneWidget);
      expect(
        find.text('Optional — a colour is already chosen for you'),
        findsOneWidget,
      );
      // Collapsed: setup must not open on a colour wheel.
      expect(find.byType(ColorWheelPicker), findsNothing);
    });

    testWidgets('landscape offers it too', (tester) async {
      // The wide layout builds a different column; it must not disagree.
      await pumpAt(tester, const Size(1400, 1000));
      expect(find.text('Game screen background'), findsOneWidget);
    });

    testWidgets('expanding reveals the picker, and applying is remembered',
        (tester) async {
      await pumpAt(tester, const Size(500, 2400));

      await tester.tap(find.text('Game screen background'));
      await tester.pumpAndSettle();
      expect(find.byType(ColorWheelPicker), findsOneWidget);

      final apply = find.text('Use this background');
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();

      // The header now reports the choice without the parent reopening it.
      expect(find.text('Your own colour is set'), findsOneWidget);
      expect(find.text('Applied'), findsOneWidget);
    });
  });

  group('saving it against the new child', () {
    test('applyInitialBackground writes the row that has just been created',
        () async {
      final childProv = ChildProvider(
        authService: AuthService(supabaseAuth: _FakeSupabaseAuth()),
      );
      const background = ChildBackground.solid(Color(0xFF102030));

      await childProv.applyInitialBackground(
        childId: 'child-9',
        background: background,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('custom_background_child-9'),
        background.encode(),
      );
      // No profile is loaded yet during setup, so the new child's background
      // is also what the app is holding in memory.
      expect(childProv.customBackground, background);
    });
  });
}

class _FakeSupabaseAuth implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
