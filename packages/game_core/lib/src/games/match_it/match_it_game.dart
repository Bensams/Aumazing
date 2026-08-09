import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';

import 'components/matchable_shape.dart';
import '../shared/answer_label.dart';
import '../shared/ghost_hand.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../shared/game_layout.dart';

/// Data for a single match pair used in the Match It game.
class MatchPairData {
  final ShapeType shape;
  final Color color;
  final String label;

  const MatchPairData({
    required this.shape,
    required this.color,
    required this.label,
  });

  /// The colour word from [label] — every label reads "<Colour> <Shape>".
  String get colorName => label.split(' ').first;

  /// The shape word, taken from [shape] rather than [label] so it always
  /// matches the key the voice-over and painter use.
  String get shapeName => shape.name;

  /// What to say back when this pair is matched: "gold star".
  AnswerLabel get answerLabel =>
      AnswerLabel(color: colorName, shape: shapeName);
}

/// The core Flame game for "Match It".
///
/// Presents two columns of shapes — the child taps one on the left,
/// then one on the right. If they match, it advances the step.
/// Tracks score, errors, and response times for assessment.
/// The core Flame game for "Match It" with XGBoost-ready analytics.
///
/// Presents two columns of shapes — the child taps one on the left,
/// then one on the right. If they match, it advances the step.
/// Tracks comprehensive gameplay analytics for ML analysis.
class MatchItGame extends FlameGame
    with TapCallbacks, DragCallbacks, EnhancedGameplayAnalyticsMixin {
  MatchItGame({
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.totalRounds = 5,
    this.gameVersion,
    this.profile = DifficultyProfile.medium,
    this.onCorrectMatch,
    this.onWrongAnswer,
    // Audio event callbacks (optional, wired by screen wrappers)
    this.onPlayCorrectSfx,
    this.onPlayWrongSfx,
    this.onPlayTapSfx,
    this.onPlayDragSfx,
    this.onPlayDropSfx,
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

  /// Optional callback fired on each individual correct match (not just round completion).
  /// Used by the Flutter layer to trigger haptic feedback during pre-assessment.
  final void Function()? onCorrectMatch;

  /// Optional callback fired on each wrong answer, alongside the wrong SFX and
  /// the encouraging voice line. The Flutter layer uses it for the mascot's
  /// reaction, so the character answers a mistake the same way the audio does.
  final void Function()? onWrongAnswer;

  // ── Audio event callbacks ────────────────────────────────────────────
  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayTapSfx;
  final VoidCallback? onPlayDragSfx;
  final VoidCallback? onPlayDropSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;

  /// Immediate feedback on a correct match: the pair that was matched, so the
  /// app can name it back ("gold star"). Praise is deliberately not played
  /// here — it belongs to [onPlayCelebrationVo] at the end of the game.
  final AnswerLabelCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;

  final int totalRounds;
  final String childId;
  final String? gameVersion;

  /// Hint/guidance policy for the selected difficulty tier (ABA prompt
  /// hierarchy — see [DifficultyProfile]).
  final DifficultyProfile profile;

  // ── Game state ───────────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;
  DateTime? _roundStartTime;

  int? _selectedLeftIndex;
  int? _selectedRightIndex;
  bool _firstInputRecorded = false;

  // ── Hint / idle timer state ──────────────────────────────────────────
  Timer? _noResponseTimer;
  int _hintCount = 0;

  // Difficulty-tier hint state (see DifficultyProfile).
  int _hintsUsedThisRound = 0;
  int _consecutiveIdleHints = 0;
  int _errorsSinceLastCorrect = 0;
  GhostHand? _ghostHand;

  /// Within-round adaptive stepping: 2 consecutive errors temporarily step
  /// the tier down (more support) for the remainder of the round.
  late final AdaptiveDifficulty _adaptive = AdaptiveDifficulty(profile);

  /// The tier in effect right now (base, or one step easier after struggles).
  DifficultyProfile get _tier => _adaptive.effective;

  bool get _hintBudgetLeft =>
      _tier.unlimitedHints || _hintsUsedThisRound < (_tier.hintsPerRound ?? 0);

  final List<MatchableShape> _leftShapes = [];
  final List<MatchableShape> _rightShapes = [];

  /// This round's three pairs, indexed by [MatchableShape.index], so a matched
  /// shape can be traced back to the words that name it.
  final List<MatchPairData> _roundPairs = [];

  /// Tracks indices of pairs already used in previous rounds to reduce
  /// repetition. Resets when the pool is exhausted.
  final Set<int> _usedPairIndices = {};

  // True, natural colors (not pastel tints) so the color a child matches
  // here is the same color they'll name and see in the real world.
  static const List<MatchPairData> _allPairs = [
    // Stars — 3 colour variants
    MatchPairData(
        shape: ShapeType.star, color: Color(0xFFFFB300), label: 'Gold Star'),
    MatchPairData(
        shape: ShapeType.star, color: Color(0xFFFB8C00), label: 'Orange Star'),
    MatchPairData(
        shape: ShapeType.star, color: Color(0xFFE53935), label: 'Red Star'),
    // Hearts — 3 colour variants
    MatchPairData(
        shape: ShapeType.heart, color: Color(0xFFE53935), label: 'Red Heart'),
    MatchPairData(
        shape: ShapeType.heart,
        color: Color(0xFF8E24AA),
        label: 'Purple Heart'),
    MatchPairData(
        shape: ShapeType.heart,
        color: Color(0xFFEC407A),
        label: 'Pink Heart'),
    // Circles — 3 colour variants
    MatchPairData(
        shape: ShapeType.circle,
        color: Color(0xFF43A047),
        label: 'Green Circle'),
    MatchPairData(
        shape: ShapeType.circle,
        color: Color(0xFF1E88E5),
        label: 'Blue Circle'),
    MatchPairData(
        shape: ShapeType.circle,
        color: Color(0xFFFB8C00),
        label: 'Orange Circle'),
    // Diamonds — 3 colour variants
    MatchPairData(
        shape: ShapeType.diamond,
        color: Color(0xFF1E88E5),
        label: 'Blue Diamond'),
    MatchPairData(
        shape: ShapeType.diamond,
        color: Color(0xFF43A047),
        label: 'Green Diamond'),
    MatchPairData(
        shape: ShapeType.diamond,
        color: Color(0xFFD500F9),
        label: 'Magenta Diamond'),
    // Triangles — 3 colour variants
    MatchPairData(
        shape: ShapeType.triangle,
        color: Color(0xFF8E24AA),
        label: 'Purple Triangle'),
    MatchPairData(
        shape: ShapeType.triangle,
        color: Color(0xFF00ACC1),
        label: 'Teal Triangle'),
    MatchPairData(
        shape: ShapeType.triangle,
        color: Color(0xFFFDD835),
        label: 'Yellow Triangle'),
  ];

  @override
  Color backgroundColor() => const Color(0x00000000); // Transparent

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Initialize and start analytics session
    analyticsInitialize(
      gameId: 'match_it',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion ?? '1.0.0',
    );
    analyticsStartSession();

    // Play instruction voice-over when game loads
    onPlayInstructionVo?.call();

    _setupRound();
  }

  void _setupRound() {
    // Cancel any existing timer from previous round
    _cancelNoResponseTimer();

    // Clear previous shapes
    for (final s in _leftShapes) {
      s.removeFromParent();
    }
    for (final s in _rightShapes) {
      s.removeFromParent();
    }
    _leftShapes.clear();
    _rightShapes.clear();
    _selectedLeftIndex = null;
    _selectedRightIndex = null;
    _firstInputRecorded = false;

    // Reset hint count per round
    _hintCount = 0;
    _hintsUsedThisRound = 0;
    _consecutiveIdleHints = 0;
    _errorsSinceLastCorrect = 0;
    _adaptive.startRound(); // any step-down only lasts one round

    final rng = math.Random();

    // Reset used-pair tracking when the pool is nearly exhausted.
    if (_usedPairIndices.length > _allPairs.length - 3) {
      _usedPairIndices.clear();
    }

    // Build a list of available (not-yet-used) pairs, shuffled.
    final available = <int>[];
    for (var i = 0; i < _allPairs.length; i++) {
      if (!_usedPairIndices.contains(i)) available.add(i);
    }
    available.shuffle(rng);

    // Pick 3 pairs with DISTINCT shape types so children can match by shape.
    final roundPairs = <MatchPairData>[];
    final roundIndices = <int>[];
    final usedShapes = <ShapeType>{};

    for (final idx in available) {
      final p = _allPairs[idx];
      if (usedShapes.contains(p.shape)) continue;
      usedShapes.add(p.shape);
      roundPairs.add(p);
      roundIndices.add(idx);
      if (roundPairs.length == 3) break;
    }

    // Fallback: if we still have < 3 (shouldn't happen with 15 pairs),
    // allow duplicates from the full pool.
    if (roundPairs.length < 3) {
      final fallback = List<int>.generate(_allPairs.length, (i) => i)
        ..shuffle(rng);
      for (final idx in fallback) {
        if (roundIndices.contains(idx)) continue;
        roundPairs.add(_allPairs[idx]);
        roundIndices.add(idx);
        if (roundPairs.length == 3) break;
      }
    }

    // Record these pairs as used for cross-round dedup.
    _usedPairIndices.addAll(roundIndices);

    _roundPairs
      ..clear()
      ..addAll(roundPairs);

    // Create a shuffled order for right column
    final rightOrder = List<int>.generate(3, (i) => i)..shuffle(rng);

    // Responsive layout constants
    final gameW = size.x;
    final gameH = size.y;
    // Lay out below the app's top overlay strip. Cards keep their full size
    // whenever the remaining height allows it — they simply sit lower — and
    // only shrink if the band genuinely leaves no room.
    final availH = gameH - kTopOverlayBand;
    var cardSize = math.min(gameW / 5.0, gameH / 4.5);
    if (3.3 * cardSize > availH) cardSize = availH / 3.3;
    final cardGap = cardSize * 0.15;
    final totalHeight = 3 * cardSize + 2 * cardGap;
    final startY = kTopOverlayBand + (availH - totalHeight) / 2;
    final leftX = gameW * 0.18;
    final rightX = gameW * 0.82 - cardSize;

    for (var i = 0; i < 3; i++) {
      final y = startY + i * (cardSize + cardGap);

      final leftShape = MatchableShape(
        shapeType: roundPairs[i].shape,
        shapeColor: roundPairs[i].color,
        index: i,
        onSelected: _onLeftSelected,
        onDragDropped: _onShapeDragged,
        position: Vector2(leftX, y),
        size: Vector2.all(cardSize),
      );

      final ri = rightOrder[i];
      final rightShape = MatchableShape(
        shapeType: roundPairs[ri].shape,
        shapeColor: roundPairs[ri].color,
        index: ri,
        onSelected: _onRightSelected,
        onDragDropped: _onShapeDragged,
        position: Vector2(rightX, y),
        size: Vector2.all(cardSize),
      );

      _leftShapes.add(leftShape);
      _rightShapes.add(rightShape);
      add(leftShape);
      add(rightShape);
    }

    _roundStartTime = DateTime.now();

    // Start round and show stimulus
    analyticsStartRound(roundNumber: _currentRound + 1);
    analyticsShowStimulus();

    // Add round-specific data
    analyticsAddRoundData('round_pairs_count', 3);
    analyticsAddRoundData('shapes_available', _allPairs.length);

    // Start idle timer for this round
    _startNoResponseTimer();
  }

  void _onLeftSelected(int index) {
    _cancelNoResponseTimer();
    _hideVisualHints();
    _consecutiveIdleHints = 0; // child re-engaged

    // Deselect previous
    for (final s in _leftShapes) {
      if (s.isSelected) s.deselect();
    }
    _selectedLeftIndex = index;
    _leftShapes[index].select();
    onPlayTapSfx?.call();
    _checkMatch();

    // Restart timer after selection (if match wasn't triggered)
    if (_selectedLeftIndex != null || _selectedRightIndex != null) {
      _startNoResponseTimer();
    }
  }

  void _onRightSelected(int index) {
    _cancelNoResponseTimer();
    _hideVisualHints();
    _consecutiveIdleHints = 0; // child re-engaged

    // Deselect previous
    for (final s in _rightShapes) {
      if (s.isSelected) s.deselect();
    }
    _selectedRightIndex = index;
    for (final s in _rightShapes) {
      if (s.index == index) s.select();
    }
    onPlayTapSfx?.call();
    _checkMatch();

    // Restart timer after selection (if match wasn't triggered)
    if (_selectedLeftIndex != null || _selectedRightIndex != null) {
      _startNoResponseTimer();
    }
  }

  /// Drag input: [shape] was dropped at [dropCenter]. If it lands on a
  /// non-matched shape in the opposite column, resolve it as a match attempt
  /// using the same logic as tap.
  void _onShapeDragged(MatchableShape shape, Vector2 dropCenter) {
    if (shape.isMatched) return;
    _cancelNoResponseTimer();
    _hideVisualHints();
    _consecutiveIdleHints = 0; // child re-engaged

    final isLeft = _leftShapes.contains(shape);
    final opposite = isLeft ? _rightShapes : _leftShapes;

    MatchableShape? target;
    for (final s in opposite) {
      if (!s.isMatched && s.containsPoint(dropCenter)) {
        target = s;
        break;
      }
    }
    if (target == null) {
      // Dropped on empty space — no match attempt; resume the idle timer.
      _startNoResponseTimer();
      return;
    }

    final leftShape = isLeft ? shape : target;
    final rightShape = isLeft ? target : shape;
    _selectedLeftIndex = leftShape.index;
    _selectedRightIndex = rightShape.index;
    onPlayDropSfx?.call();
    _checkMatch();
  }

  void _checkMatch() {
    if (_selectedLeftIndex == null || _selectedRightIndex == null) return;

    // Record first touch and valid action
    if (!_firstInputRecorded) {
      analyticsRecordValidAction();
      _firstInputRecorded = true;
    }

    final responseTime = _roundStartTime != null
        ? DateTime.now().difference(_roundStartTime!).inMilliseconds
        : 0;

    // Match by shape identity (shape type + color), not by index
    final leftShape = _leftShapes[_selectedLeftIndex!];
    MatchableShape? rightShape;
    for (final s in _rightShapes) {
      if (s.index == _selectedRightIndex) {
        rightShape = s;
        break;
      }
    }

    if (rightShape == null) return;

    final isMatch = leftShape.shapeType == rightShape.shapeType &&
        leftShape.shapeColor.value == rightShape.shapeColor.value;

    if (isMatch) {
      // Correct match!
      _score++;
      _totalResponseTimeMs += responseTime;
      _adaptive.recordCorrect();
      _consecutiveIdleHints = 0;
      _errorsSinceLastCorrect = 0;

      // Record correct response with details
      analyticsRecordCorrect(extraData: {
        'left_shape': leftShape.shapeType.name,
        'right_shape': rightShape.shapeType.name,
        'response_time_ms': responseTime,
      });

      // Notify Flutter layer of individual correct match (for haptic feedback)
      onCorrectMatch?.call();

      // Play correct SFX, then name the pair the child just matched.
      onPlayCorrectSfx?.call();
      onPlayCorrectVo?.call(leftShape.index < _roundPairs.length
          ? _roundPairs[leftShape.index].answerLabel
          : AnswerLabel.none);

      leftShape.markMatched();
      rightShape.markMatched();

      _selectedLeftIndex = null;
      _selectedRightIndex = null;

      // Check if all 3 pairs matched in this round
      final allMatched = _leftShapes.every((s) => s.isMatched);
      if (allMatched) {
        // Round complete — cancel timer
        _cancelNoResponseTimer();

        analyticsCompleteRound(successful: true);
        analyticsAddRoundData('matches_in_round', 3);

        _currentRound++;
        onStepChanged(_currentRound);

        if (_currentRound >= totalRounds) {
          // Game complete — cancel timer and play game complete SFX and celebration VO
          _cancelNoResponseTimer();
          onPlayGameCompleteSfx?.call();
          onPlayCelebrationVo?.call();

          analyticsMarkCompleted();
          analyticsCompleteSession();

          // Add game-specific metrics
          analyticsAddGameSpecificMetric('avg_match_time_ms',
            _totalResponseTimeMs / (_score > 0 ? _score : 1));
          analyticsAddGameSpecificMetric('shape_types_used',
            _usedPairIndices.length);
          analyticsAddGameSpecificMetric('hint_count', _hintCount);

          Future.delayed(const Duration(milliseconds: 600), () {
            onGameComplete(
              score: _score,
              totalItems: totalRounds * 3,
              errorCount: _errorCount,
              totalResponseTimeMs: _totalResponseTimeMs,
              analytics: analyticsSession,
            );
          });
        } else {
          // Level/round complete — play level complete SFX and transition VO
          onPlayLevelCompleteSfx?.call();
          onPlayTransitionVo?.call();

          // Next round after a brief pause
          Future.delayed(const Duration(milliseconds: 800), _setupRound);
        }
      } else {
        // Partial match - continue round, restart timer for next pair
        _roundStartTime = DateTime.now();
        _firstInputRecorded = false;
        analyticsShowStimulus();
        _startNoResponseTimer();
      }
    } else {
      // Wrong match
      _errorCount++;
      _errorsSinceLastCorrect++;

      // Adaptive stepping: repeated struggle steps the tier down (more
      // support) for the rest of this round.
      if (_adaptive.recordError()) {
        analyticsAddRoundData('difficulty_step_down', _tier.level);
      }

      // Play wrong SFX and voice-over
      onPlayWrongSfx?.call();
      onPlayWrongVo?.call();
      onWrongAnswer?.call();

      // Record wrong response with details
      analyticsRecordWrong(extraData: {
        'left_shape': leftShape.shapeType.name,
        'right_shape': rightShape.shapeType.name,
        'color_mismatch': leftShape.shapeColor.value != rightShape.shapeColor.value,
        'shape_mismatch': leftShape.shapeType != rightShape.shapeType,
      });

      // Record retry
      analyticsRecordRetry();

      leftShape.showError();
      rightShape.showError();

      // Remember the left index before clearing selection
      final hintLeftIndex = _selectedLeftIndex!;

      Future.delayed(const Duration(milliseconds: 500), () {
        if (!isMounted) return;
        _selectedLeftIndex = null;
        _selectedRightIndex = null;
        _roundStartTime = DateTime.now();
        _firstInputRecorded = false;
        analyticsShowStimulus();

        // Answer hint only when the tier's budget allows it (Easy: always;
        // Medium: while budget lasts; Hard: never).
        if (_hintBudgetLeft) {
          _showMatchHint(hintLeftIndex);
          // Easy tier: repeated errors escalate to the tap demo showing the
          // pair to tap (left shape, then its right match).
          if (_tier.guidedDemo && _errorsSinceLastCorrect >= 2) {
            _showTapDemo(hintLeftIndex);
          }
        }

        // Auto-hide hints after 3 seconds and restart timer
        Future.delayed(const Duration(seconds: 3), () {
          if (!isMounted) return;
          _hideVisualHints();
          _startNoResponseTimer();
        });
      });
    }
  }

  // ── Hint / idle timer methods ────────────────────────────────────────

  void _startNoResponseTimer() {
    _cancelNoResponseTimer();
    // Hard tier (or a spent Medium budget) waits longer and re-orients with
    // the instruction VO instead of revealing the answer.
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

  /// Tap demo for the Easy tier: the ghost hand taps the left shape, then
  /// its correct right-side match — showing the child the full gesture.
  void _showTapDemo(int leftIndex) {
    if (leftIndex < 0 || leftIndex >= _leftShapes.length) return;
    final leftShape = _leftShapes[leftIndex];
    if (leftShape.isMatched) return;

    MatchableShape? rightMatch;
    for (final s in _rightShapes) {
      if (!s.isMatched &&
          s.shapeType == leftShape.shapeType &&
          s.shapeColor.value == leftShape.shapeColor.value) {
        rightMatch = s;
        break;
      }
    }
    if (rightMatch == null) return;
    final rightTarget = rightMatch;

    _ghostHand?.removeFromParent(); // never more than one demo at a time
    final hand = GhostHand.tap(
      at: leftShape.position + leftShape.size / 2,
      handSize: leftShape.size.x * 0.7,
    );
    _ghostHand = hand;
    add(hand);
    // Second tap on the matching right shape once the first demo ends.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!isMounted || rightTarget.isMatched) return;
      _ghostHand?.removeFromParent();
      final second = GhostHand.tap(
        at: rightTarget.position + rightTarget.size / 2,
        handSize: rightTarget.size.x * 0.7,
      );
      _ghostHand = second;
      add(second);
    });
    analyticsRecordHint(hintType: 'gesture_demo');
  }

  /// Show visual hint for the correct match of a given left shape index.
  /// Called after an incorrect match attempt.
  void _showMatchHint(int leftIndex) {
    if (leftIndex < 0 || leftIndex >= _leftShapes.length) return;

    final leftShape = _leftShapes[leftIndex];
    if (leftShape.isMatched) return;

    // Highlight the left shape
    leftShape.showHint();

    // Find and highlight the correct right-side match by shape type + color
    for (final rightShape in _rightShapes) {
      if (!rightShape.isMatched &&
          rightShape.shapeType == leftShape.shapeType &&
          rightShape.shapeColor.value == leftShape.shapeColor.value) {
        rightShape.showHint();
        break;
      }
    }

    _hintCount++;
    _hintsUsedThisRound++;
    analyticsRecordHint(hintType: 'incorrect_match_hint');
  }

  /// Show visual hint for the first unmatched pair.
  /// Called when the idle timer fires (tier-dependent inactivity).
  void _showIdleHint() {
    // Guard: ensure there are still unmatched shapes
    final hasUnmatched = _leftShapes.any((s) => !s.isMatched);
    if (!hasUnmatched) return;

    // No answer hints available (Hard, or Medium budget spent): re-play the
    // instruction to re-orient attention, but never reveal the answer.
    if (_tier.noHints || !_hintBudgetLeft) {
      onPlayInstructionVo?.call();
      analyticsRecordHint(hintType: 'reorient_instruction');
      _startNoResponseTimer();
      return;
    }

    _consecutiveIdleHints++;

    // Easy tier: still idle after a glow hint → escalate to the tap demo.
    if (_tier.guidedDemo && _consecutiveIdleHints >= 2) {
      for (var i = 0; i < _leftShapes.length; i++) {
        if (!_leftShapes[i].isMatched) {
          _showTapDemo(i);
          break;
        }
      }
    }

    // Find the first unmatched left shape and its correct right match
    for (final leftShape in _leftShapes) {
      if (leftShape.isMatched) continue;

      // Highlight this left shape
      leftShape.showHint();

      // Find and highlight its correct right match
      for (final rightShape in _rightShapes) {
        if (!rightShape.isMatched &&
            rightShape.shapeType == leftShape.shapeType &&
            rightShape.shapeColor.value == leftShape.shapeColor.value) {
          rightShape.showHint();
          break;
        }
      }

      break; // Only hint one pair at a time
    }

    _hintCount++;
    _hintsUsedThisRound++;
    analyticsRecordHint(hintType: 'idle_match_hint');

    // Auto-hide hints after 3 seconds and restart timer
    Future.delayed(const Duration(seconds: 3), () {
      if (!isMounted) return;
      _hideVisualHints();
      _startNoResponseTimer();
    });
  }

  /// Hide all visual hints on all shapes.
  void _hideVisualHints() {
    for (final s in _leftShapes) {
      s.hideHint();
    }
    for (final s in _rightShapes) {
      s.hideHint();
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    // Record ALL taps — valid ones that hit components and invalid ones that missed
    analyticsRecordTouch(
      Offset(event.canvasPosition.x, event.canvasPosition.y),
      isValid: event.handled,
    );
  }

  @override
  void render(Canvas canvas) {
    // Draw center swap arrows
    final centerX = size.x / 2;
    final centerY = size.y / 2;

    final arrowPaint = Paint()
      ..color = const Color(0xFF9B82C4).withAlpha(100)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Horizontal line
    canvas.drawLine(
      Offset(centerX - 30, centerY),
      Offset(centerX + 30, centerY),
      arrowPaint,
    );
    // Left arrow head
    canvas.drawLine(
      Offset(centerX - 30, centerY),
      Offset(centerX - 20, centerY - 8),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(centerX - 30, centerY),
      Offset(centerX - 20, centerY + 8),
      arrowPaint,
    );
    // Right arrow head
    canvas.drawLine(
      Offset(centerX + 30, centerY),
      Offset(centerX + 20, centerY - 8),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(centerX + 30, centerY),
      Offset(centerX + 20, centerY + 8),
      arrowPaint,
    );

    super.render(canvas);
  }

  @override
  void onRemove() {
    _cancelNoResponseTimer();
    super.onRemove();
  }
}
