import 'package:game_core/game_core.dart';

import '../core/services/local_db_service.dart';
import '../features/history/history_models.dart';
import '../model/assessment_result.dart';
import '../model/assessment_run_record.dart';
import '../model/gameplay_session.dart';
import 'learning_path_service.dart';

/// Builds the parent-facing history summary for a child.
///
/// Reads the local database once per underlying table, groups rows by
/// assessment run, and assembles a [HistorySummary] for the history screen.
/// The service takes plain data in — it does not read provider state.
class ParentHistoryService {
  ParentHistoryService({LocalDbService? localDb})
    : _localDb = localDb ?? localDbService;

  final LocalDbService _localDb;

  /// Skill areas in the fixed display order.
  static const List<String> areaOrder = [
    'Communication',
    'Social Interaction',
    'Play Skills',
    'Attention & Focus',
    'Sensory Preference',
  ];

  /// More conservative labels rank higher, so ties resolve toward them.
  static const Map<String, int> _conservativeRank = {
    'Needs Support': 2,
    'Emerging': 1,
    'Strength': 0,
  };

  Future<HistorySummary> loadHistory({
    required String childId,
    required List<LearningPathEntry> path,
    required Set<String> pathCompletedGameIds,
  }) async {
    final runs = await _localDb.getAssessmentRuns(childId: childId);
    final results = await _localDb.getAssessmentResults(childId: childId);
    final sessions = await _localDb.getGameSessions(childId: childId);

    // Group assessment results by their run.
    final resultsByRun = <String, List<AssessmentResult>>{};
    for (final result in results) {
      final runId = result.assessmentRunId;
      if (runId == null) continue;
      resultsByRun.putIfAbsent(runId, () => <AssessmentResult>[]).add(result);
    }

    // Group run sessions by run; collect practice sessions separately.
    final sessionsByRun = <String, List<GameplaySession>>{};
    final practiceSessions = <GameplaySession>[];
    for (final session in sessions) {
      if (session.context == 'practice') {
        practiceSessions.add(session);
        continue;
      }
      final runId = session.assessmentRunId;
      if (runId != null) {
        sessionsByRun
            .putIfAbsent(runId, () => <GameplaySession>[])
            .add(session);
      }
    }

    // Runs, newest first by startedAt.
    final sortedRuns = [...runs]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    final runHistories = <AssessmentRunHistory>[];
    for (final run in sortedRuns) {
      final runSessions =
          (sessionsByRun[run.id] ?? <GameplaySession>[])
            ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
      final runResults = resultsByRun[run.id] ?? <AssessmentResult>[];

      final games = <RunGameRecord>[];
      for (final session in runSessions) {
        games.add(
          RunGameRecord(
            gameId: session.gameId,
            gameName:
                GameRegistry.find(session.gameId)?.name ??
                session.gameId.replaceAll('_', ' '),
            score: session.score,
            totalItems: session.totalItems,
            errorCount: session.errorCount,
            accuracy: _adjustedAccuracy(session.score, session.errorCount),
            configLabel: configLabelFor(session.configurationVersion),
            endedAt: session.endedAt,
          ),
        );
      }

      final overallAccuracy =
          games.isEmpty
              ? 0.0
              : games.fold<double>(0.0, (sum, g) => sum + g.accuracy) /
                  games.length;

      String? recommendedModule;
      for (final result in runResults) {
        if (result.recommendedModule != null) {
          recommendedModule = result.recommendedModule;
          break;
        }
      }

      String? overallSummary;
      for (final result in runResults) {
        if (result.overallSummary != null) {
          overallSummary = result.overallSummary;
          break;
        }
      }

      runHistories.add(
        AssessmentRunHistory(
          run: run,
          games: games,
          overallAccuracy: overallAccuracy,
          skills: aggregateSkills(runResults),
          recommendedModule: recommendedModule,
          overallSummary: overallSummary,
        ),
      );
    }

    // Completed modules — exactly zero or one: the My Path completion.
    final completedModules = <CompletedModuleRecord>[];
    if (path.isNotEmpty &&
        LearningPathService.isComplete(path, pathCompletedGameIds)) {
      final pathGameIds = path.map((e) => e.game.id).toSet();
      final pathPractice =
          practiceSessions.where((s) => pathGameIds.contains(s.gameId)).toList()
            ..sort((a, b) => a.endedAt.compareTo(b.endedAt));
      completedModules.add(
        CompletedModuleRecord(
          moduleId: 'my_path',
          moduleName: 'My Path',
          completedAt: pathPractice.isEmpty ? null : pathPractice.last.endedAt,
          status: 'completed',
          level: 0,
          maxLevel: 0,
          source: 'my_path',
          gameCount: path.length,
        ),
      );
    }

    // Practice sessions, newest first, capped at 20.
    final practice = [...practiceSessions]
      ..sort((a, b) => b.endedAt.compareTo(a.endedAt));

    // Pre-vs-post comparison when both a completed pre and post run exist.
    ProgressComparison? comparison;
    final completedPre =
        runHistories
            .where((h) => h.run.isCompleted && h.run.type == 'pre')
            .toList()
          ..sort(
            (a, b) => _completedStamp(a.run).compareTo(_completedStamp(b.run)),
          );
    final completedPost =
        runHistories
            .where((h) => h.run.isCompleted && h.run.type == 'post')
            .toList()
          ..sort(
            (a, b) => _completedStamp(a.run).compareTo(_completedStamp(b.run)),
          );

    if (completedPre.isNotEmpty && completedPost.isNotEmpty) {
      final pre = completedPre.last;
      final post = completedPost.last;

      final areas = <AreaComparisonRow>[];
      for (final area in areaOrder) {
        final preEntry = _entryFor(pre.skills, area);
        final postEntry = _entryFor(post.skills, area);
        if (preEntry == null && postEntry == null) continue;
        areas.add(
          AreaComparisonRow(
            area: area,
            before: preEntry?.label,
            after: postEntry?.label,
          ),
        );
      }

      comparison = ProgressComparison(pre: pre, post: post, areas: areas);
    }

    return HistorySummary(
      runs: runHistories,
      completedModules: completedModules,
      practiceSessions: practice.take(20).toList(),
      comparison: comparison,
    );
  }

  /// Maps a session's analytics configuration version to a display flow label.
  static String configLabelFor(String? configurationVersion) {
    switch (configurationVersion) {
      case 'three-round-v1':
        return '3-round flow';
      case 'sensory-four-round-v1':
        return '4-round sensory flow';
      case 'sensory-three-round-v1':
        return '3-round sensory flow';
      default:
        return 'Legacy';
    }
  }

  /// Aggregates rubric labels across a run's result rows into one label per
  /// area. Only non-null labels count; ties break toward the more
  /// conservative label (Needs Support > Emerging > Strength).
  static List<SkillBreakdownEntry> aggregateSkills(
    Iterable<AssessmentResult> runResults,
  ) {
    final results = runResults.toList();
    final entries = <SkillBreakdownEntry>[];

    for (final area in areaOrder) {
      final counts = <String, int>{};
      for (final result in results) {
        final label = _labelForArea(result, area);
        if (label != null) {
          counts[label] = (counts[label] ?? 0) + 1;
        }
      }
      if (counts.isEmpty) continue;

      var maxCount = 0;
      for (final count in counts.values) {
        if (count > maxCount) maxCount = count;
      }

      String? winner;
      for (final entry in counts.entries) {
        if (entry.value != maxCount) continue;
        if (winner == null) {
          winner = entry.key;
        } else if ((_conservativeRank[entry.key] ?? 0) >
            (_conservativeRank[winner] ?? 0)) {
          winner = entry.key;
        }
      }
      entries.add(SkillBreakdownEntry(area: area, label: winner!));
    }
    return entries;
  }

  static String? _labelForArea(AssessmentResult result, String area) {
    switch (area) {
      case 'Communication':
        return result.communicationLabel;
      case 'Social Interaction':
        return result.socialInteractionLabel;
      case 'Play Skills':
        return result.playSkillsLabel;
      case 'Attention & Focus':
        return result.behaviorAttentionLabel;
      case 'Sensory Preference':
        return result.sensoryPreferenceLabel;
    }
    return null;
  }

  static SkillBreakdownEntry? _entryFor(
    List<SkillBreakdownEntry> skills,
    String area,
  ) {
    for (final entry in skills) {
      if (entry.area == area) return entry;
    }
    return null;
  }

  static DateTime _completedStamp(AssessmentRunRecord run) =>
      run.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// App-wide adjusted accuracy: `score / (score + errorCount)`, clamped to
  /// 0..1, 0.0 when both score and errorCount are zero.
  static double _adjustedAccuracy(int score, int errorCount) {
    final total = score + errorCount;
    if (total <= 0) return 0.0;
    return (score / total).clamp(0.0, 1.0);
  }
}
