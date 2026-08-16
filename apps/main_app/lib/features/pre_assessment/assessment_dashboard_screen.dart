import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/assessment_progress_service.dart';
import '../../services/scoring_service.dart';
import 'assessment_result_view.dart';
import 'pre_assessment_intro_screen.dart';

/// Assessment Summary — shown when the parent taps "Assessment" on the home
/// screen after the child has completed the pre-assessment.
///
/// Review mode of the shared result presentation: the same sections and the
/// same values as the completion screen, laid out more densely, with the
/// completion date and the "Retake Assessment" action.
///
/// The profile and recommendations come from the run as it was finalized
/// (see [AssessmentProvider.supportProfile]) — reopening this screen after
/// changing the child's sensory settings must not rewrite a past result.
class AssessmentDashboardScreen extends StatelessWidget {
  const AssessmentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AssessmentProvider, ChildProvider>(
      builder: (context, assessProv, childProv, _) {
        // Always the finalized PRE-assessment: its own results, its own
        // profile and the prediction made from its own sessions. Reading
        // `aiPrediction` here would show the post-assessment's levels under
        // the pre-assessment's scores once a post-assessment has been run.
        final snapshot = assessProv.preSnapshot;
        final results = snapshot?.results ?? assessProv.preResults;

        if (results.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('No assessment data found.')),
          );
        }

        // Assessments finalized before profiles were persisted have nothing
        // stored; those fall back to the rubric scorer so an existing child
        // still sees a complete summary.
        final profile =
            snapshot?.profile ??
            assessProv.supportProfile ??
            const ScoringService().generateProfile(
              results: results,
              sensorySettings: childProv.sensorySettingsMap,
            );

        // Once a post-assessment exists, the parent's first question is
        // whether anything moved — so the baseline summary carries a
        // before/after card alongside it (AUM-161). Null whenever the two
        // runs are not comparable, which shows the baseline on its own.
        final progress = AssessmentProgressService.compare(
          before: assessProv.preSnapshot,
          after: assessProv.postSnapshot,
        );

        return ParentAdaptiveOrientation(
          child: AssessmentResultView(
            results: results,
            profile: profile,
            aiResponse:
                snapshot?.prediction ??
                (assessProv.hasPostAssessment ? null : assessProv.aiPrediction),
            progress: progress,
            presentation: AssessmentResultPresentation.review,
            backLabel: AssessmentLabels.home,
            onBack: () => Navigator.of(context).pop(),
            onRetake: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const PreAssessmentIntroScreen(),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
