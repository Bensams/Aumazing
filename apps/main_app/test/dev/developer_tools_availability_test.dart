import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/dev/developer_tools_config.dart';
import 'package:aumazing/dev/developer_tools_overlay.dart';

/// The toolbox is a debug-only affordance that can create assessment records
/// and unlock Premium gates. What keeps that safe is not the UI — it is that
/// the feature does not exist unless a build explicitly asks for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => DeveloperToolsConfig.debugAvailableOverride = null);

  group('feature gate', () {
    test('the define defaults to off', () {
      // This suite is compiled without --dart-define=ENABLE_DEVELOPER_TOOLS,
      // which is exactly how a production build is compiled.
      expect(DeveloperToolsConfig.enabled, isFalse);
    });

    test('availability is the define AND debug mode', () {
      expect(DeveloperToolsConfig.isAvailable, kDebugMode && DeveloperToolsConfig.enabled);
      // Tests run in debug, so the define alone decides here — and it is off.
      expect(kDebugMode, isTrue);
      expect(DeveloperToolsConfig.isAvailable, isFalse,
          reason: 'debug mode alone must not switch the toolbox on');
    });
  });

  group('widget tree', () {
    Widget app() => MaterialApp(
          navigatorKey: DeveloperToolsOverlay.navigatorKey,
          builder: DeveloperToolsOverlay.wrap,
          home: const Scaffold(body: Text('app content')),
        );

    testWidgets('nothing is added when the toolbox is unavailable',
        (tester) async {
      DeveloperToolsConfig.debugAvailableOverride = false;

      await tester.pumpWidget(app());

      expect(find.text('app content'), findsOneWidget);
      expect(find.text('DEV'), findsNothing);
      expect(find.byType(DeveloperToolsOverlay), findsNothing,
          reason: 'absent from the tree, not merely invisible');
      expect(DeveloperToolsOverlay.navigatorKey, isNull,
          reason: 'the app keeps its own navigator behaviour');
    });

    testWidgets('the floating DEV button appears when available',
        (tester) async {
      DeveloperToolsConfig.debugAvailableOverride = true;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(app());

      expect(find.text('app content'), findsOneWidget);
      expect(find.text('DEV'), findsOneWidget);
      expect(find.byType(DeveloperToolsOverlay), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Developer tools')),
        findsOneWidget,
        reason: 'the button is reachable and self-identifying',
      );
      expect(find.byTooltip('Developer Tools (debug build only)'),
          findsOneWidget);
      expect(DeveloperToolsOverlay.navigatorKey, isNotNull);
      semantics.dispose();
    });

    testWidgets('wrap returns the child untouched when unavailable',
        (tester) async {
      DeveloperToolsConfig.debugAvailableOverride = false;
      const child = SizedBox.shrink();

      late Widget wrapped;
      await tester.pumpWidget(
        Builder(builder: (context) {
          wrapped = DeveloperToolsOverlay.wrap(context, child);
          return const SizedBox.shrink();
        }),
      );

      expect(identical(wrapped, child), isTrue);
    });
  });
}
