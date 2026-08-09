import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';

import 'components/trace_guide_dot.dart';
import 'trace_glyphs.dart';
import '../shared/answer_label.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../shared/game_layout.dart';

/// The core Flame game for "Trace It".
///
/// Shows a large letter, number, or pre-writing stroke as a faded guide
/// path; the child traces it with a finger. A stroke completes when enough
/// of the guide path has been covered (coverage-based — direction and
/// neatness are not penalised, matching errorless-learning practice).
/// Tracks coverage, path deviation, and finger lifts for assessment.
class TraceItGame extends FlameGame
    with TapCallbacks, DragCallbacks, EnhancedGameplayAnalyticsMixin {
  TraceItGame({
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.totalRounds = 4,
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
  /// Immediate feedback on a finished glyph: the letter or numeral the child
  /// just traced, so the app can name it back ("A", "three"). Praise waits for
  /// the end of the game.
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
  /// Easy = pre-writing strokes, Medium = single-stroke letters/numbers,
  /// Hard = multi-stroke letters/numbers.
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
  int _dragOnPath = 0;
  int _dragOffPath = 0;

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

  static const Color _guideColor = Color(0xFFC9C4D4); // faded guide path
  static const Color _activeGuideColor = Color(0xFF9B82C4); // current stroke
  static const Color _doneColor = Color(0xFF43A047); // completed — true green
  static const Color _inkColor = Color(0xFF8E24AA); // crayon — true purple
  static const Color _startDotColor = Color(0xFF43A047);

  List<Vector2> get _currentPath =>
      _strokeIndex < _strokePaths.length ? _strokePaths[_strokeIndex] : const [];

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

    _strokePaths.clear();
    _ink.clear();
    _strokeIndex = 0;
    _covered = [];
    _dragging = false;
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
    _glyph = glyph;

    // Scale normalized strokes into the canvas and resample them evenly so
    // coverage checks are resolution-independent.
    final origin = _glyphOrigin;
    final side = _glyphSide;
    final spacing = side * 0.04;
    for (final stroke in glyph.strokes) {
      final scaled = stroke
          .map((p) => Vector2(origin.x + p.dx * side, origin.y + p.dy * side))
          .toList();
      _strokePaths.add(_resample(scaled, spacing));
    }
    _startStroke();

    _roundStartTime = DateTime.now();

    analyticsStartRound(roundNumber: _currentRound + 1);
    analyticsShowStimulus();
    analyticsAddRoundData('glyph', glyph.label);
    analyticsAddRoundData('stroke_count', glyph.strokes.length);

    _startNoResponseTimer();
  }

  void _startStroke() {
    _covered = List.filled(_currentPath.length, false);
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
    _dragOnPath = 0;
    _dragOffPath = 0;

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
    _dragPoint += event.localDelta;
    _ink.last.add(Offset(_dragPoint.x, _dragPoint.y));
    _absorbPoint(_dragPoint);

    if (_strokeCoverage() >= _coverageThreshold && _endpointsCovered()) {
      _dragging = false;
      _completeStroke();
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

  /// Feeds one drawn point into coverage + deviation tracking.
  void _absorbPoint(Vector2 point) {
    final path = _currentPath;
    if (path.isEmpty) return;

    final tolerance = _tolerance;
    var minDistance = double.infinity;
    for (var i = 0; i < path.length; i++) {
      final d = path[i].distanceTo(point);
      if (d < minDistance) minDistance = d;
      if (d <= tolerance) _covered[i] = true;
    }

    if (minDistance <= tolerance) {
      _dragOnPath++;
    } else {
      _dragOffPath++;
    }
    _deviationSum += (minDistance / tolerance).clamp(0.0, 3.0);
    _deviationSamples++;
  }

  double _strokeCoverage() {
    if (_covered.isEmpty) return 0;
    final hit = _covered.where((c) => c).length;
    return hit / _covered.length;
  }

  /// Both ends of the stroke must be reached, so a scribble across the
  /// middle can't complete it.
  bool _endpointsCovered() =>
      _covered.isNotEmpty && _covered.first && _covered.last;

  void _onFingerLifted() {
    if (_strokeIndex >= _strokePaths.length) return;
    _liftCount++;

    final samples = _dragOnPath + _dragOffPath;
    final offRatio = samples == 0 ? 0.0 : _dragOffPath / samples;

    if (samples >= 6 && offRatio > 0.55) {
      // Mostly off the path — a genuine wrong attempt, not a wobble.
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
      });
      analyticsRecordRetry();

      // Clear the stroke so the retry starts clean.
      _startStroke();

      if (_hintBudgetLeft && _errorsSinceLastCorrect >= 2) {
        _showTraceDemo(hintType: 'error_trace_demo');
      }
    }
    // Otherwise: a lift mid-trace — keep the partial progress silently.

    _startNoResponseTimer();
  }

  void _completeStroke() {
    _cancelNoResponseTimer();
    _errorsSinceLastCorrect = 0;

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
      onPlayGameCompleteSfx?.call();
      onPlayCelebrationVo?.call();

      analyticsMarkCompleted();
      analyticsCompleteSession();
      analyticsAddGameSpecificMetric('avg_trace_time_ms',
          _totalResponseTimeMs / (_score > 0 ? _score : 1));
      analyticsAddGameSpecificMetric('hint_count', _hintCount);
      analyticsAddGameSpecificMetric('glyphs_traced', _usedGlyphLabels.length);

      Future.delayed(const Duration(milliseconds: 600), () {
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
  /// 'circle' happens to be a shape the library already says — anything else
  /// resolves to nothing and the app stays quiet rather than inventing praise.
  AnswerLabel _glyphAnswerLabel() {
    final label = _glyph?.label;
    if (label == null) return AnswerLabel.none;
    if (label.length == 1) return AnswerLabel(letter: label);
    if (label.toLowerCase() == 'circle') return const AnswerLabel(shape: 'circle');
    return AnswerLabel.none;
  }
}
