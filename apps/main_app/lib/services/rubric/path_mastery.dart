import 'dart:math' as math;

import '../../model/gameplay_session.dart';
import 'rubric_labels.dart';
import 'rubric_scoring_service.dart';
import 'rubric_threshold_service.dart';
import 'rubric_thresholds.dart';

/// Decides whether ONE play of a learning-path game reached "Strength".
///
/// A step on My Path only unlocks the next step once the child earns a
/// Strength on it; anything below that asks the child to play the step
/// again. The label uses the same rubric vocabulary and the same
/// admin-configurable cutoffs as the assessment, so "Strength" means the
/// same thing on the path as it does in the parent's Skills Snapshot:
///
/// * the four rubric games are scored by their own area rule
///   ([RubricScoringService]) over this single session — `copy_me`, which
///   feeds two areas, must be a Strength in both;
/// * every other game uses the general rule: accuracy and completion both at
///   or above the Strength cutoffs (Emerging when either reaches the
///   Emerging cutoff).
///
/// A session with no items cannot demonstrate anything and is never a
/// Strength.
class PathMastery {
  const PathMastery({this.thresholds});

  /// Explicit cutoffs; null = the live admin-configured values.
  final RubricThresholds? thresholds;

  RubricThresholds get _t =>
      thresholds ?? RubricThresholdService.instance.current;

  /// The rubric label this single play earned.
  PerformanceLabel labelFor(GameplaySession session) {
    if (session.totalItems <= 0) return PerformanceLabel.needsSupport;
    final scorer = RubricScoringService(thresholds: _t);
    final one = [_withoutInstructionPrompts(session)];
    switch (session.gameId) {
      case 'match_it':
        return scorer.scorePlaySkills(one);
      case 'do_what_i_say':
        return scorer.scoreCommunication(one);
      case 'my_turn_your_turn':
        return scorer.scoreSocialInteraction(one);
      case 'copy_me':
        return _weaker(
          scorer.scorePlaySkills(one),
          scorer.scoreCommunication(one),
        );
      default:
        return _general(session);
    }
  }

  /// Whether this single play reached Strength.
  bool isStrength(GameplaySession session) =>
      labelFor(session) == PerformanceLabel.strength;

  PerformanceLabel _general(GameplaySession s) {
    final accuracy = (s.score / math.max(s.totalItems, 1)).clamp(0.0, 1.0);
    final completion = s.taskCompletionRate ?? accuracy;
    if (accuracy >= _t.strengthAccuracy &&
        completion >= _t.strengthCompletion) {
      return PerformanceLabel.strength;
    }
    if (accuracy >= _t.emergingAccuracy ||
        completion >= _t.emergingCompletion) {
      return PerformanceLabel.emerging;
    }
    return PerformanceLabel.needsSupport;
  }

  /// Games that log their own round instruction as a prompt: `copy_me` logs
  /// the sequence demonstration and `do_what_i_say` logs the spoken "Tap
  /// the red circle" once per round. That instruction IS the task, not help
  /// the child needed, but it lands in `promptCount` all the same — so a
  /// flawless play reads as a prompt dependency of 1.0, far above the
  /// Strength ceiling, and the path step could never unlock.
  static const _instructionPromptGames = {'copy_me', 'do_what_i_say'};

  /// The session as the rubric should see it on the path: for the games
  /// above, one instruction prompt per item is taken off before prompt
  /// dependency is worked out. Real assistance (idle voice repeats, visual
  /// guides, repeats after errors) is still counted. A session that already
  /// carries an explicit [GameplaySession.promptDependencyScore] is trusted
  /// as-is.
  ///
  /// Only the fields the play-skills and communication rules read are
  /// carried over.
  static GameplaySession _withoutInstructionPrompts(GameplaySession s) {
    if (!_instructionPromptGames.contains(s.gameId) ||
        s.promptDependencyScore != null) {
      return s;
    }
    final assistance = math.max(s.promptCount - s.totalItems, 0);
    return GameplaySession(
      id: s.id,
      childId: s.childId,
      gameId: s.gameId,
      context: s.context,
      score: s.score,
      totalItems: s.totalItems,
      errorCount: s.errorCount,
      totalResponseTimeMs: s.totalResponseTimeMs,
      retryCount: s.retryCount,
      hintCount: s.hintCount,
      promptCount: assistance,
      taskCompletionRate: s.taskCompletionRate,
      promptDependencyScore: assistance / s.totalItems,
      startedAt: s.startedAt,
      endedAt: s.endedAt,
    );
  }

  static PerformanceLabel _weaker(PerformanceLabel a, PerformanceLabel b) =>
      a.index >= b.index ? a : b;
}

/// How a child is getting on with one game of their learning path: every
/// path play counts as an attempt, and the attempt that first earned a
/// Strength is kept so the parent can see how many tries it took.
class PathAttemptRecord {
  const PathAttemptRecord({
    required this.gameId,
    required this.attempts,
    required this.lastLabel,
    this.attemptsToStrength,
    this.strengthAt,
  });

  final String gameId;

  /// Every path play of this game, including replays after the Strength.
  final int attempts;

  /// The label of the most recent play ('Strength' / 'Emerging' /
  /// 'Needs Support').
  final String lastLabel;

  /// The attempt number that first earned a Strength; null until it has.
  final int? attemptsToStrength;

  /// When that Strength was earned.
  final DateTime? strengthAt;

  bool get reachedStrength => attemptsToStrength != null;

  /// Retries it took to reach Strength (attempts after the first), or the
  /// retries so far while the step is still locked.
  int get retries => math.max((attemptsToStrength ?? attempts) - 1, 0);

  /// Records one more play with [label].
  PathAttemptRecord next(PerformanceLabel label, DateTime at) {
    final attempt = attempts + 1;
    final firstStrength =
        attemptsToStrength == null && label == PerformanceLabel.strength;
    return PathAttemptRecord(
      gameId: gameId,
      attempts: attempt,
      lastLabel: label.displayName,
      attemptsToStrength: firstStrength ? attempt : attemptsToStrength,
      strengthAt: firstStrength ? at : strengthAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'game_id': gameId,
    'attempts': attempts,
    'last_label': lastLabel,
    'attempts_to_strength': attemptsToStrength,
    'strength_at': strengthAt?.toIso8601String(),
  };

  factory PathAttemptRecord.fromMap(Map<String, dynamic> map) =>
      PathAttemptRecord(
        gameId: map['game_id'] as String,
        attempts: (map['attempts'] as num?)?.toInt() ?? 0,
        lastLabel: map['last_label'] as String? ?? '',
        attemptsToStrength: (map['attempts_to_strength'] as num?)?.toInt(),
        strengthAt:
            map['strength_at'] == null
                ? null
                : DateTime.tryParse(map['strength_at'] as String),
      );
}
