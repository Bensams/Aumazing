import 'package:provider/provider.dart';

import '../../model/star_ledger_entry.dart';
import '../../providers/child_provider.dart';
import '../../providers/stars_provider.dart';
import '../stars/widgets/star_earned_overlay.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import '../../services/active_games_service.dart';
import '../../services/assessment_result_mapper.dart';
import '../../services/assessment_summary_service.dart';
import '../../services/recommended_settings_applier.dart';
import '../../services/report_pdf_service.dart';
import '../../services/scoring_service.dart' as local_scoring;
import '../therapy/therapy_center_recommendation_dialog.dart';

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
    this.overallProgress,
    this.onContinue,
    this.onRetake,
    this.onBack,
    this.onOpenLearningPath,
    this.backLabel = AssessmentLabels.home,
    this.showCelebration = true,
    this.showTherapyRecommendation = false,
    this.nextModulePremiumRequired = false,
    required this.childDisplayName,
    this.reportPdfSharer,
    this.summaryService,
  });

  final List<AssessmentResult> results;
  final SupportProfile profile;
  final AssessmentResultPresentation presentation;
  final AiAssessmentResponse? aiResponse;
  final String assessmentType;
  final ResultProgress? progress;
  final ResultOverallProgress? overallProgress;
  final VoidCallback? onContinue;
  final VoidCallback? onRetake;
  final VoidCallback? onBack;

  /// Opens the child's My Path view from the Recommended Activities card.
  /// Null hides that action — a host that cannot send the child anywhere.
  final VoidCallback? onOpenLearningPath;
  final String backLabel;
  final bool showCelebration;
  final bool showTherapyRecommendation;
  final bool nextModulePremiumRequired;
  final String childDisplayName;
  final ReportPdfSharer? reportPdfSharer;

  /// Injectable for tests; defaults to the shared singleton.
  final AssessmentSummaryService? summaryService;

  @override
  State<AssessmentResultView> createState() => _AssessmentResultViewState();
}

class _AssessmentResultViewState extends State<AssessmentResultView> {
  Set<String>? _activeGameIds = ActiveGamesService.instance.cachedActiveGameIds;
  bool _sharingReport = false;

  /// The summarizer's narrative, once it has arrived. Null until then — and
  /// forever, when the summarizer is unreachable — in which case the rubric
  /// summary the mapper builds is what stays on screen.
  String? _aiSummary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _awardStars();
      _loadAiSummary();
      if (widget.showTherapyRecommendation &&
          local_scoring.AssessmentScoring.isCriticallyPoor(widget.results) &&
          mounted) {
        showTherapyCenterRecommendation(context);
      }
    });
    if (_activeGameIds == null) _loadActiveGameIds();
  }

  /// Stars for finishing an assessment (STAR-B6).
  ///
  /// Awarded here, on the results screen, rather than as the last question is
  /// answered: by this point the run is scored and stored, so nothing about
  /// the payout can reach back and influence how the child responded. The
  /// amount is the same fixed one every game pays — the assessment is not
  /// worth more for being harder, and an abandoned run that never reaches
  /// this screen simply earns nothing rather than being penalised.
  ///
  /// Keyed on the run id, so re-opening the results screen — which a parent
  /// does — cannot pay again.
  Future<void> _awardStars() async {
    if (!mounted) return;
    final runId = widget.results
        .map((r) => r.assessmentRunId)
        .firstWhere((id) => id != null, orElse: () => null);
    if (runId == null) return;

    // This view is embedded in several places, including the parent
    // dashboard, and awarding stars is a side-benefit of showing results —
    // never the reason. A host that has not provided StarsProvider must still
    // render the results rather than throw, so the lookup is guarded.
    final StarsProvider stars;
    try {
      stars = context.read<StarsProvider>();
    } on ProviderNotFoundException {
      debugPrint('[AssessmentResultView] no StarsProvider; skipping award');
      return;
    }

    await stars.bind(widget.results.first.childId);
    final award = await stars.awardForPlay(
      playKey: 'assessment:$runId',
      reason: StarReason.assessmentCompleted,
    );
    // Deliberately still silent when an assessment does not pay. An
    // assessment run is keyed on its own id and happens once, so the only way
    // here is a re-shown results screen or the daily cap — neither is a moment
    // to interrupt with a message about stars. The game-end flow, where a
    // child is choosing what to play next, is where that belongs (AUM-286).
    if (!award.didEarn || !mounted) return;
    await StarEarnedOverlay.show(context, granted: award.granted);
  }

  /// Writes this run's Recommended Settings to the child's settings.
  ///
  /// The profile handed to this view is the one finalized with the run being
  /// shown, so applying an older summary applies what that run recommended —
  /// never a freshly recomputed set the parent has not read.
  Future<bool> _applyRecommendations() async {
    final childId =
        widget.results.isEmpty ? null : widget.results.first.childId;
    if (childId == null) return false;
    final ChildProvider childProv;
    try {
      childProv = context.read<ChildProvider>();
    } on ProviderNotFoundException {
      debugPrint('[AssessmentResultView] no ChildProvider; cannot apply');
      return false;
    }
    return RecommendedSettingsApplier.apply(
      profile: widget.profile,
      childProv: childProv,
      childId: childId,
    );
  }

  /// Asks the summarizer to rewrite this result's summary in warm, plain
  /// language, then swaps it in.
  ///
  /// Best-effort by construction: the screen has already rendered the rubric
  /// summary by the time this runs, and [AssessmentSummaryService] answers
  /// with that same fallback on no internet, timeout, quota, or a missing
  /// key — so nothing here can delay, blank, or break the result. When a
  /// comparable earlier run exists the request is a progress narrative
  /// (before -> after) instead of a snapshot.
  Future<void> _loadAiSummary() async {
    if (!mounted) return;
    final model = _buildModel();
    if (!model.hasAreas) return;

    // Same preference that drives the localized voice-overs. A host without
    // ChildProvider still gets a summary, in English.
    var languageCode = 'en';
    try {
      languageCode = context.read<ChildProvider>().language.slug;
    } on ProviderNotFoundException {
      debugPrint('[AssessmentResultView] no ChildProvider; summarizing in en');
    }

    final progressAreas = model.progress?.areas ?? const [];
    final summary = await (widget.summaryService ??
            AssessmentSummaryService.instance)
        .summarize(
          areas: [
            for (final area in model.areas)
              {'name': area.label, 'level': area.levelName},
          ],
          previousAreas: [
            for (final area in progressAreas)
              {'name': area.label, 'level': area.beforeLevelName},
          ],
          overallPct: model.overallPercent,
          supportLevel: model.supportLevel ?? 'moderate',
          recommendations: [
            for (final step in model.learningPath) step.name,
          ],
          fallback: model.summary,
          languageCode: languageCode,
        );

    if (!mounted || !summary.isAi) return;
    setState(() => _aiSummary = summary.text);
  }

  Future<void> _loadActiveGameIds() async {
    final ids = await ActiveGamesService.instance.activeGameIds;
    if (mounted) setState(() => _activeGameIds = ids);
  }

  Future<void> _shareReport(AssessmentResultViewModel model) async {
    if (_sharingReport) return;
    setState(() => _sharingReport = true);
    try {
      await (widget.reportPdfSharer ?? ReportPdfService())
          .shareAssessmentReport(
            model: model,
            childDisplayName: widget.childDisplayName,
          );
    } catch (error) {
      debugPrint('[AssessmentResultView] report share failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We couldn\u2019t create or share the PDF. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingReport = false);
    }
  }

  AssessmentResultViewModel _buildModel() => AssessmentResultMapper.build(
    results: widget.results,
    profile: widget.profile,
    aiResponse: widget.aiResponse,
    activeGameIds: _activeGameIds,
    assessmentType: widget.assessmentType,
    progress: widget.progress,
    overallProgress: widget.overallProgress,
    premiumRequired: widget.nextModulePremiumRequired,
    aiSummary: _aiSummary,
  );

  @override
  Widget build(BuildContext context) {
    final model = _buildModel();

    return AssessmentResultLayout(
      model: model,
      presentation: widget.presentation,
      onContinue: widget.onContinue,
      onRetake: widget.onRetake,
      onBack: widget.onBack,
      backLabel: widget.backLabel,
      showCelebration: widget.showCelebration,
      onApplyRecommendations: _applyRecommendations,
      onOpenLearningPath: widget.onOpenLearningPath,
      headerAction: SizedBox(
        width: 44,
        height: 44,
        child:
            _sharingReport
                ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : IconButton(
                  key: const ValueKey('share-assessment-pdf'),
                  tooltip: 'Share as PDF',
                  onPressed: () => _shareReport(model),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                ),
      ),
    );
  }
}
