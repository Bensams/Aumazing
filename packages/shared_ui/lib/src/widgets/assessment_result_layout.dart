import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'assessment/assessment_disclaimer.dart';
import 'assessment/assessment_game_results_card.dart';
import 'assessment/assessment_learning_path_card.dart';
import 'assessment/assessment_overview_card.dart';
import 'assessment/assessment_profile_card.dart';
import 'assessment/assessment_progress_card.dart';
import 'assessment/assessment_recommendations_card.dart';
import 'assessment/assessment_result_actions.dart';
import 'assessment/assessment_result_header.dart';
import 'assessment_result_data.dart';
import 'game_celebration_overlay.dart';

/// The canonical presentation of a finalized assessment run.
///
/// One [AssessmentResultViewModel] renders in two modes:
///
/// * [AssessmentResultPresentation.completion] — shown to the parent right
///   after the child finishes. Adds a short celebration and warm copy, and
///   offers only "Continue to Home".
/// * [AssessmentResultPresentation.review] — opened later from the parent
///   dashboard. No celebration, denser spacing, shows the completion date,
///   and offers "Retake Assessment" alongside the way back.
///
/// The sections, values, terminology and disclaimer are identical in both;
/// only the framing and actions differ.
///
/// Responsive: one page scroll at every size. Single column on a narrow
/// portrait phone, two columns from 720 logical pixels, three from 1080 —
/// with the section order preserved down the columns.
class AssessmentResultLayout extends StatefulWidget {
  const AssessmentResultLayout({
    super.key,
    required this.model,
    this.presentation = AssessmentResultPresentation.completion,
    this.onContinue,
    this.onRetake,
    this.onBack,
    this.backLabel = AssessmentLabels.backToDashboard,
    this.showCelebration = true,
    this.onApplyRecommendations,
    this.celebrationDuration = const Duration(milliseconds: 3000),
    this.background,
  });

  /// The canonical result data. The same instance drives both modes.
  final AssessmentResultViewModel model;

  final AssessmentResultPresentation presentation;

  /// Completion mode: "Continue to Home".
  final VoidCallback? onContinue;

  /// Review mode: "Retake Assessment".
  final VoidCallback? onRetake;

  /// Review mode: back to the dashboard / home; also the header's back arrow.
  final VoidCallback? onBack;

  /// Label for the review-mode back action.
  final String backLabel;

  /// Whether to show the celebration overlay on mount. Ignored in review
  /// mode — reopening the summary never replays the celebration.
  final bool showCelebration;

  /// Writes the run's Recommended Settings to the child's settings. Null
  /// leaves the card read-only, which is what a host with no child to write
  /// to — the game lab, a preview — should pass.
  final Future<bool> Function()? onApplyRecommendations;

  final Duration celebrationDuration;

  /// Optional page background decoration (defaults to the flat app canvas).
  final Decoration? background;

  @override
  State<AssessmentResultLayout> createState() => _AssessmentResultLayoutState();
}

class _AssessmentResultLayoutState extends State<AssessmentResultLayout> {
  static const double _twoColumnBreakpoint = 720;
  static const double _threeColumnBreakpoint = 1080;

  bool _showCelebration = false;

  bool get _isCompletion =>
      widget.presentation == AssessmentResultPresentation.completion;

  bool get _dense => !_isCompletion;

  @override
  void initState() {
    super.initState();
    _showCelebration = _isCompletion && widget.showCelebration;
    if (_showCelebration) {
      Future.delayed(widget.celebrationDuration, () {
        if (mounted) setState(() => _showCelebration = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          DecoratedBox(
            decoration:
                widget.background ??
                const BoxDecoration(color: AppColors.background),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns =
                      width >= _threeColumnBreakpoint
                          ? 3
                          : width >= _twoColumnBreakpoint
                          ? 2
                          : 1;
                  final isWide = columns > 1;

                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: switch (columns) {
                          3 => 1320,
                          2 => 920,
                          _ => 560,
                        },
                      ),
                      // One predictable page scroll — no column ever scrolls
                      // on its own.
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: isWide ? 32 : 20,
                          vertical: isWide ? 28 : 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AssessmentResultHeader(
                              model: widget.model,
                              presentation: widget.presentation,
                              onBack: _isCompletion ? null : widget.onBack,
                            ),
                            SizedBox(height: isWide ? 24 : 18),
                            _buildBody(columns),
                            const SizedBox(height: 20),
                            const AssessmentDisclaimer(),
                            const SizedBox(height: 16),
                            AssessmentResultActions(
                              presentation: widget.presentation,
                              onContinue: widget.onContinue,
                              onRetake: widget.onRetake,
                              onBack: widget.onBack,
                              backLabel: widget.backLabel,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_showCelebration)
            const GameCelebrationOverlay(
              emoji: '🏆',
              message: 'You Did It!',
              subMessage: 'Amazing job finishing all the games!',
              isBigCelebration: true,
            ),
        ],
      ),
    );
  }

  // ── Sections ─────────────────────────────────────────────────────────

  /// Section order, identical in every orientation and column count:
  /// overview → progress → profile → game results → recommended settings →
  /// recommended activities.
  ///
  /// Progress sits directly under the overview: when a parent has run a
  /// second assessment, "did this help?" is the question they opened the
  /// screen to answer.
  List<Widget> _sections() {
    final model = widget.model;
    final progress = model.progress;
    return [
      AssessmentOverviewCard(model: model, dense: _dense),
      if (progress != null && progress.hasAreas)
        AssessmentProgressCard(progress: progress, dense: _dense),
      if (model.hasAreas || model.sensoryObservations.isNotEmpty)
        AssessmentProfileCard(model: model, dense: _dense),
      if (model.games.isNotEmpty)
        AssessmentGameResultsCard(games: model.games, dense: _dense),
      if (model.recommendations.isNotEmpty)
        AssessmentRecommendationsCard(
          recommendations: model.recommendations,
          dense: _dense,
          onApply: widget.onApplyRecommendations,
        ),
      if (model.hasLearningPath || model.learningPathUnavailable)
        AssessmentLearningPathCard(
          modules: model.learningPath,
          unavailable: model.learningPathUnavailable,
          dense: _dense,
        ),
    ];
  }

  Widget _buildBody(int columns) {
    final sections = _sections();
    if (columns == 1) return _stacked(sections);

    // Split the sections into contiguous, balanced runs — reading down one
    // column and on to the next keeps the canonical order at every width.
    final perColumn = (sections.length / columns).ceil();
    final buckets = <List<Widget>>[
      for (var start = 0; start < sections.length; start += perColumn)
        sections.sublist(
          start,
          start + perColumn > sections.length
              ? sections.length
              : start + perColumn,
        ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < buckets.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(child: _stacked(buckets[i])),
        ],
      ],
    );
  }

  Widget _stacked(List<Widget> cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) SizedBox(height: _dense ? 10 : 14),
          cards[i],
        ],
      ],
    );
  }
}
