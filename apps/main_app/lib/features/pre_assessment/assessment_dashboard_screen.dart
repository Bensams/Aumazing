import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/assessment_progress_service.dart';
import '../../services/assessment_summary_service.dart';
import '../../services/scoring_service.dart';
import '../child_mode/open_my_path.dart';
import 'assessment_result_view.dart';
import 'pre_assessment_intro_screen.dart';

/// Assessment Summary — shown when the parent taps "Assessment" on the home
/// screen after the child has completed the pre-assessment.
///
/// When a post-assessment has been completed, shows the post snapshot as the
/// primary view so the parent sees their child's latest results, recommended
/// settings, and recommended activities. The pre-assessment baseline remains
/// viewable through the pre→post comparison card (AUM-161).
///
/// When only the pre-assessment exists, shows the pre snapshot as before.
///
/// The profile and recommendations come from the run as it was finalized —
/// reopening this screen after changing the child's sensory settings must not
/// rewrite a past result.
class AssessmentDashboardScreen extends StatelessWidget {
  const AssessmentDashboardScreen({super.key, this.summaryService});

  /// Test seam for keeping dashboard widget tests off the network.
  @visibleForTesting
  final AssessmentSummaryService? summaryService;

  @override
  Widget build(BuildContext context) {
    return Consumer2<AssessmentProvider, ChildProvider>(
      builder: (context, assessProv, childProv, _) {
        // Select the most recent completed run as the primary display.
        // When a post-assessment exists and has a coherent snapshot, show
        // that; otherwise show the pre-assessment snapshot.
        final hasPost =
            assessProv.hasPostAssessment && assessProv.postSnapshot != null;
        final snapshot =
            hasPost ? assessProv.postSnapshot : assessProv.preSnapshot;
        final results =
            snapshot?.results ??
            (hasPost ? assessProv.postResults : assessProv.preResults);

        if (results.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('No assessment data found.')),
          );
        }

        // Historical snapshots own their nullable profile and prediction.
        // Never fill a missing frozen value from mutable provider state,
        // which may already describe a different run. Legacy post snapshots
        // did not finalize their own profile, so rebuild those from post data.
        final snapshotProfile =
            snapshot?.profileIsRunSpecific == true ? snapshot?.profile : null;
        final profile =
            snapshotProfile ??
            (snapshot == null ? assessProv.supportProfile : null) ??
            const ScoringService().generateProfile(
              results: results,
              sensorySettings: childProv.sensorySettingsMap,
            );
        final prediction =
            snapshot == null ? assessProv.aiPrediction : snapshot.prediction;

        // Once a post-assessment exists, the parent's first question is
        // whether anything moved — so the primary summary carries a
        // before/after card alongside it (AUM-161). Null whenever the two
        // runs are not comparable, which shows the primary on its own.
        final progress = AssessmentProgressService.compare(
          before: assessProv.preSnapshot,
          after: assessProv.postSnapshot,
        );

        return ParentAdaptiveOrientation(
          child: AssessmentResultView(
            results: results,
            profile: profile,
            aiResponse: prediction,
            assessmentType: snapshot?.assessmentType ?? 'pre',
            progress: progress,
            presentation: AssessmentResultPresentation.review,
            childDisplayName: childProv.profile?.displayName ?? 'Your child',
            showTherapyRecommendation: true,
            nextModulePremiumRequired: hasPost && assessProv.nextCycleLocked,
            summaryService: summaryService,
            backLabel: AssessmentLabels.home,
            onBack: () => Navigator.of(context).pop(),
            onOpenLearningPath: () => openMyPath(context),
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
