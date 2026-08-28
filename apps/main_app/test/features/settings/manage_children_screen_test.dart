import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/features/settings/manage_children_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/progress_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_auth.dart';

/// AUM-150 — the parent-facing profile list: who is on the account, who is
/// active, and switching between them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChildProfile child(
    String id,
    String name, {
    required DateTime createdAt,
    DateTime? birthDate,
  }) =>
      ChildProfile(
        id: id,
        userId: 'user-1',
        displayName: name,
        birthDate: birthDate ?? DateTime(2020, 3, 4),
        avatar: '🐻',
        createdAt: createdAt,
        updatedAt: createdAt,
      );

  Future<ChildProvider> pumpScreen(
    WidgetTester tester,
    List<ChildProfile> children,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final childProvider = ChildProvider(
      localDb: _FakeLocalDb(children),
      authService: FakeAuthService.boundAccount(),
    );
    await childProvider.loadProfile();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChildProvider>.value(value: childProvider),
          ChangeNotifierProvider<AssessmentProvider>(
            create: (_) => AssessmentProvider(localDb: _FakeLocalDb(children)),
          ),
          ChangeNotifierProvider<ProgressProvider>(
            create: (_) => ProgressProvider(),
          ),
          Provider<AudioService>(create: (_) => _FakeAudioService()),
        ],
        child: const MaterialApp(home: ManageChildrenScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return childProvider;
  }

  testWidgets('lists every child with their age and marks the active one',
      (tester) async {
    final today = DateTime.now();
    await pumpScreen(tester, [
      child('a', 'Ana', createdAt: DateTime(2026, 1, 1),
          birthDate: DateTime(today.year - 5, 1, 2)),
      // Deliberately older than the former 2–6 limit.
      child('b', 'Bea', createdAt: DateTime(2026, 2, 1),
          birthDate: DateTime(today.year - 12, 1, 2)),
    ]);

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Bea'), findsOneWidget);
    expect(find.textContaining('Age 5'), findsOneWidget);
    expect(find.textContaining('Age 12'), findsOneWidget);
    // Exactly one profile is presented as active.
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Tap to make active'), findsOneWidget);
    expect(find.byKey(const Key('add-child-button')), findsOneWidget);
  });

  testWidgets('tapping another child makes it the active profile',
      (tester) async {
    final provider = await pumpScreen(tester, [
      child('a', 'Ana', createdAt: DateTime(2026, 1, 1)),
      child('b', 'Bea', createdAt: DateTime(2026, 2, 1)),
    ]);
    expect(provider.activeChildId, 'a');

    await tester.tap(find.text('Bea'));
    await tester.pumpAndSettle();

    expect(provider.activeChildId, 'b');
    expect(find.text('Bea is now the active profile.'), findsOneWidget);
    // The badge moved with the selection rather than being duplicated.
    expect(find.text('Active'), findsOneWidget);
    // Past AudioService's 4s native-operation backstop from the child
    // switch's updateConfig, so no pending timer is left behind.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('deleting asks for parent verification before anything happens',
      (tester) async {
    final provider = await pumpScreen(tester, [
      child('a', 'Ana', createdAt: DateTime(2026, 1, 1)),
      child('b', 'Bea', createdAt: DateTime(2026, 2, 1)),
    ]);

    await tester.tap(find.byTooltip('Delete Bea'));
    await tester.pumpAndSettle();

    // The parent gate is up and nothing has been deleted yet.
    expect(find.byType(Dialog), findsWidgets);
    expect(find.byKey(const Key('confirm-delete-child')), findsNothing);
    expect(provider.children, hasLength(2));
  });
}

class _FakeLocalDb extends LocalDbService {
  _FakeLocalDb(this._children);

  final List<ChildProfile> _children;

  @override
  Future<List<ChildProfile>> getChildren({
    String? userId,
    bool includeDeleted = false,
  }) async =>
      _children;
}

class _FakeAudioService extends AudioService {
  _FakeAudioService() : super(config: const AudioConfig());
}
