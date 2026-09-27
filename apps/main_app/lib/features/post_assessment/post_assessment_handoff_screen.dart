import 'package:flutter/material.dart';

import '../../widgets/assessment_handoff.dart';
import '../../widgets/milestone_victory_scene.dart';
import '../questionnaire/parent_questionnaire_screen.dart';
import 'post_assessment_result_screen.dart';

/// Screen shown to the child after all post-assessment games are complete.
///
/// The post-assessment used to drop straight from the last game into
/// [PostAssessmentResultScreen], which is parent-facing — so the child was
/// handed the comparison of their own before/after levels, and no verification
/// stood between them and it. This puts the same child hand-off the
/// pre-assessment has in front of it.
///
/// The finished run's numbers are carried through verbatim rather than
/// recomputed: they were produced by the run that just ended, and re-deriving
/// them here could only disagree with it.
class PostAssessmentHandoffScreen extends StatelessWidget {
  const PostAssessmentHandoffScreen({
    super.key,
    required this.improvement,
    this.nextModulePremiumRequired = false,
    this.voiceOverFactory,
    this.childId,
    this.assessmentRunId,
    this.showQuestionnaire = true,
  });

  /// The child and the finished run, so the parent questionnaire is stored
  /// against them. The run id is captured before the run is closed.
  final String? childId;
  final String? assessmentRunId;

  /// Whether the parent questionnaire comes between verification and the
  /// results. On in the app; tests about the hand-off itself turn it off.
  final bool showQuestionnaire;

  /// Output of AssessmentService.compareAssessments for the completed run.
  final Map<String, dynamic> improvement;

  /// Whether generating the next personalized module requires Premium.
  final bool nextModulePremiumRequired;

  /// Test seam, forwarded to [AssessmentHandoffScreen].
  final HandoffVoiceOverFactory? voiceOverFactory;

  @override
  Widget build(BuildContext context) {
    return AssessmentHandoffScreen(
      title: MilestoneKind.postAssessment.title,
      subtitle: MilestoneKind.postAssessment.subtitle,
      milestoneVoiceCue: MilestoneKind.postAssessment.voiceCue,
      voiceOverFactory: voiceOverFactory,
      onParentVerified: _afterVerification,
    );
  }

  /// The same questionnaire as after the pre-assessment, answered before the
  /// comparison is shown, so the parent's view of change is their own.
  void _afterVerification(BuildContext context) {
    final childId = this.childId;
    if (!showQuestionnaire || childId == null) {
      _showResults(context);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => ParentQuestionnaireScreen(
              assessmentType: 'post',
              childId: childId,
              assessmentRunId: assessmentRunId,
              onDone: _showResults,
            ),
      ),
    );
  }

  void _showResults(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PostAssessmentResultScreen(
          improvement: improvement,
          nextModulePremiumRequired: nextModulePremiumRequired,
        ),
      ),
    );
  }
}
