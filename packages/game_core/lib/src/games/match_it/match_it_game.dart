import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';

import 'package:shared_ui/shared_ui.dart';
import 'components/matchable_shape.dart';

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
}

/// The core Flame game for "Match It".
///
/// Presents two columns of shapes — the child taps one on the left,
/// then one on the right. If they match, it advances the step.
/// Tracks score, errors, and response times for assessment.
class MatchItGame extends FlameGame with TapCallbacks {
  MatchItGame({
    required this.onStepChanged,
    required this.onGameComplete,
    this.totalRounds = 5,
  });

  final void Function(int currentStep) onStepChanged;
  final void Function({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
  }) onGameComplete;

  final int totalRounds;

  // ── Game state ───────────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;
  DateTime? _roundStartTime;

  int? _selectedLeftIndex;
  int? _selectedRightIndex;

  final List<MatchableShape> _leftShapes = [];
  final List<MatchableShape> _rightShapes = [];

  /// Tracks indices of pairs already used in previous rounds to reduce
  /// repetition. Resets when the pool is exhausted.
  final Set<int> _usedPairIndices = {};

  static const List<MatchPairData> _allPairs = [
    // Stars — 3 colour variants
    MatchPairData(
        shape: ShapeType.star, color: Color(0xFFF5C842), label: 'Gold Star'),
    MatchPairData(
        shape: ShapeType.star, color: Color(0xFFFF8C42), label: 'Orange Star'),
    MatchPairData(
        shape: ShapeType.star, color: Color(0xFFFF5252), label: 'Red Star'),
    // Hearts — 3 colour variants
    MatchPairData(
        shape: ShapeType.heart, color: Color(0xFFE86B6B), label: 'Red Heart'),
    MatchPairData(
        shape: ShapeType.heart,
        color: Color(0xFFC76BD1),
        label: 'Purple Heart'),
    MatchPairData(
        shape: ShapeType.heart,
        color: Color(0xFFFF6B9D),
        label: 'Pink Heart'),
    // Circles — 3 colour variants
    MatchPairData(
        shape: ShapeType.circle,
        color: Color(0xFF5DAF8E),
        label: 'Green Circle'),
    MatchPairData(
        shape: ShapeType.circle,
        color: Color(0xFF42B4E8),
        label: 'Blue Circle'),
    MatchPairData(
        shape: ShapeType.circle,
        color: Color(0xFFFFB74D),
        label: 'Orange Circle'),
    // Diamonds — 3 colour variants
    MatchPairData(
        shape: ShapeType.diamond,
        color: Color(0xFF5B9BD5),
        label: 'Blue Diamond'),
    MatchPairData(
        shape: ShapeType.diamond,
        color: Color(0xFF7ED957),
        label: 'Green Diamond'),
    MatchPairData(
        shape: ShapeType.diamond,
        color: Color(0xFFE040FB),
        label: 'Magenta Diamond'),
    // Triangles — 3 colour variants
    MatchPairData(
        shape: ShapeType.triangle,
        color: Color(0xFF9B82C4),
        label: 'Purple Triangle'),
    MatchPairData(
        shape: ShapeType.triangle,
        color: Color(0xFF26C6DA),
        label: 'Teal Triangle'),
    MatchPairData(
        shape: ShapeType.triangle,
        color: Color(0xFFFFCA28),
        label: 'Yellow Triangle'),
  ];

  @override
  Color backgroundColor() => const Color(0x00000000); // Transparent

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _setupRound();
  }

  void _setupRound() {
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

    // Create a shuffled order for right column
    final rightOrder = List<int>.generate(3, (i) => i)..shuffle(rng);

    // Responsive layout constants
    final gameW = size.x;
    final gameH = size.y;
    final cardSize = math.min(gameW / 5.0, gameH / 4.5);
    final cardGap = cardSize * 0.15;
    final totalHeight = 3 * cardSize + 2 * cardGap;
    final startY = (gameH - totalHeight) / 2;
    final leftX = gameW * 0.18;
    final rightX = gameW * 0.82 - cardSize;

    for (var i = 0; i < 3; i++) {
      final y = startY + i * (cardSize + cardGap);

      final leftShape = MatchableShape(
        shapeType: roundPairs[i].shape,
        shapeColor: roundPairs[i].color,
        index: i,
        onSelected: _onLeftSelected,
        position: Vector2(leftX, y),
        size: Vector2.all(cardSize),
      );

      final ri = rightOrder[i];
      final rightShape = MatchableShape(
        shapeType: roundPairs[ri].shape,
        shapeColor: roundPairs[ri].color,
        index: ri,
        onSelected: _onRightSelected,
        position: Vector2(rightX, y),
        size: Vector2.all(cardSize),
      );

      _leftShapes.add(leftShape);
      _rightShapes.add(rightShape);
      add(leftShape);
      add(rightShape);
    }

    _roundStartTime = DateTime.now();
  }

  void _onLeftSelected(int index) {
    // Deselect previous
    for (final s in _leftShapes) {
      if (s.isSelected) s.deselect();
    }
    _selectedLeftIndex = index;
    _leftShapes[index].select();
    _checkMatch();
  }

  void _onRightSelected(int index) {
    // Deselect previous
    for (final s in _rightShapes) {
      if (s.isSelected) s.deselect();
    }
    _selectedRightIndex = index;
    for (final s in _rightShapes) {
      if (s.index == index) s.select();
    }
    _checkMatch();
  }

  void _checkMatch() {
    if (_selectedLeftIndex == null || _selectedRightIndex == null) return;

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

      leftShape.markMatched();
      rightShape.markMatched();

      _selectedLeftIndex = null;
      _selectedRightIndex = null;

      // Check if all 3 pairs matched in this round
      final allMatched = _leftShapes.every((s) => s.isMatched);
      if (allMatched) {
        _currentRound++;
        onStepChanged(_currentRound);

        if (_currentRound >= totalRounds) {
          // Game complete
          Future.delayed(const Duration(milliseconds: 600), () {
            onGameComplete(
              score: _score,
              totalItems: totalRounds * 3,
              errorCount: _errorCount,
              totalResponseTimeMs: _totalResponseTimeMs,
            );
          });
        } else {
          // Next round after a brief pause
          Future.delayed(const Duration(milliseconds: 800), _setupRound);
        }
      } else {
        _roundStartTime = DateTime.now();
      }
    } else {
      // Wrong match
      _errorCount++;

      leftShape.showError();
      rightShape.showError();

      Future.delayed(const Duration(milliseconds: 500), () {
        _selectedLeftIndex = null;
        _selectedRightIndex = null;
        _roundStartTime = DateTime.now();
      });
    }
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
}
