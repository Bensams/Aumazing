import 'dart:convert';

import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire.dart';
import 'package:aumazing/features/questionnaire/parent_questionnaire_comparison_card.dart'
    show QuestionnaireLoader;
import 'package:aumazing/features/questionnaire/parent_questionnaire_screen.dart';
import 'package:aumazing/features/questionnaire/questionnaire_template_repository.dart';
import 'package:aumazing/features/questionnaire/setup_home_questionnaire.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The home questionnaire's "before" is asked once per child, right after the
/// profile is set up, and children set up earlier are offered it once on the
/// dashboard (AUM-364).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final repository = QuestionnaireTemplateRepository(fetcher: (_) async => []);
  Future<List<Map<String, dynamic>>> none(String _) async => [];

  Map<String, dynamic> homeReport(String? run, {String type = 'pre'}) => {
    'child_id': 'child-1',
    'assessment_run_id': run,
    'questionnaire_type': type,
    'completed_at': '2026-10-01',
    'responses': jsonEncode({
      'template_id': 'home',
      'template_version': 1,
      'domain_scores': {'communication': 50},
    }),
  };

  group('whether the dashboard offers it', () {
    test('a child never asked and with no home report is offered it', () async {
      expect(
        await SetupHomeQuestionnaire.shouldOffer('child-1', loader: none),
        isTrue,
      );
    });

    test('once asked, never again; other children are unaffected', () async {
      await SetupHomeQuestionnaire.markOffered('child-1');
      expect(
        await SetupHomeQuestionnaire.shouldOffer('child-1', loader: none),
        isFalse,
      );
      expect(
        await SetupHomeQuestionnaire.shouldOffer('child-2', loader: none),
        isTrue,
      );
    });

    test(
      'any home report, from setup or an older assessment, counts',
      () async {
        for (final run in [null, 'pre-run']) {
          expect(
            await SetupHomeQuestionnaire.shouldOffer(
              'child-1',
              loader: (_) async => [homeReport(run)],
            ),
            isFalse,
          );
        }
        // Records that are not home reports do not count.
        expect(
          await SetupHomeQuestionnaire.shouldOffer(
            'child-1',
            loader: (_) async => [homeReport(null, type: 'pre_intake')],
          ),
          isTrue,
        );
      },
    );

    test('an unreadable store stays quiet rather than nag', () async {
      expect(
        await SetupHomeQuestionnaire.shouldOffer(
          'child-1',
          loader: (_) async => throw StateError('no database'),
        ),
        isFalse,
      );
    });
  });

  group('after setup', () {
    Future<List<({String? run, String type})>> open(
      WidgetTester tester, {
      required bool replaceAll,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final saved = <({String? run, String type})>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    child: const Text('Save Child Profile'),
                    onPressed:
                        () => SetupHomeQuestionnaire.show(
                          context,
                          childId: 'child-1',
                          replaceAll: replaceAll,
                          repository: repository,
                          saver: ({
                            required id,
                            required childId,
                            required assessmentRunId,
                            required questionnaireType,
                            required responses,
                          }) async {
                            saved.add((
                              run: assessmentRunId,
                              type: questionnaireType,
                            ));
                          },
                          onDone:
                              (questionnaire) =>
                                  replaceAll
                                      ? Navigator.of(
                                        questionnaire,
                                      ).pushAndRemoveUntil(
                                        MaterialPageRoute(
                                          builder:
                                              (_) => const Scaffold(
                                                body: Text('Dashboard'),
                                              ),
                                        ),
                                        (_) => false,
                                      )
                                      : Navigator.of(questionnaire).pop(),
                        ),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Save Child Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(ParentQuestionnaireScreen), findsOneWidget);
      return saved;
    }

    testWidgets('first setup: answers are the "before", then the dashboard', (
      tester,
    ) async {
      final saved = await open(tester, replaceAll: true);
      // Asked only once, so the skip button is not "for now".
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Skip for now'), findsNothing);

      for (final item in kParentQuestionnaireDraft.items) {
        final chip = find.byKey(
          Key('questionnaire.answer.${item.id}.${Frequency.often.name}'),
        );
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('questionnaire.save')));
      await tester.pumpAndSettle();

      expect(saved, [(run: null, type: 'pre')]);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Save Child Profile'), findsNothing);
      expect(
        await SetupHomeQuestionnaire.shouldOffer('child-1', loader: none),
        isFalse,
      );
    });

    testWidgets('adding a child: skipping counts as asked and returns', (
      tester,
    ) async {
      final saved = await open(tester, replaceAll: false);
      await tester.tap(find.byKey(const Key('questionnaire.skip')));
      await tester.pumpAndSettle();

      expect(saved, isEmpty);
      expect(find.byType(ParentQuestionnaireScreen), findsNothing);
      expect(find.text('Save Child Profile'), findsOneWidget);
      expect(
        await SetupHomeQuestionnaire.shouldOffer('child-1', loader: none),
        isFalse,
      );
    });
  });

  group('the dashboard card', () {
    Future<void> pumpDashboard(
      WidgetTester tester, {
      QuestionnaireLoader? loader,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider<ChildProvider>(
          create: (_) => _ActiveChild('child-1'),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: HomeQuestionnaireOffer(
                loader: loader ?? none,
                repository: repository,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const card = Key('home-questionnaire-offer');

    testWidgets('No thanks dismisses it for good', (tester) async {
      await pumpDashboard(tester);
      expect(find.byKey(card), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('home-questionnaire-offer.dismiss')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(card), findsNothing);

      // Opening the dashboard again does not bring it back.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpDashboard(tester);
      expect(find.byKey(card), findsNothing);
    });

    testWidgets('Answer now opens the questionnaire, then it is gone', (
      tester,
    ) async {
      await pumpDashboard(tester);
      await tester.tap(
        find.byKey(const Key('home-questionnaire-offer.answer')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ParentQuestionnaireScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('questionnaire.skip')));
      await tester.pumpAndSettle();
      expect(find.byType(ParentQuestionnaireScreen), findsNothing);
      expect(find.byType(HomeQuestionnaireOffer), findsOneWidget);
      expect(find.byKey(card), findsNothing);
    });

    testWidgets('a child who already has a home report is not offered it', (
      tester,
    ) async {
      await pumpDashboard(tester, loader: (_) async => [homeReport('pre-run')]);
      expect(find.byKey(card), findsNothing);
    });
  });
}

class _ActiveChild extends ChildProvider {
  _ActiveChild(this._id)
    : super(authService: AuthService(supabaseAuth: _NoAuth()));

  final String _id;

  @override
  String? get activeChildId => _id;
}

class _NoAuth implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
