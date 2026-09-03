import '../model/area_level.dart';
import '../model/assessment_result.dart';
import '../model/gameplay_session.dart';

/// Parent-readable evidence for one developmental skill area.
///
/// The level is the finalized rubric interpretation already stored with the
/// assessment. The percentage is supporting activity evidence; it does not
/// independently calculate or replace the level.
class ParentSkillAreaSummary {
  const ParentSkillAreaSummary({
    required this.key,
    required this.label,
    required this.levelName,
    required this.levelInt,
    required this.metricLabel,
    required this.metricPercent,
    this.detail,
  });

  final String key;
  final String label;
  final String levelName;
  final int? levelInt;
  final String metricLabel;
  final int? metricPercent;
  final String? detail;

  String get metricText =>
      metricPercent == null
          ? 'Supporting percentage unavailable'
          : '$metricPercent% $metricLabel';
}

/// The latest parent-facing picture of one finalized assessment run.
class ParentSkillRunSummary {
  const ParentSkillRunSummary({
    required this.assessmentType,
    required this.areas,
    required this.overallActivityAccuracy,
  });

  final String assessmentType;
  final List<ParentSkillAreaSummary> areas;
  final double overallActivityAccuracy;

  ParentSkillAreaSummary? area(String key) {
    for (final area in areas) {
      if (area.key == key) return area;
    }
    return null;
  }
}

/// One skill area's before-and-after interpretation and supporting metric.
class ParentSkillAreaProgress {
  const ParentSkillAreaProgress({required this.before, required this.after});

  final ParentSkillAreaSummary before;
  final ParentSkillAreaSummary after;

  int? get levelDelta {
    if (before.levelInt == null || after.levelInt == null) return null;
    return after.levelInt! - before.levelInt!;
  }

  int? get metricDelta {
    if (before.metricPercent == null || after.metricPercent == null) {
      return null;
    }
    if (before.metricLabel != after.metricLabel) return null;
    return after.metricPercent! - before.metricPercent!;
  }
}

/// A comparable pre → post parent summary.
class ParentSkillProgressSummary {
  const ParentSkillProgressSummary({
    required this.areas,
    required this.overallAccuracyDelta,
  });

  final List<ParentSkillAreaProgress> areas;

  /// Ratio delta (`post - pre`). Multiply by 100 for percentage points.
  final double overallAccuracyDelta;

  int get improvedAreaCount =>
      areas.where((area) => (area.levelDelta ?? 0) > 0).length;
}

/// Converts existing assessment data into a concise, transparent parent view.
///
/// This service is deliberately read-only. It does not recalculate rubric
/// bands, modify thresholds, or write new fields to local storage/Supabase.
abstract final class ParentSkillSummaryService {
  static const _communicationGames = {'copy_me', 'do_what_i_say'};
  static const _playGames = {'match_it', 'copy_me'};
  static const _socialGame = 'my_turn_your_turn';

  /// Builds the four areas in the parent-requested display order.
  ///
  /// [areaLevels] is the finalized per-area interpretation from the run's AI
  /// prediction (the same source the Assessment Summary's Developmental Profile
  /// uses). When provided, it decides each area's level so this snapshot and the
  /// summary always agree; the rubric labels on [results] are only used as the
  /// fallback when no prediction is available. The supporting percentages/detail
  /// still come from the activity data either way.
  static ParentSkillRunSummary build({
    required String assessmentType,
    required List<AssessmentResult> results,
    Iterable<GameplaySession> sessions = const [],
    Map<String, AreaLevel>? areaLevels,
  }) {
    final runId = _latestRunId(results);
    final runResults =
        runId == null
            ? results
            : results
                .where((result) => result.assessmentRunId == runId)
                .toList();
    final runSessions =
        runId == null
            ? const <GameplaySession>[]
            : sessions
                .where((session) => session.assessmentRunId == runId)
                .toList();

    final communicationResults =
        runResults
            .where((result) => _communicationGames.contains(result.gameId))
            .toList();
    final playResults =
        runResults
            .where((result) => _playGames.contains(result.gameId))
            .toList();
    final socialResults =
        runResults.where((result) => result.gameId == _socialGame).toList();

    final socialSessions =
        runSessions.where((session) => session.gameId == _socialGame).toList();
    final turnTaking = _meanNullable(
      socialSessions.map((session) => session.turnTakingSuccessRate),
    );
    final interruptions = _meanNullable(
      socialSessions.map((session) => session.interruptionCount?.toDouble()),
    );

    final completion =
        runSessions.isEmpty
            ? _weightedRawCompletion(runResults)
            : _mean(
              runSessions.map(
                (session) =>
                    session.taskCompletionRate ??
                    (session.totalItems <= 0
                        ? 0.0
                        : (session.score / session.totalItems).clamp(0.0, 1.0)),
              ),
            );
    final averageIdle =
        runSessions.isEmpty
            ? null
            : _mean(runSessions.map((session) => session.idleTimeSeconds));
    final averageRandomTouches =
        runSessions.isEmpty
            ? null
            : _mean(
              runSessions.map((session) => session.randomTouchCount.toDouble()),
            );

    return ParentSkillRunSummary(
      assessmentType: assessmentType,
      overallActivityAccuracy: _weightedAdjustedAccuracy(runResults) ?? 0.0,
      areas: [
        _area(
          key: 'communication',
          label: 'Communication',
          rawLevel: _latestLabel(
            runResults,
            (result) => result.communicationLabel,
          ),
          aiLevel: areaLevels?['communication'],
          metricLabel: 'activity accuracy',
          metric: _weightedAdjustedAccuracy(communicationResults),
          detail: 'Copy Me and Do What I Say activities',
        ),
        _area(
          key: 'play',
          label: 'Play Skills',
          rawLevel: _latestLabel(
            runResults,
            (result) => result.playSkillsLabel,
          ),
          aiLevel: areaLevels?['play'],
          metricLabel: 'activity accuracy',
          metric: _weightedAdjustedAccuracy(playResults),
          detail: 'Match It and Copy Me activities',
        ),
        _area(
          key: 'social',
          label: 'Social Interaction',
          rawLevel: _latestLabel(
            runResults,
            (result) => result.socialInteractionLabel,
          ),
          aiLevel: areaLevels?['social'],
          metricLabel:
              turnTaking == null
                  ? 'activity accuracy'
                  : 'successful turn-taking',
          metric: turnTaking ?? _weightedAdjustedAccuracy(socialResults),
          detail:
              interruptions == null
                  ? 'My Turn, Your Turn activity'
                  : '${_number(interruptions)} average interruptions',
        ),
        _area(
          key: 'attention',
          label: 'Attention & Focus',
          rawLevel: _latestLabel(
            runResults,
            (result) => result.behaviorAttentionLabel,
          ),
          aiLevel: areaLevels?['attention'],
          metricLabel: 'tasks completed',
          metric: completion,
          detail:
              averageIdle == null || averageRandomTouches == null
                  ? 'Based on completion, idle time, and touch patterns'
                  : '${_number(averageIdle)}s average idle time · '
                      '${_number(averageRandomTouches)} average off-target touches',
        ),
      ],
    );
  }

  static ParentSkillProgressSummary compare({
    required ParentSkillRunSummary before,
    required ParentSkillRunSummary after,
  }) {
    final areas = <ParentSkillAreaProgress>[];
    for (final beforeArea in before.areas) {
      final afterArea = after.area(beforeArea.key);
      if (afterArea == null) continue;
      areas.add(ParentSkillAreaProgress(before: beforeArea, after: afterArea));
    }
    return ParentSkillProgressSummary(
      areas: areas,
      overallAccuracyDelta:
          after.overallActivityAccuracy - before.overallActivityAccuracy,
    );
  }

  static ParentSkillAreaSummary _area({
    required String key,
    required String label,
    required String? rawLevel,
    required String metricLabel,
    required double? metric,
    String? detail,
    AreaLevel? aiLevel,
  }) {
    final attention = key == 'attention';
    // The finalized AI prediction (when present) decides the level, so this
    // snapshot matches the summary's Developmental Profile. The rubric label is
    // only the fallback. The level *value* comes from the prediction; the level
    // *name* stays in this snapshot's vocabulary (e.g. Sustained/Variable for
    // attention) so wording is consistent within the card.
    final (String levelName, int? levelInt) = aiLevel != null
        ? (_nameForLevel(aiLevel.levelInt, attention: attention), aiLevel.levelInt)
        : _level(rawLevel, attention: attention);
    return ParentSkillAreaSummary(
      key: key,
      label: label,
      levelName: levelName,
      levelInt: levelInt,
      metricLabel: metricLabel,
      metricPercent: metric == null ? null : (metric * 100).round(),
      detail: detail,
    );
  }

  /// The snapshot's display name for a 0–2 level ordinal.
  static String _nameForLevel(int levelInt, {required bool attention}) {
    final i = levelInt.clamp(0, 2);
    return attention
        ? const ['Needs Support', 'Variable', 'Sustained'][i]
        : const ['Needs Support', 'Emerging', 'Strength'][i];
  }

  static (String, int?) _level(String? raw, {required bool attention}) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return ('Not enough data', null);
    }
    if (attention) {
      if (normalized.contains('sustained')) return ('Sustained', 2);
      if (normalized.contains('variable') || normalized.contains('moderate')) {
        return ('Variable', 1);
      }
      if (normalized.contains('support') || normalized.contains('short')) {
        return ('Needs Support', 0);
      }
    }
    if (normalized.contains('strength') || normalized.contains('strong')) {
      return ('Strength', 2);
    }
    if (normalized.contains('emerging') ||
        normalized.contains('developing') ||
        normalized.contains('good')) {
      return ('Emerging', 1);
    }
    if (normalized.contains('support')) return ('Needs Support', 0);
    return ('Not enough data', null);
  }

  static String? _latestLabel(
    List<AssessmentResult> results,
    String? Function(AssessmentResult) read,
  ) {
    final sorted = [...results]
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    for (final result in sorted) {
      final value = read(result);
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static String? _latestRunId(List<AssessmentResult> results) {
    if (results.isEmpty) return null;
    final sorted = [...results]
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    for (final result in sorted) {
      final runId = result.assessmentRunId;
      if (runId != null && runId.isNotEmpty) return runId;
    }
    return null;
  }

  static double? _weightedAdjustedAccuracy(Iterable<AssessmentResult> results) {
    var weighted = 0.0;
    var items = 0;
    for (final result in results) {
      if (result.totalItems <= 0) continue;
      weighted += result.adjustedAccuracy * result.totalItems;
      items += result.totalItems;
    }
    if (items == 0) return null;
    return (weighted / items).clamp(0.0, 1.0);
  }

  static double? _weightedRawCompletion(Iterable<AssessmentResult> results) {
    var completed = 0;
    var items = 0;
    for (final result in results) {
      if (result.totalItems <= 0) continue;
      completed += result.score.clamp(0, result.totalItems);
      items += result.totalItems;
    }
    if (items == 0) return null;
    return (completed / items).clamp(0.0, 1.0);
  }

  static double _mean(Iterable<double> values) {
    var total = 0.0;
    var count = 0;
    for (final value in values) {
      total += value;
      count++;
    }
    return count == 0 ? 0.0 : total / count;
  }

  static double? _meanNullable(Iterable<double?> values) {
    var total = 0.0;
    var count = 0;
    for (final value in values) {
      if (value == null) continue;
      total += value;
      count++;
    }
    return count == 0 ? null : total / count;
  }

  static String _number(double value) {
    final rounded = value.roundToDouble();
    return value == rounded
        ? rounded.toInt().toString()
        : value.toStringAsFixed(1);
  }
}
