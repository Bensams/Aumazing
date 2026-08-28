import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/assessment_progress_service.dart';
import '../../services/scoring_service.dart' as local_scoring;
import '../pre_assessment/assessment_result_view.dart';

/// Parent-facing post-assessment results.
///
/// Shows the full canonical assessment result (game scores, developmental
/// profile, recommended settings, recommended activities) from the frozen
/// post snapshot, alongside a pre→post comparison card. When Premium is
/// required for the next learning module, the activities section shows a
/// premium-required message instead of stale pre-assessment recommendations.
class PostAssessmentResultScreen extends StatelessWidget {
  const PostAssessmentResultScreen({
    super.key,
    required this.improvement,
    this.nextModulePremiumRequired = false,
  });

  /// Output of AssessmentService.compareAssessments.
  final Map<String, dynamic> improvement;

  /// Whether generating the next personalized module requires Premium.
  final bool nextModulePremiumRequired;

  @override
  Widget build(BuildContext context) {
    return Consumer2<AssessmentProvider, ChildProvider>(
      builder: (context, assessProv, childProv, _) {
        final postSnapshot = assessProv.postSnapshot;
        final preSnapshot = assessProv.preSnapshot;

        // The post snapshot was captured before navigating here and contains
        // the post run's own results, profile, and prediction. Never mix the
        // mutable provider fields into this historical run.
        final results = postSnapshot?.results ?? const [];

        if (results.isEmpty) {
          // Defensive: should not happen in the normal flow.
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: AppGradients.parentLavenderMint,
              ),
              child: const SafeArea(
                child: Center(child: Text('No post-assessment data found.')),
              ),
            ),
          );
        }

        // New snapshots carry the freshly finalized post profile. Legacy post
        // snapshots may contain the pre profile, so rebuild those from the
        // frozen post results instead of showing stale settings.
        final profile =
            (postSnapshot?.profileIsRunSpecific == true
                ? postSnapshot?.profile
                : null) ??
            const local_scoring.ScoringService().generateProfile(
              results: results,
              sensorySettings: childProv.sensorySettingsMap,
            );

        // The prediction frozen in the post snapshot — never the mutable
        // provider.aiPrediction, which could have been overwritten.
        final aiResponse = postSnapshot?.prediction;

        // Pre→post comparison using the frozen snapshots.
        final progress = AssessmentProgressService.compare(
          before: preSnapshot,
          after: postSnapshot,
        );
        final overallProgress =
            improvement['has_data'] == true
                ? ResultOverallProgress(
                  accuracyDelta:
                      (improvement['accuracy_improvement'] as num?)
                          ?.toDouble() ??
                      0,
                  responseTimeDeltaMs:
                      (improvement['response_time_improvement'] as num?)
                          ?.toDouble() ??
                      0,
                )
                : null;

        return ParentAdaptiveOrientation(
          child: AssessmentResultView(
            results: results,
            profile: profile,
            aiResponse: aiResponse,
            assessmentType: 'post',
            progress: progress,
            overallProgress: overallProgress,
            presentation: AssessmentResultPresentation.completion,
            childDisplayName: childProv.profile?.displayName ?? 'Your child',
            showTherapyRecommendation: true,
            nextModulePremiumRequired: nextModulePremiumRequired,
            onContinue:
                () => Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        );
      },
    );
  }
}
