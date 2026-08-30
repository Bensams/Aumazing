import 'package:flutter/material.dart';

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import '../../widgets/assessment_handoff.dart';
import '../../widgets/milestone_victory_scene.dart';
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
  });

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
      onParentVerified: _showSummary,
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
