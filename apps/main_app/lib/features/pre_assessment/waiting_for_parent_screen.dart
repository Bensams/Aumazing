import 'package:flutter/material.dart';

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import '../../widgets/assessment_handoff.dart';
import '../../widgets/milestone_victory_scene.dart';
import '../questionnaire/parent_questionnaire_screen.dart';
import 'game_summary_dialog.dart';
import 'pre_assessment_result_screen.dart';

/// Screen shown to the child after all pre-assessment games are complete.
///
/// The celebration, the "give the device to your parent" hand-off and the
/// verification gate all live in [AssessmentHandoffScreen], which the
/// post-assessment shares. This screen supplies only what is specific to the
/// pre-assessment: the summary dialog and the result screen behind it.
class WaitingForParentScreen extends StatelessWidget {
  const WaitingForParentScreen({
    super.key,
    required this.results,
    required this.profile,
    this.aiResponse,
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

  final List<AssessmentResult> results;
  final SupportProfile profile;

  /// AI prediction data, or null if AI was unavailable (rule-based fallback).
  final AiAssessmentResponse? aiResponse;

  /// Test seam, forwarded to [AssessmentHandoffScreen].
  final HandoffVoiceOverFactory? voiceOverFactory;

  @override
  Widget build(BuildContext context) {
    return AssessmentHandoffScreen(
      title: MilestoneKind.preAssessment.title,
      subtitle: MilestoneKind.preAssessment.subtitle,
      milestoneVoiceCue: MilestoneKind.preAssessment.voiceCue,
      voiceOverFactory: voiceOverFactory,
      onParentVerified: _afterVerification,
    );
  }

  /// The parent has the device: their questionnaire first, before any result
  /// is on screen, then the summary.
  void _afterVerification(BuildContext context) {
    final childId = this.childId;
    if (!showQuestionnaire || childId == null) {
      _showSummary(context);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => ParentQuestionnaireScreen(
              assessmentType: 'pre',
              childId: childId,
              assessmentRunId: assessmentRunId,
              onDone: _showSummary,
            ),
      ),
    );
  }

  void _showSummary(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (summaryContext) => GameSummaryDialog(
          results: results,
          aiResponse: aiResponse,
          onContinue: () {
            Navigator.of(summaryContext).pushReplacement(
              MaterialPageRoute(
                builder: (_) => PreAssessmentResultScreen(
                  profile: profile,
                  results: results,
                  aiResponse: aiResponse,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
