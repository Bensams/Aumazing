import '../../model/assessment_run_record.dart';
import '../../model/gameplay_session.dart';

/// The full history payload the parent history screen renders.
///
/// Built by ParentHistoryService.loadHistory; consumed read-only by the UI.
class HistorySummary {
  final List<AssessmentRunHistory> runs;

  /// At most one record: the My Path completion, present only when the
  /// recommended learning path has been fully completed.
  final List<CompletedModuleRecord> completedModules;

  /// Practice sessions, newest first, capped at 20.
  final List<GameplaySession> practiceSessions;

  /// Pre-vs-post progress, null unless both a completed pre and a completed
  /// post run exist.
  final ProgressComparison? comparison;

  const HistorySummary({
    required this.runs,
    required this.completedModules,
    required this.practiceSessions,
    required this.comparison,
  });
}

/// One assessment run with its games, aggregated accuracy, and skill labels.
class AssessmentRunHistory {
  final AssessmentRunRecord run;

  /// Sessions of the run, ordered startedAt ascending.
  final List<RunGameRecord> games;

  /// Mean of per-game [RunGameRecord.accuracy]; 0.0 when there are no games.
  final double overallAccuracy;

  /// Aggregated per-area labels, in the fixed area order. Only areas that
  /// have at least one non-null label across the run's results appear.
  final List<SkillBreakdownEntry> skills;

  /// First non-null recommended module among the run's result rows.
  final String? recommendedModule;

  /// First non-null overall summary among the run's result rows.
  final String? overallSummary;

  const AssessmentRunHistory({
    required this.run,
    required this.games,
    required this.overallAccuracy,
    required this.skills,
    required this.recommendedModule,
    required this.overallSummary,
  });
}

/// One game played within an assessment run.
class RunGameRecord {
  final String gameId;

  /// Human-readable game name — GameRegistry.find's name, falling back to
  /// the game id with underscores replaced by spaces.
  final String gameName;

  final int score;
  final int totalItems;
  final int errorCount;

  /// App-wide adjusted accuracy: `score / (score + errorCount)`, clamped to
  /// 0..1, 0.0 when both score and errorCount are zero.
  final double accuracy;

  /// Flow label from the session's analytics configuration version.
  final String? configLabel;

  final DateTime endedAt;

  const RunGameRecord({
    required this.gameId,
    required this.gameName,
    required this.score,
    required this.totalItems,
    required this.errorCount,
    required this.accuracy,
    required this.configLabel,
    required this.endedAt,
  });
}

/// An aggregated skill label for one developmental area.
class SkillBreakdownEntry {
  /// One of: 'Communication', 'Social Interaction', 'Play Skills',
  /// 'Attention & Focus', 'Sensory Preference'.
  final String area;

  /// One of: 'Strength', 'Emerging', 'Needs Support'.
  final String label;

  const SkillBreakdownEntry({required this.area, required this.label});
}

/// A completed learning milestone shown on the history screen.
class CompletedModuleRecord {
  final String moduleId;

  /// 'My Path' for the My Path record.
  final String moduleName;

  final DateTime? completedAt;

  /// 'completed'.
  final String status;

  /// 0 for the current My Path record; module_progress rows carry their level.
  final int level;

  /// 0 for the current My Path record; module_progress rows carry their max.
  final int maxLevel;

  /// 'module_progress' | 'my_path': the current derived path completion vs a
  /// durable module_progress row (an older path a later recommendation
  /// replaced, or any completed recommendation module).
  final String source;

  /// Path length for My Path rows (current or module_progress), else 0.
  final int gameCount;

  const CompletedModuleRecord({
    required this.moduleId,
    required this.moduleName,
    required this.completedAt,
    required this.status,
    required this.level,
    required this.maxLevel,
    required this.source,
    required this.gameCount,
  });
}

/// Pre- vs post-assessment progress for a child.
class ProgressComparison {
  final AssessmentRunHistory pre;
  final AssessmentRunHistory post;
  final List<AreaComparisonRow> areas;

  const ProgressComparison({
    required this.pre,
    required this.post,
    required this.areas,
  });

  /// Difference in overall accuracy in percentage points.
  double get overallDeltaPoints =>
      (post.overallAccuracy - pre.overallAccuracy) * 100;
}

/// One skill area's before/after label in a [ProgressComparison].
class AreaComparisonRow {
  final String area;
  final String? before;
  final String? after;

  const AreaComparisonRow({
    required this.area,
    required this.before,
    required this.after,
  });
}
