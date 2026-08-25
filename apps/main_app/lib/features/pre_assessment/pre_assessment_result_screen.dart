import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import '../../services/assessment_result_mapper.dart';
import 'assessment_result_view.dart';
import '../therapy/therapy_directory_screen.dart';

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

    final areas = AssessmentResultMapper.buildAreas(
      profile: widget.profile,
      aiResponse: widget.aiResponse,
    );
    final needsSupportCount =
        areas.where((area) => area.levelInt == 0).length;
    if (needsSupportCount >= 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _therapyCenterPromptShown) return;
        _therapyCenterPromptShown = true;
        await _showTherapyCenterPrompt();
      });
    }
  }

  Future<void> _showTherapyCenterPrompt() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Explore Therapy Center support',
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              content: Text(
                'These results suggest that extra support may be helpful '
                'across several skill areas. This assessment is based on game '
                'performance only and is not a medical diagnosis. You can '
                'browse Therapy Centers for consultation and support options.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.mutedForeground,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Maybe Later'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    if (!mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TherapyDirectoryScreen(),
                      ),
                    );
                  },
                  child: const Text('Browse Therapy Centers'),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AssessmentResultView(
      results: widget.results,
      profile: widget.profile,
      aiResponse: widget.aiResponse,
      presentation: AssessmentResultPresentation.completion,
      onContinue: () {
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }
}
