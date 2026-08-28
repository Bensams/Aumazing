import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'components/trace_guide_dot.dart';
import 'trace_glyphs.dart';
import '../shared/answer_label.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../../config/round_policy.dart';
import '../shared/game_layout.dart';
import '../shared/game_lifecycle_guard.dart';

/// The core Flame game for "Trace It".
///
/// Shows a large letter, number, or pre-writing stroke as a faded guide
/// path; the child traces it with a finger. A stroke completes when the
/// trace satisfies the documented recognition policy (see the policy
/// section before the tolerance getters): the ink must cover the guide
/// AND stay near it within the tier tolerance — direction, neatness, and
/// finger lifts are not penalised, matching errorless-learning practice.
/// Tracks coverage, adherence, path deviation, and finger lifts for
/// assessment.
class TraceItGame extends FlameGame
    with GameLifecycleGuard, TapCallbacks, DragCallbacks, EnhancedGameplayAnalyticsMixin {
  TraceItGame({
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.totalRounds = GameRoundPolicy.standardRoundCount,
    this.gameVersion,
    this.profile = DifficultyProfile.medium,
    this.onCorrectTrace,
    this.onWrongAnswer,
    // Audio event callbacks (optional, wired by screen wrappers)
    this.onPlayCorrectSfx,
    this.onPlayWrongSfx,
    this.onPlayTapSfx,
    this.onPlayLevelCompleteSfx,
    this.onPlayGameCompleteSfx,
    this.onPlayCorrectVo,
    this.onPlayWrongVo,
    this.onPlayInstructionVo,
    this.onPlayTransitionVo,
    this.onPlayCelebrationVo,
  });

  final void Function(int currentStep) onStepChanged;
  final void Function({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    GameSessionMetrics? analytics,
  }) onGameComplete;

  /// Fired on each completed stroke (not just round completion).
  /// Used by the Flutter layer for haptic feedback.
  final void Function()? onCorrectTrace;

  /// Fired on each wrong attempt, alongside the wrong SFX and the encouraging
  /// voice line. The Flutter layer uses it for the mascot's reaction, so the
  /// character answers a mistake the same way the audio does.
  final void Function()? onWrongAnswer;

  // ── Audio event callbacks ────────────────────────────────────────────
  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayTapSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;
  /// Immediate feedback on a finished glyph: the letter, numeral, or shape the
  /// child just traced, so the app can name it back ("A", "three", "circle").
  /// Praise waits for the end of the game.
  final AnswerLabelCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;

  final int totalRounds;
  final String childId;
  final String? gameVersion;

  /// Hint/guidance policy for the selected difficulty tier (ABA prompt
  /// hierarchy — see [DifficultyProfile]). Also selects the glyph pool:
  /// Easy = simple pre-writing strokes/shapes, Medium = angular shapes and
  /// single-stroke letters/numbers, Hard = complex shapes and multi-stroke
  /// letters/numbers.
  final DifficultyProfile profile;

  // ── Game state ───────────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;
  DateTime? _roundStartTime;
  bool _firstInputRecorded = false;

  TraceGlyph? _glyph;
  final Set<String> _usedGlyphLabels = {};

  /// Resampled stroke paths in canvas coordinates.
  final List<List<Vector2>> _strokePaths = [];
  int _strokeIndex = 0;

  /// Coverage flags for the current stroke's target points.
  List<bool> _covered = [];

  /// The child's ink for the current stroke (one polyline per finger-down).
  final List<List<Offset>> _ink = [];

  bool _dragging = false;
  Vector2 _dragPoint = Vector2.zero();

  // Per-stroke-attempt recognition state (see the policy section below).
  // Metrics accumulate across finger lifts until the stroke completes or is
  // cleared for a retry, so a child pausing mid-trace is never counted as
  // a fresh mistake.
  int _inkSamples = 0;
  int _inkOnSamples = 0;
  bool _startReached = false;
  bool _endReached = false;
  List<double> _pathCumulativeLengths = const [];
  double _pathLength = 0;

  // Per-round quality stats (fed to analytics).
  int _liftCount = 0;
  double _deviationSum = 0;
  int _deviationSamples = 0;

  double _time = 0; // drives the start-dot pulse

  // ── Hint / idle timer state ──────────────────────────────────────────
  Timer? _noResponseTimer;
  int _hintCount = 0;
  int _hintsUsedThisRound = 0;
  int _errorsSinceLastCorrect = 0;
  TraceGuideDot? _guideDot;

  /// Within-round adaptive stepping: repeated struggle temporarily steps
  /// the tier down (wider tolerance, more hints) for the rest of the round.
  late final AdaptiveDifficulty _adaptive = AdaptiveDifficulty(profile);

  DifficultyProfile get _tier => _adaptive.effective;

  bool get _hintBudgetLeft =>
      _tier.unlimitedHints || _hintsUsedThisRound < (_tier.hintsPerRound ?? 0);

  // ── Recognition policy ───────────────────────────────────────────────
  //
  // The intended path is the resampled guide polyline of the current
  // stroke (points every 4% of the glyph side). The child's actual path is
  // the ink collected for that stroke — one attempt spans all finger downs
  // from `_startStroke` until the stroke completes or is cleared for a
  // retry. Every value below is the documented tolerance that the tests in
  // `test/trace_it_recognition_test.dart` assert:
  //
  //  * Tolerance radius `t` — how far ink may stray from the guide and
  //    still count as on it. Tier-scaled (11% of the glyph side on Easy,
  //    9% on Medium, 7.5% on Hard) so children with weaker motor control
  //    get a wider band; an adaptive step-down widens it for the rest of
  //    the round.
  //  * Guide coverage — fraction of guide points within `t` of some ink
  //    point: the intended path must be *covered* (path → ink).
  //  * Ink adherence — fraction of ink samples within `t` of the guide
  //    polyline: the drawn path must also *stay near* the intended path
  //    (ink → path). Without it a scribble that happens to cross the whole
  //    glyph passes coverage alone and is silently accepted. The bar is
  //    strict (90% on Medium/Hard) because shapes that ride the guide —
  //    a full circle over a C, an 8 over a 3 — keep 86–87% of their ink
  //    on it and must not slip through as correct; an honest trace keeps
  //    97%+.
  //  * End reach — the ink must approach both ends of the guide: an ink
  //    sample within `t` whose nearest point on the guide lies in the
  //    terminal 10% of the path's arc length. Children routinely stop
  //    short of the end dot or start just past the start dot, so the exact
  //    end points are not required; a trace cut across the middle is.
  //  * Completion — coverage, adherence, and end reach must all hold at
  //    the tier threshold. Evaluated at the finger lift: judging while
  //    the finger is still down would score only the ink drawn so far, so
  //    a circle over a C completes before its closing sweep. The short
  //    delay is imperceptible and keeps praise honest.
  //  * Wrong attempt — a lift that did not complete is a mistake worth
  //    retry-and-corrective-feedback exactly when the ink dwells outside
  //    tolerance (adherence below the bar): a wrong shape riding the guide
  //    is told to try again, not silently kept. A partial trace whose ink
  //    stays on tolerance keeps its progress and only the hint timers
  //    re-arm — young children pause mid-trace all the time, and an early
  //    stop is not punished while the ink is still in tolerance.
  //  * Direction is never penalised, and finger lifts never discard
  //    on-tolerance progress.
  //
  // ── Layout / tolerance ───────────────────────────────────────────────

  /// Side of the centered square the glyph is scaled into.
  double get _glyphSide => math.min(
        math.min(size.x * 0.55, size.y * 0.78),
        // Never taller than the space left below the overlay strip.
        (size.y - kTopOverlayBand) * 0.98,
      );

  Vector2 get _glyphOrigin => Vector2(
        (size.x - _glyphSide) / 2,
        kTopOverlayBand + (size.y - kTopOverlayBand - _glyphSide) / 2,
      );

  /// How far a finger may stray from the guide path and still count.
  /// Wider on easier tiers (and after an adaptive step-down).
  double get _tolerance {
    switch (_tier.level) {
      case 1:
        return _glyphSide * 0.11;
      case 3:
        return _glyphSide * 0.075;
      default:
        return _glyphSide * 0.09;
    }
  }

  /// Coverage of the guide path required to complete a stroke.
  double get _coverageThreshold {
    switch (_tier.level) {
      case 1:
        return 0.70;
      case 3:
        return 0.85;
      default:
        return 0.80;
    }
  }

  /// Ink adherence required to complete a stroke. Above the coverage bar,
  /// because sticking to a path is harder than covering it — and strict on
  /// Medium/Hard (90%) so shapes that ride the guide (86–87% adherence:
  /// a circle for a C, an 8 for a 3) are rejected while an honest trace
  /// (97%+) is accepted. Easy stays at 75% for unsteady motor control.
  double get _adherenceThreshold => _tier.level == 1 ? 0.75 : 0.90;

  /// How far along the path an end may be missed and still count as
  /// reached (fraction of the stroke's arc length). See the policy above.
  static const double _endAllowance = 0.10;

  static const Color _guideColor = Color(0xFFC9C4D4); // faded guide path
  static const Color _activeGuideColor = Color(0xFF9B82C4); // current stroke
  static const Color _doneColor = Color(0xFF43A047); // completed — true green
  static const Color _inkColor = Color(0xFF8E24AA); // crayon — true purple
  static const Color _startDotColor = Color(0xFF43A047);

  List<Vector2> get _currentPath =>
      _strokeIndex < _strokePaths.length ? _strokePaths[_strokeIndex] : const [];

  /// The resampled guide path the child is being asked to trace right now, in
  /// canvas coordinates. Test-only: it is the ground truth a coverage test has
  /// to drag along, and the glyph is picked at random.
  @visibleForTesting
  List<Vector2> get debugCurrentPath => List.unmodifiable(_currentPath);

  /// Test-only: whether the temporary purple trace is still being kept around.
  @visibleForTesting
  bool get debugHasInk => _ink.isNotEmpty;

  /// Test-only: reset the current round to a specific labelled glyph
  /// (letters, numbers, or pre-writing strokes from [TraceGlyphs]) so tests
  /// can exercise a deterministic intended path — the glyph is normally
  /// picked at random per round.
  @visibleForTesting
  void debugForceGlyph(String label) {
    final glyph = TraceGlyphs.forLevel(profile.level)
        .firstWhere((g) => g.label == label);
    _usedGlyphLabels.add(label);
    _applyGlyph(glyph);
  }

  /// Test-only: the current stroke's coverage of the guide (path → ink).
  @visibleForTesting
  double get debugGuideCoverage => _strokeCoverage();

  /// Test-only: the current attempt's ink adherence (ink → path).
  @visibleForTesting
  double get debugInkAdherence => _inkAdherence;

  /// Test-only: the per-tier tolerance radius in canvas units.
  @visibleForTesting
  double get debugTolerance => _tolerance;

  /// Test-only: the glyph box origin, for building offset/parallel paths.
  @visibleForTesting
  Vector2 get debugGlyphOrigin => _glyphOrigin;

  /// Test-only: the glyph box side, for building accurate test strokes.
  @visibleForTesting
  double get debugGlyphSide => _glyphSide;

  @override
  Color backgroundColor() => const Color(0x00000000); // Transparent

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    analyticsInitialize(
      gameId: 'trace_it',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion ?? '1.0.0',
    );
    analyticsStartSession();

    onPlayInstructionVo?.call();

    _setupRound();
  }

  void _setupRound() {
    _cancelNoResponseTimer();
    _removeGuideDot();

    _ink.clear();
    _firstInputRecorded = false;
    _liftCount = 0;
    _deviationSum = 0;
    _deviationSamples = 0;
    _hintsUsedThisRound = 0;
    _errorsSinceLastCorrect = 0;
    _adaptive.startRound(); // any step-down only lasts one round

    // Pick a glyph from the tier's pool, avoiding repeats until exhausted.
    final pool = TraceGlyphs.forLevel(profile.level);
    if (_usedGlyphLabels.length >= pool.length) _usedGlyphLabels.clear();
    final candidates =
        pool.where((g) => !_usedGlyphLabels.contains(g.label)).toList();
    final glyph = candidates[math.Random().nextInt(candidates.length)];
    _usedGlyphLabels.add(glyph.label);

    _applyGlyph(glyph);

    _roundStartTime = DateTime.now();

    analyticsStartRound(roundNumber: _currentRound + 1);
    analyticsShowStimulus();
    analyticsAddRoundData('glyph', glyph.label);
    analyticsAddRoundData('stroke_count', glyph.strokes.length);

    _startNoResponseTimer();
  }

  /// Scales [glyph]'s normalized strokes into the canvas and resamples them
  /// evenly so coverage checks are resolution-independent, then resets the
  /// attempt state to the glyph's first stroke.
  void _applyGlyph(TraceGlyph glyph) {
    _glyph = glyph;
    final origin = _glyphOrigin;
    final side = _glyphSide;
    final spacing = side * 0.04;
    _strokePaths.clear();
    for (final stroke in glyph.strokes) {
      final scaled = stroke
          .map((p) => Vector2(origin.x + p.dx * side, origin.y + p.dy * side))
          .toList();
      _strokePaths.add(_resample(scaled, spacing));
    }
    _strokeIndex = 0;
    _dragging = false;
    _startStroke();
  }

  void _startStroke() {
    _covered = List.filled(_currentPath.length, false);
    _clearInk();
    _inkSamples = 0;
    _inkOnSamples = 0;
    _startReached = false;
    _endReached = false;
    _buildPathLengths();
  }

  /// Cumulative arc length at each guide vertex and the stroke's total
  /// length — the ruler for the end-reach allowance in the policy above.
  void _buildPathLengths() {
    final path = _currentPath;
    _pathCumulativeLengths = List<double>.filled(path.length, 0);
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += path[i].distanceTo(path[i - 1]);
      _pathCumulativeLengths[i] = total;
    }
    _pathLength = total;
  }

  void _clearInk() {
    _ink.clear();
  }

  /// Resamples a polyline to points spaced ~[spacing] apart by arc length.
  static List<Vector2> _resample(List<Vector2> points, double spacing) {
    if (points.length < 2) return points;
    final out = <Vector2>[points.first.clone()];
    var carry = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final from = points[i];
      final to = points[i + 1];
      final segment = from.distanceTo(to);
      if (segment == 0) continue;
      var d = spacing - carry;
      while (d <= segment) {
        out.add(from + (to - from) * (d / segment));
        d += spacing;
      }
      carry = segment - (d - spacing);
    }
    if (out.last.distanceTo(points.last) > spacing * 0.25) {
      out.add(points.last.clone());
    }
    return out;
  }

  // ── Drag input ───────────────────────────────────────────────────────

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_dragging || _strokeIndex >= _strokePaths.length) return;
    _dragging = true;
    _dragPoint = event.canvasPosition.clone();

    _cancelNoResponseTimer();
    _removeGuideDot();

    if (!_firstInputRecorded) {
      analyticsRecordValidAction();
      _firstInputRecorded = true;
    }
    onPlayTapSfx?.call();

    _ink.add([Offset(_dragPoint.x, _dragPoint.y)]);
    _absorbPoint(_dragPoint);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (!_dragging) return;

    // The pointer's absolute position, not the running sum of its deltas.
    // `onDragStart` records `canvasPosition` while updates reported
    // `localDelta`, which are only the same space when nothing sits between
    // the game and the canvas — and any drift between them accumulates for as
    // long as the finger stays down, so the crayon line slid further from the
    // fingertip the longer a child traced.
    final previous = _dragPoint.clone();
    _dragPoint = event.canvasEndPosition.clone();
    _ink.last.add(Offset(_dragPoint.x, _dragPoint.y));

    // Flame reports one event per pointer sample, and a child sweeping quickly
    // leaves gaps between them far wider than the tolerance. Only the sampled
    // points used to count, so a fast, perfectly-aimed trace scored as a dotted
    // line — coverage never reached the threshold and the stroke would not
    // complete. Walk the segment instead, so what is measured is the line the
    // finger drew rather than where it happened to be polled.
    _absorbSegment(previous, _dragPoint);
    // Completion is evaluated at the finger lift (see the policy above):
    // judging mid-drag would score only the ink drawn so far.
  }

  /// Feeds the whole segment [from] → [to] into coverage tracking.
  ///
  /// Sampled at half the tolerance so no target point inside the segment's
  /// reach can be stepped over, and capped so a stray teleport (a second finger
  /// landing, say) cannot stall the frame.
  void _absorbSegment(Vector2 from, Vector2 to) {
    final distance = from.distanceTo(to);
    final step = _tolerance * 0.5;
    final steps = distance <= step ? 1 : math.min((distance / step).ceil(), 64);
    for (var i = 1; i <= steps; i++) {
      _absorbPoint(from + (to - from) * (i / steps));
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!_dragging) return;
    _dragging = false;
    _onFingerLifted();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (!_dragging) return;
    _dragging = false;
    _onFingerLifted();
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    analyticsRecordTouch(
      Offset(event.canvasPosition.x, event.canvasPosition.y),
      isValid: event.handled,
    );
  }

  /// Feeds one drawn point into guide coverage, ink adherence, end reach,
  /// and deviation tracking.
  void _absorbPoint(Vector2 point) {
    final path = _currentPath;
    if (path.isEmpty) return;

    final tolerance = _tolerance;

    // Guide coverage: mark guard points the ink passes within tolerance of.
    for (var i = 0; i < path.length; i++) {
      if (path[i].distanceTo(point) <= tolerance) _covered[i] = true;
    }

    // Ink adherence / end reach: the distance to the *polyline* the child
    // sees (not just its sampled vertices) and where along it the sample
    // lands.
    final projection = _nearestPathProjection(point);
    _inkSamples++;
    if (projection.distance <= tolerance) {
      _inkOnSamples++;
      if (projection.arcPosition <= _pathLength * _endAllowance) {
        _startReached = true;
      }
      if (projection.arcPosition >= _pathLength * (1 - _endAllowance)) {
        _endReached = true;
      }
    }
    _deviationSum += (projection.distance / tolerance).clamp(0.0, 3.0);
    _deviationSamples++;
  }

  double _strokeCoverage() {
    if (_covered.isEmpty) return 0;
    final hit = _covered.where((c) => c).length;
    return hit / _covered.length;
  }

  /// Fraction of ink samples within the tolerance of the guide polyline —
  /// the reverse of the coverage check: the drawn path must stay near the
  /// intended path, not merely cross it. See the policy above.
  double get _inkAdherence =>
      _inkSamples == 0 ? 0 : _inkOnSamples / _inkSamples;

  /// Whether the ink reached both ends of the guide within the end
  /// allowance, so a scribble across the middle can't complete the stroke
  /// — and a trace that stops short of the end dot still can.
  bool get _attemptEndsReached => _startReached && _endReached;

  /// The documented recognition policy for the current attempt: the guide
  /// is covered, the ink stays near it, and both ends were reached — each
  /// at the tier threshold/allowance.
  bool _attemptQualifies() =>
      _strokeCoverage() >= _coverageThreshold &&
      _inkAdherence >= _adherenceThreshold &&
      _attemptEndsReached;

  /// Nearest point on the guide polyline to [point], as its distance from
  /// the intended path and its position along it (arc length). Mapping
  /// every ink sample to exactly one `(distance, arcPosition)` pair is
  /// what makes adherence and end reach deterministic.
  ({double distance, double arcPosition}) _nearestPathProjection(
    Vector2 point,
  ) {
    final path = _currentPath;
    var bestDistance = double.infinity;
    var bestArcPosition = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i];
      final ab = path[i + 1] - a;
      final lengthSquared = ab.x * ab.x + ab.y * ab.y;
      final t = lengthSquared > 0
          ? (((point - a).x * ab.x + (point - a).y * ab.y) / lengthSquared)
              .clamp(0.0, 1.0)
              .toDouble()
          : 0.0;
      final projected = a + ab * t;
      final distance = projected.distanceTo(point);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestArcPosition = _pathCumulativeLengths[i] + t * ab.length;
      }
    }
    return (distance: bestDistance, arcPosition: bestArcPosition);
  }

  void _onFingerLifted() {
    if (_strokeIndex >= _strokePaths.length) return;
    _liftCount++;

    // A slow, careful trace can satisfy the policy exactly as the finger
    // leaves; finish it with praise rather than counting it as unfinished.
    if (_attemptQualifies()) {
      _completeStroke();
      return;
    }

    final offRatio =
        _inkSamples == 0 ? 0.0 : (_inkSamples - _inkOnSamples) / _inkSamples;

    if (_inkSamples >= 6 && _inkAdherence < _adherenceThreshold) {
      // The ink dwells outside the tolerance — a wrong shape riding the
      // guide, a scribble, or a stroke drawn far from the intended path:
      // a genuine wrong attempt, not a wobble. Give the retry feedback it
      // is due. A partial trace whose ink stays in tolerance keeps its
      // progress silently instead.
      _errorCount++;
      _errorsSinceLastCorrect++;
      if (_adaptive.recordError()) {
        analyticsAddRoundData('difficulty_step_down', _tier.level);
      }

      onPlayWrongSfx?.call();
      onPlayWrongVo?.call();
      onWrongAnswer?.call();
      analyticsRecordWrong(extraData: {
        'glyph': _glyph?.label,
        'stroke_index': _strokeIndex,
        'off_path_ratio': offRatio,
        'coverage': _strokeCoverage(),
        'adherence': _inkAdherence,
      });
      analyticsRecordRetry();

      // Clear the stroke so the retry starts clean.
      _startStroke();

      if (_hintBudgetLeft && _errorsSinceLastCorrect >= 2) {
        _showTraceDemo(hintType: 'error_trace_demo');
      }
    }
    // Other lifts keep their progress silently — the ink is still within
    // tolerance.

    _startNoResponseTimer();
  }

  void _completeStroke() {
    _cancelNoResponseTimer();
    _errorsSinceLastCorrect = 0;
    _clearInk();

    onPlayCorrectSfx?.call();
    onCorrectTrace?.call();

    _strokeIndex++;
    if (_strokeIndex < _strokePaths.length) {
      _startStroke();
      _startNoResponseTimer();
      return;
    }

    // ── Glyph finished: round complete ────────────────────────────────
    final responseTime = _roundStartTime != null
        ? DateTime.now().difference(_roundStartTime!).inMilliseconds
        : 0;
    _score++;
    _totalResponseTimeMs += responseTime;
    _adaptive.recordCorrect();

    final avgDeviation =
        _deviationSamples == 0 ? 0.0 : _deviationSum / _deviationSamples;
    analyticsRecordCorrect(extraData: {
      'glyph': _glyph?.label,
      'response_time_ms': responseTime,
      'finger_lifts': _liftCount,
      'avg_deviation_ratio': avgDeviation,
    });
    onPlayCorrectVo?.call(_glyphAnswerLabel());

    analyticsCompleteRound(successful: true);

    _currentRound++;
    onStepChanged(_currentRound);

    if (_currentRound >= totalRounds) {
      if (!tryBeginCompletion()) return;
      onPlayGameCompleteSfx?.call();
      onPlayCelebrationVo?.call();

      analyticsMarkCompleted();
      analyticsCompleteSession();
      analyticsAddGameSpecificMetric('avg_trace_time_ms',
          _totalResponseTimeMs / (_score > 0 ? _score : 1));
      analyticsAddGameSpecificMetric('hint_count', _hintCount);
      analyticsAddGameSpecificMetric('glyphs_traced', _usedGlyphLabels.length);

      guardedDelay(const Duration(milliseconds: 600), () {
        onGameComplete(
          score: _score,
          totalItems: totalRounds,
          errorCount: _errorCount,
          totalResponseTimeMs: _totalResponseTimeMs,
          analytics: analyticsSession,
        );
      });
    } else {
      onPlayLevelCompleteSfx?.call();
      onPlayTransitionVo?.call();
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!isMounted) return;
        _setupRound();
      });
    }
  }

  // ── Hint / idle timer methods ────────────────────────────────────────

  void _startNoResponseTimer() {
    _cancelNoResponseTimer();
    final delay = (_tier.noHints || !_hintBudgetLeft)
        ? _tier.reorientDelay
        : _tier.idleHintDelay;
    _noResponseTimer = Timer(delay, () {
      if (!isMounted) return;
      _showIdleHint();
    });
  }

  void _cancelNoResponseTimer() {
    _noResponseTimer?.cancel();
    _noResponseTimer = null;
  }

  void _showIdleHint() {
    if (_strokeIndex >= _strokePaths.length) return;

    // No answer hints available (Hard, or a spent Medium budget): re-play
    // the instruction to re-orient attention, never reveal the trace.
    if (_tier.noHints || !_hintBudgetLeft) {
      onPlayInstructionVo?.call();
      analyticsRecordHint(hintType: 'reorient_instruction');
      _startNoResponseTimer();
      return;
    }

    _showTraceDemo(hintType: 'idle_trace_demo');
    _startNoResponseTimer();
  }

  /// The ghost finger travels the current stroke, showing how to trace it.
  void _showTraceDemo({required String hintType}) {
    final path = _currentPath;
    if (path.length < 2) return;

    _removeGuideDot();
    final dot = TraceGuideDot(
      path: path,
      handSize: _glyphSide * 0.22,
      speed: _glyphSide * 0.55,
    );
    _guideDot = dot;
    add(dot);

    _hintCount++;
    _hintsUsedThisRound++;
    analyticsRecordHint(hintType: hintType);
  }

  void _removeGuideDot() {
    if (_guideDot?.isMounted ?? false) _guideDot?.removeFromParent();
    _guideDot = null;
  }

  // ── Rendering ────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    final side = _glyphSide;

    Paint strokePaint(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawPath(List<Vector2> points, Paint paint) {
      if (points.length < 2) return;
      final path = Path()..moveTo(points.first.x, points.first.y);
      for (final p in points.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      canvas.drawPath(path, paint);
    }

    final guideWidth = side * 0.085;

    // Not-yet-traced strokes: faded guide.
    for (var i = _strokeIndex; i < _strokePaths.length; i++) {
      drawPath(_strokePaths[i], strokePaint(_guideColor, guideWidth));
    }
    // Current stroke: highlighted guide on top of the faded one.
    if (_strokeIndex < _strokePaths.length) {
      drawPath(
        _strokePaths[_strokeIndex],
        strokePaint(_activeGuideColor.withAlpha(90), guideWidth),
      );
    }
    // Completed strokes: solid success color.
    for (var i = 0; i < _strokeIndex && i < _strokePaths.length; i++) {
      drawPath(_strokePaths[i], strokePaint(_doneColor, guideWidth));
    }

    // The child's ink for the current stroke.
    for (final line in _ink) {
      if (line.length < 2) continue;
      final path = Path()..moveTo(line.first.dx, line.first.dy);
      for (final p in line.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, strokePaint(_inkColor, guideWidth * 0.6));
    }

    // Pulsing start dot + end dot for the current stroke.
    final current = _currentPath;
    if (current.length >= 2) {
      final pulse = 1.0 + 0.18 * math.sin(_time * 4);
      canvas.drawCircle(
        Offset(current.first.x, current.first.y),
        side * 0.045 * pulse,
        Paint()..color = _startDotColor,
      );
      canvas.drawCircle(
        Offset(current.last.x, current.last.y),
        side * 0.03,
        Paint()..color = _activeGuideColor,
      );
    }

    super.render(canvas);
  }

  @override
  void onRemove() {
    _cancelNoResponseTimer();
    super.onRemove();
  }

  /// What to say back for the glyph just traced.
  ///
  /// The glyph table mixes single characters ('A', '3') with named strokes
  /// ('circle', 'line across'). Only the first kind has a recorded name, and
  /// Pre-writing lines intentionally stay silent because they have no matching
  /// naming cue. Geometric shapes use the same naming feedback as the shape
  /// games, while letters and numerals keep their existing glyph cues.
  AnswerLabel _glyphAnswerLabel() {
    final label = _glyph?.label;
    if (label == null) return AnswerLabel.none;
    if (label.length == 1) return AnswerLabel(letter: label);
    final normalized = label.toLowerCase();
    const spokenShapes = {
      'circle',
      'square',
      'triangle',
      'star',
      'heart',
      'diamond',
    };
    if (spokenShapes.contains(normalized)) {
      return AnswerLabel(shape: normalized);
    }
    return AnswerLabel.none;
  }
}
