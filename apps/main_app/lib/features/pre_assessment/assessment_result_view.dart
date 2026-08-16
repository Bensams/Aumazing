import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import '../../services/active_games_service.dart';
import '../../services/assessment_result_mapper.dart';

/// Renders a finalized assessment run with the shared result layout.
///
/// Both the immediate completion screen and the parent's later Assessment
/// Summary go through here, so they build the *same* canonical view model
/// from the *same* inputs and differ only in [presentation] and actions.
///
/// The active-game set only filters the recommended activities. It is read
/// from the in-memory cache first and refreshed in the background, so an
/// offline parent still sees the whole result immediately.
class AssessmentResultView extends StatefulWidget {
  const AssessmentResultView({
    super.key,
    required this.results,
    required this.profile,
    required this.presentation,
    this.aiResponse,
    this.assessmentType = 'pre',
    this.progress,
    this.onContinue,
    this.onRetake,
    this.onBack,
    this.backLabel = AssessmentLabels.home,
    this.showCelebration = true,
  });

  final List<AssessmentResult> results;

  /// The support profile finalized with this run — never recomputed from
  /// the child's current settings.
  final SupportProfile profile;

  final AssessmentResultPresentation presentation;
  final AiAssessmentResponse? aiResponse;
  final String assessmentType;

  /// Before-and-after comparison against an earlier comparable run, when the
  /// caller has one (AUM-161). Null shows the run on its own, unchanged.
  final ResultProgress? progress;

  final VoidCallback? onContinue;
  final VoidCallback? onRetake;
  final VoidCallback? onBack;
  final String backLabel;
  final bool showCelebration;

  @override
  State<AssessmentResultView> createState() => _AssessmentResultViewState();
}

class _AssessmentResultViewState extends State<AssessmentResultView> {
  Set<String>? _activeGameIds = ActiveGamesService.instance.cachedActiveGameIds;

  @override
  void initState() {
    super.initState();
    if (_activeGameIds == null) _loadActiveGameIds();
  }

  Future<void> _loadActiveGameIds() async {
    final ids = await ActiveGamesService.instance.activeGameIds;
    if (mounted) setState(() => _activeGameIds = ids);
  }

  @override
  Widget build(BuildContext context) {
    final model = AssessmentResultMapper.build(
      results: widget.results,
      profile: widget.profile,
      aiResponse: widget.aiResponse,
      activeGameIds: _activeGameIds,
      assessmentType: widget.assessmentType,
      progress: widget.progress,
    );

    return AssessmentResultLayout(
      model: model,
      presentation: widget.presentation,
      onContinue: widget.onContinue,
      onRetake: widget.onRetake,
      onBack: widget.onBack,
      backLabel: widget.backLabel,
      showCelebration: widget.showCelebration,
    );
  }
}
