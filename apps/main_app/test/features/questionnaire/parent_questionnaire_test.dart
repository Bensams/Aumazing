import 'package:aumazing/core/services/sync_service.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire_comparison_card.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'dart:convert';

/// The parent questionnaire (pre-final defense note): what the parent sees at
/// home, in the same four domains the games report on, asked identically
/// before and after.
void main() {
  const template = kParentQuestionnaireDraft;

  group('the draft template', () {
    test('covers each of the four domains with four items', () {
      for (final domain in QuestionnaireDomain.values) {
        expect(template.itemsFor(domain), hasLength(4), reason: domain.key);
      }
      expect(template.items.map((i) => i.id).toSet(), hasLength(16),
          reason: 'item ids are stored with answers and must be unique');
    });

    test('is marked as a draft', () {
      expect(template.isDraft, isTrue);
    });
  });

  group('scoring', () {
    test('a domain score is the mean answer as a percentage', () {
      final answers = {
        for (final item in template.itemsFor(QuestionnaireDomain.play))
          item.id: Frequency.often, // 3 of 4
      };
      final scores = scoreQuestionnaire(template, answers);
      expect(scores[QuestionnaireDomain.play], 75);
    });

    test('an unanswered domain is unknown, not zero', () {
      final scores = scoreQuestionnaire(template, const {});
      for (final domain in QuestionnaireDomain.values) {
        expect(scores[domain], isNull);
      }
    });

    test('all Always is 100 and all Never is 0', () {
      final always = {
        for (final i in template.items) i.id: Frequency.always,
      };
      final never = {for (final i in template.items) i.id: Frequency.never};
      expect(scoreQuestionnaire(template, always).values.toSet(), {100});
      expect(scoreQuestionnaire(template, never).values.toSet(), {0});
    });
  });

  group('the screen', () {
    Future<(List<Map<String, dynamic>>, List<String>)> open(
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final saved = <Map<String, dynamic>>[];
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ParentQuestionnaireScreen(
            assessmentType: 'pre',
            childId: 'child-1',
            assessmentRunId: 'run-1',
            onDone: (_) => events.add('done'),
            saver: ({
              required id,
              required childId,
              required assessmentRunId,
              required questionnaireType,
              required responses,
            }) async {
              saved.add({
                'id': id,
                'child_id': childId,
                'assessment_run_id': assessmentRunId,
                'questionnaire_type': questionnaireType,
                'responses': responses,
              });
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (saved, events);
    }

    Future<void> answerAll(WidgetTester tester, Frequency f) async {
      for (final item in template.items) {
        final chip = find.byKey(Key('questionnaire.answer.${item.id}.${f.name}'));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pump();
      }
    }

    FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.byKey(const Key('questionnaire.save')),
    );

    testWidgets('says the questions are a draft', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('questionnaire.draftNote')), findsOneWidget);
    });

    testWidgets('Save waits until every question is answered', (tester) async {
      await open(tester);
      expect(saveButton(tester).onPressed, isNull);
      expect(find.text('0 of 16 answered'), findsOneWidget);

      final first = template.items.first;
      await tester.tap(
        find.byKey(Key('questionnaire.answer.${first.id}.often')),
      );
      await tester.pump();
      expect(find.text('1 of 16 answered'), findsOneWidget);
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('saving stores the answers against the child and run', (
      tester,
    ) async {
      final (saved, events) = await open(tester);
      await answerAll(tester, Frequency.sometimes);
      expect(saveButton(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('questionnaire.save')));
      await tester.pumpAndSettle();

      expect(events, ['done']);
      expect(saved, hasLength(1));
      final record = saved.single;
      expect(record['child_id'], 'child-1');
      expect(record['assessment_run_id'], 'run-1');
      expect(record['questionnaire_type'], 'pre');
      final responses = record['responses'] as Map<String, dynamic>;
      expect(responses['template_id'], template.id);
      expect(responses['template_status'], 'draft');
      expect((responses['answers'] as Map), hasLength(16));
      expect(responses['domain_scores'], {
        'communication': 50.0,
        'play': 50.0,
        'social': 50.0,
        'attention': 50.0,
      });
    });

    testWidgets('Skip for now carries on without saving', (tester) async {
      final (saved, events) = await open(tester);
      await tester.tap(find.byKey(const Key('questionnaire.skip')));
      await tester.pumpAndSettle();
      expect(events, ['done']);
      expect(saved, isEmpty);
    });
  });

  group('the before/after card', () {
    Map<String, dynamic> row(String type, String at, Map<String, double> s) => {
      'questionnaire_type': type,
      'completed_at': at,
      'responses': jsonEncode({'domain_scores': s}),
    };

    Future<void> pumpCard(
      WidgetTester tester,
      List<Map<String, dynamic>> rows,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ParentQuestionnaireComparisonCard(
              childId: 'child-1',
              loader: (_) async => rows,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the latest pre and post side by side', (tester) async {
      await pumpCard(tester, [
        row('pre', '2026-01-01', {
          'communication': 25,
          'play': 50,
          'social': 50,
          'attention': 75,
        }),
        // An older pre that must be ignored.
        row('pre', '2025-12-01', {'communication': 0}),
        row('post', '2026-03-01', {
          'communication': 75,
          'play': 50,
          'social': 25,
          'attention': 75,
        }),
      ]);

      expect(find.text('What you noticed at home'), findsOneWidget);
      expect(find.text('25 → 75'), findsOneWidget);
      expect(find.text('50 → 50'), findsOneWidget);
      expect(find.text('50 → 25'), findsOneWidget);
      expect(find.text('75 → 75'), findsOneWidget);
    });

    testWidgets('stays hidden without both questionnaires', (tester) async {
      await pumpCard(tester, [
        row('pre', '2026-01-01', {'communication': 25}),
      ]);
      expect(find.byKey(const Key('questionnaireComparison')), findsNothing);
    });
  });

  group('sync to the cloud table', () {
    test('uses the columns the live table actually has', () {
      final row = SyncService.mapQuestionnaireToSupabase({
        'id': 'q-1',
        'child_id': 'child-1',
        'assessment_run_id': 'run-1',
        'questionnaire_type': 'post',
        'responses': jsonEncode({
          'template_id': template.id,
          'domain_scores': {
            'communication': 50.0,
            'play': 75.0,
            'social': 100.0,
            'attention': 25.0,
          },
        }),
        'completed_at': '2026-09-27T10:00:00.000',
      });

      expect(row['responses_json'], isA<Map<String, dynamic>>());
      expect(row['assessment_run_id'], 'run-1');
      expect(row['completed_by_role'], 'parent');
      expect(row['created_at'], '2026-09-27T10:00:00.000');
      expect(row['social_communication_score'], 75.0,
          reason: 'the mean of communication (50) and social (100)');
      expect(row.containsKey('responses'), isFalse);
      expect(row.containsKey('completed_at'), isFalse,
          reason: 'the cloud table has no completed_at column');
    });

    test('a malformed answer blob still syncs the row identity', () {
      final row = SyncService.mapQuestionnaireToSupabase({
        'id': 'q-2',
        'child_id': 'child-1',
        'questionnaire_type': 'pre',
        'responses': 'not json',
      });
      expect(row['id'], 'q-2');
      expect(row['responses_json'], isEmpty);
      expect(row['social_communication_score'], isNull);
    });
  });
}
