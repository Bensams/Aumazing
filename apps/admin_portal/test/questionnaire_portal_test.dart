import 'package:admin_portal/data/questionnaire_api.dart';
import 'package:admin_portal/pages/practitioners_page.dart';
import 'package:admin_portal/pages/questionnaires_page.dart';
import 'package:admin_portal/pages/template_editor_page.dart';
import 'package:admin_portal/screens/admin_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questionnaire_core/questionnaire_core.dart';

/// AUM-352 — practitioners write the questionnaires in the portal;
/// administrators approve practitioners and choose what is in use.
class _FakeApi implements QuestionnaireApi {
  _FakeApi({this.admin = false, this.application, List<Map<String, dynamic>>? templates})
    : _templates = templates ?? [];

  bool admin;
  Map<String, dynamic>? application;
  final List<Map<String, dynamic>> _templates;
  final inserted = <Map<String, dynamic>>[];
  final updated = <(String, Map<String, dynamic>)>[];
  final activated = <(String, bool)>[];
  final statuses = <(String, String)>[];
  final practitionerStatuses = <(String, String)>[];
  List<Map<String, dynamic>> practitionerRows = [];

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
  }) async {
    application = {
      'user_id': 'me',
      'full_name': fullName,
      'profession': profession,
      'license_number': licenseNumber,
      'status': 'pending',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> practitioners() async => practitionerRows;

  @override
  Future<void> setPractitionerStatus(String userId, String status) async =>
      practitionerStatuses.add((userId, status));

  @override
  Future<List<Map<String, dynamic>>> templates() async => _templates;

  @override
  Future<void> insertTemplate(Map<String, dynamic> row) async =>
      inserted.add(row);

  @override
  Future<void> updateTemplate(String id, Map<String, dynamic> fields) async =>
      updated.add((id, fields));

  @override
  Future<void> setActive(Map<String, dynamic> template, bool active) async =>
      activated.add(('${template['id']}', active));

  @override
  Future<void> setStatus(String id, String status) async =>
      statuses.add((id, status));
}

Map<String, dynamic> _template({
  String id = 't1',
  String kind = 'observation',
  bool active = false,
  String authoredBy = 'me',
}) => {
  'id': id,
  'template_key': 'sped_after',
  'version': 1,
  'kind': kind,
  'questionnaire_type': 'both',
  'title': 'What did you see?',
  'intro': '',
  'items': kDefaultObservationTemplate.itemsJson(),
  'status': 'draft',
  'is_active': active,
  'authored_by': authoredBy,
  'updated_at': '2026-09-28T10:00:00Z',
};

void main() {
  Future<void> pumpSized(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Pages sit inside the shell's Scaffold in the portal.
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  group('who sees what', () {
    testWidgets('an approved practitioner sees only questionnaires', (
      tester,
    ) async {
      await pumpSized(
        tester,
        AdminShell(
          api: _FakeApi(application: {'status': 'approved', 'full_name': 'Lea'}),
          onSignOut: () async {},
        ),
      );
      expect(find.text('Questionnaires'), findsWidgets);
      expect(find.text('My details'), findsOneWidget);
      expect(find.text('Payments'), findsNothing);
      expect(find.text('Practitioners'), findsNothing);
    });

    testWidgets('an administrator also reviews practitioners', (tester) async {
      await pumpSized(
        tester,
        AdminShell(api: _FakeApi(admin: true), onSignOut: () async {}),
      );
      final rail = find.byType(NavigationRail);
      expect(
        find.descendant(of: rail, matching: find.text('Questionnaires')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rail, matching: find.text('Practitioners')),
        findsOneWidget,
      );
    });

    testWidgets('anyone else can apply, then waits for review', (tester) async {
      final api = _FakeApi();
      await pumpSized(tester, AdminShell(api: api, onSignOut: () async {}));
      expect(find.text('Apply as a practitioner'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('access.name')), 'Lea Famor');
      await tester.enterText(
        find.byKey(const Key('access.profession')),
        'SPED teacher',
      );
      await tester.tap(find.byKey(const Key('access.apply')));
      await tester.pumpAndSettle();

      expect(api.application?['full_name'], 'Lea Famor');
      expect(find.byKey(const Key('access.pending')), findsOneWidget);
    });
  });

  group('the questionnaire list', () {
    testWidgets('groups templates by question set; empty ones use built-in', (
      tester,
    ) async {
      await pumpSized(
        tester,
        QuestionnairesPage(
          api: _FakeApi(templates: [_template()]),
          isAdmin: false,
        ),
      );
      expect(find.text('After the session'), findsOneWidget);
      expect(
        find.text('None yet — the app uses its built-in questions.'),
        findsNWidgets(2),
      );
      // Practitioners cannot activate.
      expect(find.byKey(const Key('questionnaires.activate.t1')), findsNothing);
    });

    testWidgets('an administrator puts a template in use and validates it', (
      tester,
    ) async {
      final api = _FakeApi(admin: true, templates: [_template()]);
      await pumpSized(tester, QuestionnairesPage(api: api, isAdmin: true));

      await tester.tap(find.byKey(const Key('questionnaires.activate.t1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('questionnaires.validate.t1')));
      await tester.pumpAndSettle();

      expect(api.activated, [('t1', true)]);
      expect(api.statuses, [('t1', 'validated')]);
    });

    testWidgets('a practitioner cannot edit someone else\'s template', (
      tester,
    ) async {
      await pumpSized(
        tester,
        QuestionnairesPage(
          api: _FakeApi(templates: [_template(authoredBy: 'other')]),
          isAdmin: false,
        ),
      );
      expect(find.byKey(const Key('questionnaires.edit.t1')), findsNothing);
      // They can still start their own version from it.
      expect(find.byKey(const Key('questionnaires.copy.t1')), findsOneWidget);
    });
  });

  group('the editor', () {
    bool saveEnabled(WidgetTester tester) =>
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('editor.save')))
            .onPressed !=
        null;

    testWidgets('starts from the built-in questions and saves them', (
      tester,
    ) async {
      final api = _FakeApi();
      await pumpSized(tester, TemplateEditorPage(api: api, isAdmin: false));

      // Nothing to save yet: no name, title or questions.
      expect(find.byKey(const Key('editor.errors')), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tester.tap(find.text('After the session'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor.builtIn')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('editor.key')), 'sped_after');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('editor.errors')), findsNothing);
      await tester.tap(find.byKey(const Key('editor.save')));
      await tester.pumpAndSettle();

      final row = api.inserted.single;
      expect(row['kind'], 'observation');
      expect(row['template_key'], 'sped_after');
      expect(row['version'], 1);
      expect(row['title'], 'What did you see?');
      // What the portal saves is exactly what the app accepts.
      expect(
        ChoiceTemplate.validateItems(TemplateKind.observation, row['items']),
        isEmpty,
      );
      expect(row['items'], kDefaultObservationTemplate.itemsJson());
    });

    testWidgets('home questions need every area before saving', (tester) async {
      final api = _FakeApi();
      await pumpSized(tester, TemplateEditorPage(api: api, isAdmin: true));
      await tester.enterText(find.byKey(const Key('editor.key')), 'home_v');
      await tester.tap(find.byKey(const Key('editor.addQuestion')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Add at least one question for Play Skills'),
        findsOneWidget,
      );
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('editing an in-use template warns a practitioner', (
      tester,
    ) async {
      final api = _FakeApi();
      await pumpSized(
        tester,
        TemplateEditorPage(
          api: api,
          isAdmin: false,
          existing: _template(active: true),
        ),
      );
      expect(find.textContaining('takes it out of use'), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor.save')));
      await tester.pumpAndSettle();
      expect(api.updated.single.$1, 't1');
      expect(api.updated.single.$2['kind'], 'observation');
      expect(api.inserted, isEmpty);
    });

    testWidgets('a new version copies the questions and bumps the version', (
      tester,
    ) async {
      final api = _FakeApi();
      await pumpSized(
        tester,
        TemplateEditorPage(api: api, isAdmin: false, asNewVersionOf: _template()),
      );
      await tester.tap(find.byKey(const Key('editor.save')));
      await tester.pumpAndSettle();
      expect(api.inserted.single['version'], 2);
      expect(api.inserted.single['template_key'], 'sped_after');
    });
  });

  testWidgets('an administrator approves a practitioner', (tester) async {
    final api = _FakeApi(admin: true)
      ..practitionerRows = [
        {
          'user_id': 'p1',
          'full_name': 'Lea Famor',
          'profession': 'SPED teacher',
          'license_number': '0012345',
          'status': 'pending',
          'created_at': '2026-09-28T10:00:00Z',
        },
      ];
    await pumpSized(tester, PractitionersPage(api: api));
    expect(find.text('Lea Famor · SPED teacher'), findsOneWidget);
    await tester.tap(find.byKey(const Key('practitioners.approve.p1')));
    await tester.pumpAndSettle();
    expect(api.practitionerStatuses, [('p1', 'approved')]);
  });
}
