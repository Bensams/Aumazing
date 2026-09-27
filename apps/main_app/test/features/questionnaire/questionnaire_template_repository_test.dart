import 'dart:async';

import 'package:aumazing/features/questionnaire/parent_questionnaire.dart';
import 'package:aumazing/features/questionnaire/questionnaire_template_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AUM-344 — the parent questionnaire uses the practitioner-authored template
/// an admin has activated, and never fails to open.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  List<Map<String, String>> items({String prefix = 'x'}) => [
    for (final d in QuestionnaireDomain.values)
      {'id': '${prefix}_${d.key}', 'domain': d.key, 'text': 'About ${d.key}.'},
  ];

  Map<String, dynamic> row({
    String type = 'both',
    String key = 'sped_checklist',
    List<Map<String, String>>? itemList,
    String status = 'validated',
  }) => {
    'template_key': key,
    'version': 2,
    'questionnaire_type': type,
    'title': 'From your child\'s teacher',
    'intro': 'Four short questions.',
    'items': itemList ?? items(),
    'status': status,
  };

  group('parse', () {
    test('reads a well-formed template', () {
      final t = QuestionnaireTemplateRepository.parse(row())!;
      expect(t.id, 'sped_checklist');
      expect(t.version, 2);
      expect(t.isDraft, isFalse);
      expect(t.items, hasLength(4));
    });

    test('rejects an unknown domain', () {
      final bad = items()..add({'id': 'z', 'domain': 'music', 'text': 'x'});
      expect(QuestionnaireTemplateRepository.parse(row(itemList: bad)), isNull);
    });

    test('rejects duplicate item ids', () {
      final bad = items()..add(Map.of(items().first));
      expect(QuestionnaireTemplateRepository.parse(row(itemList: bad)), isNull);
    });

    test('rejects a template that leaves a domain without items', () {
      final bad = items().where((i) => i['domain'] != 'play').toList();
      expect(QuestionnaireTemplateRepository.parse(row(itemList: bad)), isNull);
    });

    test('anything not marked validated is treated as a draft', () {
      final t = QuestionnaireTemplateRepository.parse(row(status: 'weird'))!;
      expect(t.isDraft, isTrue);
    });
  });

  test('a template made for the type wins over a shared one', () {
    final picked = QuestionnaireTemplateRepository.pickActive([
      row(type: 'both', key: 'shared'),
      row(type: 'post', key: 'post_only'),
    ], 'post');
    expect(picked!['template_key'], 'post_only');
  });

  group('templateFor', () {
    test('uses the active practitioner template', () async {
      final repo = QuestionnaireTemplateRepository(
        fetcher: (_) async => [row()],
      );
      expect((await repo.templateFor('pre')).id, 'sped_checklist');
    });

    test('falls back to the bundled draft when none is active', () async {
      final repo = QuestionnaireTemplateRepository(fetcher: (_) async => []);
      expect(await repo.templateFor('pre'), same(kParentQuestionnaireDraft));
    });

    test('falls back to the bundled draft for a broken template', () async {
      final repo = QuestionnaireTemplateRepository(
        fetcher: (_) async => [row(itemList: const [])],
      );
      expect(await repo.templateFor('pre'), same(kParentQuestionnaireDraft));
    });

    test('offline, the last template seen is used', () async {
      await QuestionnaireTemplateRepository(
        fetcher: (_) async => [row()],
      ).templateFor('pre');

      final offline = QuestionnaireTemplateRepository(
        fetcher: (_) async => throw Exception('no network'),
      );
      expect((await offline.templateFor('pre')).id, 'sped_checklist');
    });

    test('a slow backend does not hold up the parent', () async {
      final never = Completer<List<Map<String, dynamic>>>();
      final repo = QuestionnaireTemplateRepository(
        fetcher: (_) => never.future,
        timeout: const Duration(milliseconds: 50),
      );
      expect(await repo.templateFor('pre'), same(kParentQuestionnaireDraft));
    });

    test('a withdrawn template is not served from the cache', () async {
      await QuestionnaireTemplateRepository(
        fetcher: (_) async => [row()],
      ).templateFor('pre');
      // The admin deactivated it: the backend now returns nothing active.
      final repo = QuestionnaireTemplateRepository(fetcher: (_) async => []);
      expect(await repo.templateFor('pre'), same(kParentQuestionnaireDraft));
      // And going offline afterwards does not resurrect it.
      final offline = QuestionnaireTemplateRepository(
        fetcher: (_) async => throw Exception('no network'),
      );
      expect(await offline.templateFor('pre'), same(kParentQuestionnaireDraft));
    });
  });
}
