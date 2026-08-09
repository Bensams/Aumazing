import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/settings/settings_screen.dart';
import 'package:aumazing/features/settings/widgets/background_picker.dart';
import 'package:aumazing/features/settings/widgets/object_style_picker.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The background and object editors carry a colour wheel and a live game
/// preview each. Inline in Child Preferences they buried every shorter
/// setting under them, so they moved behind one row in the Background Theme
/// card. These tests pin that route: the row is reachable, it opens the
/// editors, and both are still there on their own tabs.
void main() {
  final profile = ChildProfile(
    id: 'child-1',
    userId: 'user-1',
    displayName: 'Test',
    birthDate: DateTime(2022, 4, 20),
    avatar: 'bear',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  Future<void> openChildPreferences(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChildProvider>.value(
            value: _TestChildProvider(profile),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SettingsScreen(
            authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Child Preferences'));
    await tester.pumpAndSettle();
  }

  testWidgets('the editors are not inline in Child Preferences',
      (tester) async {
    await openChildPreferences(tester);

    // The whole point of the move: this list stays short.
    expect(find.byType(BackgroundPicker), findsNothing);
    expect(find.byType(ObjectStylePicker), findsNothing);
    expect(find.text('Background Theme'), findsOneWidget);
  });

  testWidgets('the row opens the editors on two tabs', (tester) async {
    await openChildPreferences(tester);

    await tester.tap(find.text('Customise background and objects'));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    // Background tab is showing first.
    expect(find.byType(BackgroundPicker), findsOneWidget);

    await tester.tap(find.text('Game objects'));
    await tester.pumpAndSettle();
    expect(find.byType(ObjectStylePicker), findsOneWidget);
  });

  testWidgets('the row summarises the current state without opening it',
      (tester) async {
    await openChildPreferences(tester);

    // Defaults: no custom background, objects outlined solid.
    expect(find.text('Theme background · solid outline'), findsOneWidget);
  });

  testWidgets('the row is a named target of at least 48dp', (tester) async {
    final handle = tester.ensureSemantics();
    await openChildPreferences(tester);

    final row = find.ancestor(
      of: find.text('Customise background and objects'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(row).height,
        greaterThanOrEqualTo(kMinInteractiveDimension));
    expect(
      find.bySemanticsLabel(RegExp('Customise background and objects')),
      findsOneWidget,
    );
    handle.dispose();
  });
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider(this._profile)
      : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  final ChildProfile _profile;

  @override
  ChildProfile? get profile => _profile;

  @override
  bool get hasProfile => true;
}

class _FakeSupabaseAuthClient implements SupabaseAuthClient {
  @override
  Session? get currentSession => null;

  @override
  User? get currentUser => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
