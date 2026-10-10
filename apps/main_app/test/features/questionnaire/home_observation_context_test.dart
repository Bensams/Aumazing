import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:aumazing/features/questionnaire/home_observation_context.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire.dart';
import 'package:aumazing/services/overall_gameplay_summary_service.dart';
import 'package:aumazing/services/assessment_summary_service.dart';

void main() {
  final runs = <HomeAssessmentLink>[
    (id: 'pre1', type: 'pre', completedAt: DateTime(2026, 1, 1)),
    (id: 'post1', type: 'post', completedAt: DateTime(2026, 2, 1)),
    (id: 'pre2', type: 'pre', completedAt: DateTime(2026, 3, 1)),
  ];
  Map<String, dynamic> row(
    String run,
    String phase,
    String date, {
    String child = 'child1',
    int version = 1,
    String? signature,
    Object? score = 75,
  }) => {
    'child_id': child,
    'assessment_run_id': run,
    'questionnaire_type': phase,
    'completed_at': date,
    'responses': jsonEncode({
      'template_id': 'home',
      'template_version': version,
      'template_status': 'draft',
      if (signature != null) 'schema_signature': signature,
      'domain_scores': {'communication': score, 'play': null},
    }),
  };
  final pre = row('pre1', 'pre', '2026-01-01');
  final post = row('post1', 'post', '2026-02-01');
  HomeObservationContext context(
    List<Map<String, dynamic>> rows, {
    String? run = 'post1',
  }) => HomeObservationContext.fromRows(
    rows: rows,
    runs: runs,
    childId: 'child1',
    currentRunId: run,
  );

  test('only matching child, run and phase are used; skip stays empty', () {
    expect(context([pre]).isEmpty, isTrue);
    expect(context([pre, post], run: 'pre2').isEmpty, isTrue);
    expect(
      context([row('post1', 'post', '2026-02-01', child: 'other')]).isEmpty,
      isTrue,
    );
    expect(context([row('post1', 'pre_intake', '2026-02-01')]).isEmpty, isTrue);
    expect(context([row('unlinked', 'post', '2026-02-01')]).isEmpty, isTrue);
  });
  test(
    'compatible reports in the same cycle compare without transmitting IDs',
    () {
      final payload = context([post, pre]).toPayload();
      final records = payload['observations'] as List;
      expect(records, hasLength(2));
      expect(records.last['comparable_to_pre'], true);
      expect(records.last['cycle'], 1);
      expect(records.last['domain_frequencies'], [
        {'name': 'Communication', 'frequency_pct': 75.0},
      ]);
      final encoded = jsonEncode(payload);
      for (final id in [
        'child1',
        'pre1',
        'post1',
        'template_id',
        'schema_signature',
      ]) {
        expect(encoded, isNot(contains(id)));
      }
    },
  );
  test('changed legacy revisions do not compare', () {
    final payload =
        context([
          pre,
          row('post1', 'post', '2026-02-01', version: 2),
        ]).toPayload();
    expect((payload['observations'] as List).last['comparable_to_pre'], false);
  });
  test('unchanged item signatures compare across title-only revisions', () {
    final payload =
        context([
          row('pre1', 'pre', '2026-01-01', signature: 'same'),
          row('post1', 'post', '2026-02-01', version: 2, signature: 'same'),
        ]).toPayload();
    expect((payload['observations'] as List).last['comparable_to_pre'], true);
  });
  test('a new cycle never compares to a previous cycle', () {
    final payload =
        context([
          pre,
          post,
          row('pre2', 'pre', '2026-03-01'),
        ], run: null).toPayload();
    expect((payload['observations'] as List).last['comparable_to_pre'], false);
  });
  test('invalid frequencies cannot turn missing answers into zero', () {
    for (final invalid in [null, -1, 101, '75']) {
      expect(
        context([row('post1', 'post', '2026-02-01', score: invalid)]).isEmpty,
        true,
      );
    }
    expect(
      context([row('post1', 'post', '2026-02-01', score: 0)]).isEmpty,
      false,
    );
  });
  test('home changes refresh both summaries without changing game results', () {
    GameplaySummaryInput overall(List<Map<String, dynamic>> rows) =>
        OverallGameplaySummaryService.assemble(
          runs: runs,
          results: [],
          sessions: [],
          childId: 'child1',
          questionnaireRows: rows,
        );
    final skipped = overall([]);
    final answered = overall([pre]);
    expect(skipped.toPayload().containsKey('parent_context'), false);
    expect(answered.fingerprint, isNot(skipped.fingerprint));
    expect(
      answered.toPayload()['assessments'],
      skipped.toPayload()['assessments'],
    );
    expect(
      OverallGameplaySummaryService.buildFallback(answered).summary,
      contains('parent-reported frequency ratings'),
    );
    String key(Map<String, dynamic>? home, String scope) =>
        AssessmentSummaryService.debugCacheKey(
          [],
          75,
          'moderate',
          [],
          'en',
          home,
          scope,
        );
    expect(
      key(null, 'child:run'),
      isNot(key(context([post]).toPayload(), 'child:run')),
    );
    expect(key(null, 'child:run'), isNot(key(null, 'other:run')));
  });
  test('item signature ignores ordering but detects a changed statement', () {
    QuestionnaireTemplate template(List<QuestionnaireItem> items) =>
        QuestionnaireTemplate(
          id: 'home',
          version: 1,
          status: 'draft',
          title: 'Home',
          intro: '',
          items: items,
        );
    final base = kParentQuestionnaireDraft.items;
    expect(
      questionnaireSchemaSignature(template(base)),
      questionnaireSchemaSignature(template(base.reversed.toList())),
    );
    expect(
      questionnaireSchemaSignature(template(base)),
      isNot(
        questionnaireSchemaSignature(
          template([
            QuestionnaireItem(
              id: base.first.id,
              domain: base.first.domain,
              text: 'Changed',
            ),
            ...base.skip(1),
          ]),
        ),
      ),
    );
  });
}
