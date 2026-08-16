import 'package:shared_ui/shared_ui.dart';

import '../model/assessment_run_snapshot.dart';
import 'assessment_result_mapper.dart';

/// Builds the pre → post comparison shown on the parent's assessment
/// summary (AUM-161).
///
/// Two runs are only worth putting side by side when they measured the same
/// thing for the same child. [areComparable] is that rule, kept in one place
/// so no surface can accidentally compare runs that do not line up — an
/// invented improvement is worse than no comparison at all.
abstract final class AssessmentProgressService {
  /// Whether [before] and [after] describe the same child's progress on the
  /// same scale, and can therefore be compared.
  ///
  /// Requires: the same child; a real before/after ordering; both runs
  /// finalized with the levels the comparison reads; and at least one
  /// developmental area present in both. Runs from different children, the
  /// same run twice, or a run whose levels were never stored are not
  /// comparable.
  static bool areComparable(
    AssessmentRunSnapshot? before,
    AssessmentRunSnapshot? after,
  ) {
    if (before == null || after == null) return false;
    if (before.childId != after.childId) return false;
    if (before.results.isEmpty || after.results.isEmpty) return false;
    // A distinct, later run — not the same run read twice, and never a
    // "later" run that actually predates the baseline.
    if (before.assessmentRunId != null &&
        before.assessmentRunId == after.assessmentRunId) {
      return false;
    }
    if (!after.completedAt.isAfter(before.completedAt)) return false;
    return _sharedAreas(before, after).isNotEmpty;
  }

  /// The comparison for these two runs, or null when they are not
  /// comparable. Only areas present in *both* runs are included, so adding
  /// or dropping an area between runs never fabricates a change.
  static ResultProgress? compare({
    required AssessmentRunSnapshot? before,
    required AssessmentRunSnapshot? after,
  }) {
    if (!areComparable(before, after)) return null;
    final shared = _sharedAreas(before!, after!);
    if (shared.isEmpty) return null;

    return ResultProgress(
      areas: shared,
      beforeCompletedAt: before.completedAt,
      afterCompletedAt: after.completedAt,
    );
  }

  /// Areas that both runs reported, in the canonical display order.
  static List<ResultProgressArea> _sharedAreas(
    AssessmentRunSnapshot before,
    AssessmentRunSnapshot after,
  ) {
    final beforeLevels = _levelsFor(before);
    final afterLevels = _levelsFor(after);

    return [
      for (final title in AssessmentResultMapper.areaTitles.values)
        if (beforeLevels[title] != null && afterLevels[title] != null)
          ResultProgressArea(
            label: title,
            beforeLevelName: beforeLevels[title]!.levelName,
            afterLevelName: afterLevels[title]!.levelName,
            beforeLevelInt: beforeLevels[title]!.levelInt,
            afterLevelInt: afterLevels[title]!.levelInt,
          ),
    ];
  }

  /// The finalized area levels for a run, keyed by display title.
  ///
  /// Read through the same mapper the result screens use, so a comparison
  /// can never show a level that differs from the one on the run's own
  /// summary. A run with no stored profile contributes nothing.
  static Map<String, ResultAreaLevel> _levelsFor(
    AssessmentRunSnapshot snapshot,
  ) {
    final profile = snapshot.profile;
    if (profile == null) return const {};
    final areas = AssessmentResultMapper.buildAreas(
      profile: profile,
      aiResponse: snapshot.prediction,
    );
    return {for (final area in areas) area.label: area};
  }
}
