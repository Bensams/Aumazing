import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import '../../providers/child_provider.dart';
import '../../services/scoring_service.dart' as local_scoring;
import '../child_mode/open_my_path.dart';
import '../therapy/therapy_center_recommendation_dialog.dart';
import 'assessment_result_view.dart';

/// The result shown immediately after the child finishes the pre-assessment
/// (once the parent has verified themselves).
///
/// Completion mode of the shared result presentation: a short celebration,
/// warm explanatory copy, and a single "Continue to Home" action — retaking
/// belongs in the parent's later review, not here.
class PreAssessmentResultScreen extends StatefulWidget {
  const PreAssessmentResultScreen({
    super.key,
    required this.profile,
    required this.results,
    this.aiResponse,
  });

  /// The support profile finalized with this run.
  final SupportProfile profile;
  final List<AssessmentResult> results;

  /// AI prediction data, or null if AI was unavailable (rule-based fallback).
  final AiAssessmentResponse? aiResponse;

  @override
  State<PreAssessmentResultScreen> createState() =>
      _PreAssessmentResultScreenState();
}

class _PreAssessmentResultScreenState extends State<PreAssessmentResultScreen> {
  bool _therapyCenterPromptShown = false;

  @override
  void initState() {
    super.initState();
    // Back to the parent: the child just finished the landscape activities.
    lockParentAdaptive();

    if (local_scoring.AssessmentScoring.isCriticallyPoor(widget.results)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _therapyCenterPromptShown) return;
        _therapyCenterPromptShown = true;
        await showTherapyCenterRecommendation(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final childId =
        widget.results.isEmpty ? null : widget.results.first.childId;
    final children = context.watch<ChildProvider>().children;
    final childName =
        children
            .where((child) => child.id == childId)
            .map((child) => child.displayName)
            .firstOrNull;
    return AssessmentResultView(
      results: widget.results,
      profile: widget.profile,
      aiResponse: widget.aiResponse,
      presentation: AssessmentResultPresentation.completion,
      childDisplayName: childName ?? 'Your child',
      onContinue: () {
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
      onOpenLearningPath: () => openMyPath(context),
    );
  }
}
