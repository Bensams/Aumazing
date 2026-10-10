import 'package:admin_portal/auth/admin_auth.dart';
import 'package:admin_portal/data/questionnaire_api.dart';
import 'package:admin_portal/pages/template_editor_page.dart';
import 'package:admin_portal/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questionnaire_core/questionnaire_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login reflows and remains keyboard-operable', (tester) async {
    final auth = _FakeAuth();
    for (final configuration in const [
      (Size(360, 800), 1.0),
      (Size(768, 1024), 1.3),
      (Size(1440, 900), 2.0),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = configuration.$1;
      tester.platformDispatcher.textScaleFactorTestValue = configuration.$2;
      await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth)));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '${configuration.$1} at ${configuration.$2}x text',
      );
      expect(find.byKey(const Key('admin-email-sign-in')), findsOneWidget);
    }

    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'admin@example.test');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.enterText(find.byType(TextField).last, 'test-password');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(auth.passwordCalls, 1);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('login satisfies automated accessibility guidelines', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: _FakeAuth())));
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets('questionnaire editor keeps actions reachable at every width', (
    tester,
  ) async {
    for (final size in const [
      Size(360, 800),
      Size(768, 1024),
      Size(1280, 800),
      Size(1440, 900),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: TemplateEditorPage(
            api: _FakeApi(),
            isAdmin: false,
            asNewVersionOf: {
              ...kDefaultHomeTemplate,
              'kind': 'home',
              'version': 1,
              'questionnaire_type': 'both',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.byKey(const Key('editor.openPreview')), findsOneWidget);
      expect(find.byKey(const Key('editor.save')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('3. Preview and save'),
        800,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      expect(find.text('3. Preview and save'), findsOneWidget);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _FakeAuth implements AdminAuth {
  int passwordCalls = 0;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    passwordCalls++;
  }

  @override
  Future<bool> signInWithGoogle({required String redirectTo}) async => true;
}

class _FakeApi implements QuestionnaireApi {
  @override
  String? get userId => 'quality-user';

  @override
  Future<void> apply({
    required String fullName,
    required String profession,
    String? licenseNumber,
  }) async {}

  @override
  Future<void> insertTemplate(Map<String, dynamic> row) async {}

  @override
  Future<bool> isAdmin() async => false;

  @override
  Future<Map<String, dynamic>?> myPractitioner() async => const {
    'status': 'approved',
  };

  @override
  Future<List<Map<String, dynamic>>> practitioners() async => const [];

  @override
  Future<void> setActive(Map<String, dynamic> template, bool active) async {}

  @override
  Future<void> setPractitionerStatus(String userId, String status) async {}

  @override
  Future<void> setStatus(String id, String status) async {}

  @override
  Future<List<Map<String, dynamic>>> templates() async => const [];

  @override
  Future<void> updateTemplate(String id, Map<String, dynamic> fields) async {}
}
