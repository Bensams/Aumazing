import 'package:admin_portal/auth/admin_auth.dart';
import 'package:admin_portal/data/questionnaire_api.dart';
import 'package:admin_portal/pages/questionnaires_page.dart';
import 'package:admin_portal/pages/template_editor_page.dart';
import 'package:admin_portal/screens/admin_shell.dart';
import 'package:admin_portal/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:questionnaire_core/questionnaire_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _e2eEnabled = bool.fromEnvironment('E2E_TEST_MODE');
const _screenshotsEnabled = bool.fromEnvironment(
  'E2E_SCREENSHOTS',
  defaultValue: true,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('password login exercises browser controls and error feedback', (
    tester,
  ) async {
    expect(_e2eEnabled, isTrue);
    final auth = _FakeAuth()..passwordError = const AuthException('Denied');
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth)));

    await tester.enterText(find.byType(TextField).first, ' user@example.test ');
    await tester.enterText(find.byType(TextField).last, 'incorrect');
    await tester.tap(find.byKey(const Key('admin-email-sign-in')));
    await tester.pumpAndSettle();

    expect(auth.email, 'user@example.test');
    expect(auth.password, 'incorrect');
    expect(find.text('Denied'), findsOneWidget);
  });

  testWidgets('practitioner copies, previews, and saves a home questionnaire', (
    tester,
  ) async {
    expect(_e2eEnabled, isTrue);
    final api = _FakeApi(
      application: const {
        'status': 'approved',
        'full_name': 'Test Practitioner',
        'profession': 'SPED teacher',
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.deepPurple,
        ),
        home: AdminShell(api: api, onSignOut: () async {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Questionnaires'), findsWidgets);
    expect(find.text('Payments'), findsNothing);
    await tester.tap(find.byKey(const Key('questionnaires.builtIn.edit.home')));
    await tester.pumpAndSettle();

    expect(find.byType(TemplateEditorPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('editor.openPreview')));
    await tester.pumpAndSettle();
    expect(find.text('Preview as a parent'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Often').first);
    await tester.pump();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Often').first)
          .selected,
      isTrue,
    );
    expect(api.inserted, isEmpty);
    await tester.tap(find.byTooltip('Close preview'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editor.save')));
    await tester.pumpAndSettle();
    expect(api.inserted, hasLength(1));
    expect(api.inserted.single['kind'], 'home');
    expect(api.inserted.single['items'], kDefaultHomeTemplate['items']);
  });

  testWidgets(
    'administrator validates and activates without duplicate writes',
    (tester) async {
      expect(_e2eEnabled, isTrue);
      final api = _FakeApi(admin: true, templates: [_template()]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: QuestionnairesPage(api: api, isAdmin: true)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'questionnaires.validate.t1');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'questionnaires.activate.t1');
      await tester.pumpAndSettle();

      expect(api.statuses, [('t1', 'validated')]);
      expect(api.activated, [('t1', true)]);
    },
  );

  testWidgets('narrow editor remains scrollable and produces visual evidence', (
    tester,
  ) async {
    expect(_e2eEnabled, isTrue);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeApi();
    final watch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateEditorPage(
          api: api,
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
    watch.stop();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('editor.openPreview')), findsOneWidget);
    expect(find.byKey(const Key('editor.save')), findsOneWidget);
    expect(
      watch.elapsed,
      lessThan(const Duration(milliseconds: 2500)),
      reason: 'Hermetic portal editor should become interactive within 2.5 s.',
    );
    if (_screenshotsEnabled) {
      final screenshot = await binding.takeScreenshot('portal-editor-390x844');
      expect(screenshot, isNotEmpty);
    }
    binding.reportData = {
      'editor_interactive_ms': watch.elapsedMilliseconds,
      'viewport': '390x844',
      'backend': 'in_memory_fake',
    };
  });
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Map<String, dynamic> _template() => {
  'id': 't1',
  'template_key': 'session_observation',
  'version': 1,
  'kind': 'observation',
  'questionnaire_type': 'both',
  'title': 'What did you see?',
  'intro': '',
  'items': kDefaultObservationTemplate.itemsJson(),
  'status': 'draft',
  'is_active': false,
  'authored_by': 'me',
  'updated_at': '2026-09-28T10:00:00Z',
};

class _FakeAuth implements AdminAuth {
  String? email;
  String? password;
  AuthException? passwordError;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    this.email = email;
    this.password = password;
    if (passwordError != null) throw passwordError!;
  }

  @override
  Future<bool> signInWithGoogle({required String redirectTo}) async => true;
}

class _FakeApi implements QuestionnaireApi {
  _FakeApi({
    this.admin = false,
    this.application,
    List<Map<String, dynamic>>? templates,
  }) : _templates = templates ?? [];

  final bool admin;
  final Map<String, dynamic>? application;
  final List<Map<String, dynamic>> _templates;
  final inserted = <Map<String, dynamic>>[];
  final statuses = <(String, String)>[];
  final activated = <(String, bool)>[];

  @override
  String? get userId => 'me';

  @override
  Future<bool> isAdmin() async => admin;

  @override
  Future<Map<String, dynamic>?> myPractitioner() async => application;

  @override
  Future<void> apply({
    required String fullName,
    required String profession,
    String? licenseNumber,
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> practitioners() async => const [];

  @override
  Future<void> setPractitionerStatus(String userId, String status) async {}

  @override
  Future<List<Map<String, dynamic>>> templates() async => _templates;

  @override
  Future<void> insertTemplate(Map<String, dynamic> row) async {
    inserted.add(row);
  }

  @override
  Future<void> updateTemplate(String id, Map<String, dynamic> fields) async {}

  @override
  Future<void> setActive(Map<String, dynamic> template, bool active) async {
    activated.add(('${template['id']}', active));
  }

  @override
  Future<void> setStatus(String id, String status) async {
    statuses.add((id, status));
  }
}
