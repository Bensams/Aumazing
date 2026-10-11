import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/services/local_db_service.dart';
import '../../providers/child_provider.dart';
import 'home_observation_context.dart';
import 'parent_questionnaire_comparison_card.dart' show QuestionnaireLoader;
import 'parent_questionnaire_screen.dart';
import 'questionnaire_template_repository.dart';

/// The home questionnaire's "before" (AUM-364): asked once per child, right
/// after the profile is set up — first registration or adding a child — and
/// before the dashboard. A child set up before this existed, with no home
/// report yet, is offered it once on the dashboard ([HomeQuestionnaireOffer]).
///
/// The report is stored as a `pre` questionnaire with no assessment run; the
/// summaries read it as the pre-assessment's home context and compare the
/// post-assessment report ([HomeQuestionnaireFlow]) with it.
///
/// Answering or skipping both count as asked, so it never comes back.
class SetupHomeQuestionnaire {
  static String _offeredKey(String childId) =>
      'home_questionnaire_offered_$childId';

  /// Records that this child has been asked. Best effort: a storage failure
  /// only means the dashboard may offer it once more.
  static Future<void> markOffered(String childId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_offeredKey(childId), true);
    } catch (e) {
      debugPrint('[SetupHomeQuestionnaire] could not record offer: $e');
    }
  }

  /// Whether the dashboard should still offer it: never asked on this device
  /// and no home report saved for the child.
  static Future<bool> shouldOffer(
    String childId, {
    QuestionnaireLoader? loader,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_offeredKey(childId)) ?? false) return false;
      final rows = await (loader ?? localDbService.getCaregiverQuestionnaires)(
        childId,
      );
      return !rows.any((row) => HomeObservation.fromRow(row) != null);
    } catch (_) {
      // Unknown state: stay quiet rather than nag.
      return false;
    }
  }

  /// Opens the questionnaire for [childId]. [onDone] runs once, after saving
  /// or skipping, with the questionnaire's context so it can move on.
  static Future<void> show(
    BuildContext context, {
    required String childId,
    required void Function(BuildContext) onDone,
    bool replaceAll = false,
    QuestionnaireTemplateRepository? repository,
    QuestionnaireSaver? saver,
  }) async {
    await markOffered(childId);
    final template = await (repository ??
            QuestionnaireTemplateRepository.instance)
        .templateFor('pre');
    if (!context.mounted) return;
    final route = PageRouteBuilder<void>(
      pageBuilder:
          (_, __, ___) => ParentQuestionnaireScreen(
            template: template,
            assessmentType: 'pre',
            childId: childId,
            assessmentRunId: null,
            atSetup: true,
            onDone: onDone,
            saver: saver,
          ),
      // A fade, like the setup screen's own hand-off, so music keeps going.
      transitionsBuilder:
          (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 400),
    );
    final navigator = Navigator.of(context);
    if (replaceAll) {
      navigator.pushAndRemoveUntil(route, (_) => false);
    } else {
      await navigator.push(route);
    }
  }
}

/// Dashboard card offering the home questionnaire once to a child who has
/// none yet. **No thanks** dismisses it for good.
class HomeQuestionnaireOffer extends StatefulWidget {
  const HomeQuestionnaireOffer({super.key, this.loader, this.repository});

  final QuestionnaireLoader? loader;
  final QuestionnaireTemplateRepository? repository;

  @override
  State<HomeQuestionnaireOffer> createState() => _HomeQuestionnaireOfferState();
}

class _HomeQuestionnaireOfferState extends State<HomeQuestionnaireOffer> {
  String? _checkedFor;
  bool _show = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final childId = context.watch<ChildProvider>().activeChildId;
    if (childId == _checkedFor) return;
    _checkedFor = childId;
    _show = false;
    if (childId != null) _check(childId);
  }

  Future<void> _check(String childId) async {
    final offer = await SetupHomeQuestionnaire.shouldOffer(
      childId,
      loader: widget.loader,
    );
    if (mounted && _checkedFor == childId) setState(() => _show = offer);
  }

  Future<void> _dismiss(String childId) async {
    setState(() => _show = false);
    await SetupHomeQuestionnaire.markOffered(childId);
  }

  Future<void> _answer(String childId) async {
    setState(() => _show = false);
    await SetupHomeQuestionnaire.show(
      context,
      childId: childId,
      repository: widget.repository,
      onDone: (questionnaire) => Navigator.of(questionnaire).pop(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final childId = _checkedFor;
    if (!_show || childId == null) return const SizedBox.shrink();
    return Padding(
      key: const Key('home-questionnaire-offer'),
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A few questions about your child',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Optional, about 2 minutes. How your child does at home sits '
              'beside the game results, and a later follow-up asks again so '
              'you can compare. We only ask once.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                FilledButton(
                  key: const Key('home-questionnaire-offer.answer'),
                  onPressed: () => _answer(childId),
                  child: const Text('Answer now'),
                ),
                TextButton(
                  key: const Key('home-questionnaire-offer.dismiss'),
                  onPressed: () => _dismiss(childId),
                  child: const Text('No thanks'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
