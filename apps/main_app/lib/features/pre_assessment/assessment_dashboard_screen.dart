import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
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
        final results = assessProv.preResults;

        if (results.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('No assessment data found.')),
          );
        }

        // Assessments finalized before profiles were persisted have nothing
        // stored; those fall back to the rubric scorer so an existing child
        // still sees a complete summary.
        final profile =
            assessProv.supportProfile ??
            const ScoringService().generateProfile(
              results: results,
              sensorySettings: childProv.sensorySettingsMap,
            );

        return ParentAdaptiveOrientation(
          child: AssessmentResultView(
            results: results,
            profile: profile,
            aiResponse: assessProv.aiPrediction,
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
