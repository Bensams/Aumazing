/// Plain data classes for the [AssessmentResultLayout] widget.
///
/// These are framework-agnostic value objects that both main_app and game_lab
/// can construct from their own domain models (or from hardcoded mock data).
///
/// [AssessmentResultViewModel] is the canonical result model: it is built
/// **once** from a finalized assessment run and rendered by both the
/// immediate completion screen and the later Assessment Summary review, so
/// the two can never disagree about what the assessment found.
library;

import 'package:flutter/material.dart';

/// How the shared result layout is being presented.
enum AssessmentResultPresentation {
  /// Immediately after the child finishes: celebratory and explanatory.
  completion,

  /// Opened later by the parent: compact, built for review / retake.
  review,
}

/// Where the developmental analysis came from.
///
/// The display labels are fixed terminology — both presentations show the
/// same string for the same source.
enum AssessmentAnalysisSource {
  /// Cloud AI model (XGBoost API).
  cloudAi('AI Analysis'),

  /// On-device ONNX model.
  onDeviceAi('On-Device AI'),

  /// Local rubric / rule-based scoring — no model prediction available.
  ruleBased('Rule-Based');

  const AssessmentAnalysisSource(this.label);

  /// Parent-facing label. Identical in completion and review mode.
  final String label;

  bool get isAi => this != AssessmentAnalysisSource.ruleBased;
}

/// Fixed section headings and copy shared by both presentations.
///
/// Terminology lives here so the two screens cannot drift apart (no more
/// "Prompts" vs "Prompt Style" or "Recommendations" vs "Recommended
/// Settings").
abstract final class AssessmentLabels {
  static const title = 'Assessment Summary';
  static const overallPerformance = 'Overall Performance';
  static const gameResults = 'Game Results';
  static const developmentalProfile = 'Developmental Profile';
  static const recommendedSettings = 'Recommended Settings';
  static const recommendedActivities = 'Recommended Activities';
  static const progressSinceFirst = 'Progress Since the First Assessment';
  static const aiAnalysis = 'AI Analysis';
  static const onDeviceAi = 'On-Device AI';
  static const ruleBased = 'Rule-Based';

  static const difficulty = 'Difficulty';
  static const promptStyle = 'Prompt Style';
  static const sessionLength = 'Session Length';
  static const promptRepetition = 'Prompt Repetition';
  static const lowStimulationMode = 'Low-Stimulation Mode';
  static const turnTakingPractice = 'Turn-Taking Practice';

  static const correct = 'Correct';
  static const errors = 'Errors';
  static const totalItems = 'Total Items';
  static const confidence = 'Confidence';
  static const sensory = 'Sensory';

  static const disclaimer =
      'Not a clinical diagnosis. These observations are only used to '
      'customize your child’s learning activities.';

  static const continueToHome = 'Continue to Home';
  static const retakeAssessment = 'Retake Assessment';
  static const backToDashboard = 'Back to Dashboard';
  static const home = 'Home';
  static const tryAgain = 'Try Again';

  /// Shown when a run could not be started, saved or finalized.
  static const couldNotStart =
      'We could not start the assessment. Please check your connection and '
      'try again.';
  static const couldNotSave =
      'We could not save this assessment. Nothing has been lost — please try '
      'again.';
}

/// A single developmental area with its predicted level.
class ResultAreaLevel {
  const ResultAreaLevel({
    required this.label,
    required this.levelName,
    required this.levelInt,
    this.confidence = 0.0,
  });

  /// Display name, e.g. "Communication", "Social Interaction".
  final String label;

  /// Human-readable level, e.g. "Needs Support", "Emerging", "Strength".
  final String levelName;

  /// Ordinal: 0 = Needs Support, 1 = Emerging, 2 = Strength.
  final int levelInt;

  /// Model confidence for this area (0.0–1.0). Not displayed but kept
  /// for potential future use.
  final double confidence;
}

/// A single game's result for the Game Results card.
class ResultGameScore {
  const ResultGameScore({
    required this.gameId,
    required this.name,
    required this.emoji,
    required this.accuracy,
    this.correctCount = 0,
    this.errorCount = 0,
    this.totalItems = 0,
  });

  final String gameId;
  final String name;
  final String emoji;

  /// Adjusted accuracy (0.0–1.0): `correct / (correct + errors)`.
  ///
  /// This — never the raw `score / totalItems` ratio — is what the UI shows
  /// as a percentage. See [AssessmentScoring].
  final double accuracy;

  /// Raw counts, displayed separately from [accuracy].
  final int correctCount;
  final int errorCount;
  final int totalItems;
}

/// A recommended learning module with its starting level.
class ResultModule {
  const ResultModule({
    required this.name,
    required this.startingLevel,
    this.reason,
  });

  final String name;
  final int startingLevel;

  /// Why this activity was chosen, in a parent's words (AUM-161) — e.g.
  /// "Builds Communication, the area with the most room to grow right now".
  ///
  /// Describes what the activity practises and why it comes next. It is
  /// never a claim about the child themselves, and never diagnostic: the
  /// assessment reports skills observed in a game, not a condition.
  final String? reason;
}

/// How one developmental area moved between two assessment runs (AUM-161).
class ResultProgressArea {
  const ResultProgressArea({
    required this.label,
    required this.beforeLevelName,
    required this.afterLevelName,
    required this.beforeLevelInt,
    required this.afterLevelInt,
  });

  /// Display name, e.g. "Communication".
  final String label;

  final String beforeLevelName;
  final String afterLevelName;

  /// Ordinals: 0 = Needs Support, 1 = Emerging, 2 = Strength.
  final int beforeLevelInt;
  final int afterLevelInt;

  /// Positive = moved up, negative = moved down, 0 = held steady.
  int get delta => afterLevelInt - beforeLevelInt;

  bool get improved => delta > 0;
  bool get steady => delta == 0;
}

/// A before-and-after comparison of two assessment runs (AUM-161).
///
/// Deliberately describes *what the child did in the activities* and how
/// those skill areas moved — never a condition, a diagnosis, or a claim
/// about the child themselves. Only runs the app considers comparable ever
/// reach here; the app-side progress service owns that rule.
class ResultProgress {
  const ResultProgress({
    required this.areas,
    required this.beforeCompletedAt,
    required this.afterCompletedAt,
  });

  final List<ResultProgressArea> areas;
  final DateTime beforeCompletedAt;
  final DateTime afterCompletedAt;

  int get improvedCount => areas.where((a) => a.improved).length;
  int get steadyCount => areas.where((a) => a.steady).length;

  bool get hasAreas => areas.isNotEmpty;

  /// One plain sentence a parent can read at a glance. Growth is stated
  /// warmly; no growth is stated neutrally, never as a failure or concern.
  String get headline {
    if (areas.isEmpty) return 'No areas could be compared between these two.';
    final improved = improvedCount;
    final noun = areas.length == 1 ? 'area' : 'areas';
    if (improved == 0) {
      return 'Skills held steady across ${areas.length} $noun since the '
          'first assessment.';
    }
    return 'Grew in $improved of ${areas.length} skill $noun since the '
        'first assessment.';
  }
}

/// A single row in the Recommended Settings card.
class ResultRecommendation {
  const ResultRecommendation({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

/// A single row in the Developmental Profile card.
class ResultProfileRow {
  const ResultProfileRow({required this.area, required this.level});

  final String area;
  final String level;
}

/// The one scoring policy used by every assessment result surface.
///
/// **Per-game accuracy** is [ResultGameScore.accuracy] — the *adjusted*
/// accuracy `correct / (correct + errors)`, which penalises errors even in
/// games that retry until the child is right (where `score / totalItems`
/// is always 1.0).
///
/// **Overall accuracy** is the item-weighted mean of those adjusted
/// accuracies: `sum(adjustedAccuracy × totalItems) / sum(totalItems)`. A raw
/// `score / totalItems` ratio is never displayed as "Overall Performance",
/// because it would not be comparable with the per-game percentages next to
/// it. Raw counts are still shown, but labelled as counts.
abstract final class AssessmentScoring {
  /// Item-weighted overall adjusted accuracy (0.0–1.0).
  ///
  /// Returns 0.0 for an empty list or when every game reports zero items,
  /// so an empty or malformed result set can never divide by zero.
  static double overallAdjustedAccuracy(Iterable<ResultGameScore> games) {
    var weighted = 0.0;
    var items = 0;
    for (final game in games) {
      if (game.totalItems <= 0) continue;
      weighted += game.accuracy.clamp(0.0, 1.0) * game.totalItems;
      items += game.totalItems;
    }
    if (items <= 0) return 0.0;
    return (weighted / items).clamp(0.0, 1.0);
  }

  static int correctCount(Iterable<ResultGameScore> games) =>
      games.fold(0, (sum, g) => sum + g.correctCount);

  static int errorCount(Iterable<ResultGameScore> games) =>
      games.fold(0, (sum, g) => sum + g.errorCount);

  static int totalItems(Iterable<ResultGameScore> games) =>
      games.fold(0, (sum, g) => sum + g.totalItems);

  /// Percent (0–100) for display, rounded once so both modes round alike.
  static int percent(double ratio) => (ratio.clamp(0.0, 1.0) * 100).round();
}

/// The canonical, immutable result of one finalized assessment run.
///
/// Built once (see main_app's `AssessmentResultMapper`) and handed to the
/// shared layout in either presentation mode. It deliberately carries the
/// values *as finalized* — the sensory observations and recommendations
/// recorded with the run — so reopening the summary after the parent has
/// changed the child's current settings cannot rewrite history.
@immutable
class AssessmentResultViewModel {
  AssessmentResultViewModel({
    required this.assessmentType,
    required this.games,
    required this.areas,
    required this.recommendations,
    required this.source,
    this.assessmentRunId,
    this.completedAt,
    this.confidence,
    this.summary = '',
    this.profileDisplayName,
    this.supportLevel,
    this.learningPath = const [],
    this.sensoryObservations = const [],
    this.learningPathUnavailable = false,
    this.progress,
  }) : correctCount = AssessmentScoring.correctCount(games),
       errorCount = AssessmentScoring.errorCount(games),
       totalItems = AssessmentScoring.totalItems(games),
       overallAdjustedAccuracy = AssessmentScoring.overallAdjustedAccuracy(
         games,
       );

  /// 'pre' or 'post'.
  final String assessmentType;

  /// Identifies the exact result set this model was built from.
  final String? assessmentRunId;

  /// When the run finished, when known.
  final DateTime? completedAt;

  /// Raw counts, summed across [games]. Shown as counts, never as the
  /// overall percentage.
  final int correctCount;
  final int errorCount;
  final int totalItems;

  /// Item-weighted mean of the per-game adjusted accuracies (0.0–1.0).
  final double overallAdjustedAccuracy;

  final List<ResultGameScore> games;

  /// Developmental areas with their finalized levels.
  final List<ResultAreaLevel> areas;

  /// Before-and-after comparison against an earlier comparable run, when one
  /// exists (AUM-161). Null when this is the only run, or when the two runs
  /// are not comparable.
  final ResultProgress? progress;

  bool get hasProgress => progress?.hasAreas ?? false;

  /// Recommended settings as finalized with the run.
  final List<ResultRecommendation> recommendations;

  final AssessmentAnalysisSource source;

  /// Overall model confidence (0.0–1.0), or null when there is none.
  final double? confidence;

  /// Parent-friendly narrative summary.
  final String summary;

  /// Legacy single-profile display name, when the model emitted one.
  final String? profileDisplayName;

  /// 'low' | 'moderate' | 'high', when known.
  final String? supportLevel;

  /// Recommended activities in the child's "My Path" order.
  final List<ResultModule> learningPath;

  /// Sensory notes captured when the assessment was finalized.
  final List<String> sensoryObservations;

  /// True when every recommendation was filtered out (no active games).
  final bool learningPathUnavailable;

  /// Overall performance as a whole percent.
  int get overallPercent => AssessmentScoring.percent(overallAdjustedAccuracy);

  /// Confidence as a whole percent, or null when there is no confidence.
  int? get confidencePercent {
    final value = confidence;
    return value == null ? null : AssessmentScoring.percent(value);
  }

  bool get hasAreas => areas.isNotEmpty;
  bool get hasLearningPath => learningPath.isNotEmpty;

  /// Developmental Profile rows including the sensory observations, which
  /// render as free-form text rather than a level meter.
  List<ResultProfileRow> get profileRows => [
    for (final area in areas)
      ResultProfileRow(area: area.label, level: area.levelName),
    if (sensoryObservations.isNotEmpty)
      ResultProfileRow(
        area: AssessmentLabels.sensory,
        level: sensoryObservations.join(', '),
      ),
  ];
}
