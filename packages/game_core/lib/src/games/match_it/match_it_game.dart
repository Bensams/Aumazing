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

  static const List<MatchPairData> _allPairs = [
    MatchPairData(
        shape: ShapeType.star, color: AppColors.butterYellow, label: 'Star'),
    MatchPairData(
        shape: ShapeType.heart, color: AppColors.peach, label: 'Heart'),
    MatchPairData(
        shape: ShapeType.circle, color: AppColors.mint, label: 'Circle'),
    MatchPairData(
        shape: ShapeType.diamond, color: AppColors.skyBlue, label: 'Diamond'),
    MatchPairData(
        shape: ShapeType.triangle,
        color: AppColors.lavender,
        label: 'Triangle'),
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

    // Pick 3 random pairs for this round
    final rng = math.Random();
    final shuffled = List<MatchPairData>.from(_allPairs)..shuffle(rng);
    final roundPairs = shuffled.take(3).toList();

    // Create a shuffled order for right column
    final rightOrder = List<int>.generate(3, (i) => i)..shuffle(rng);

    // Layout constants
    final gameW = size.x;
    final gameH = size.y;
    const cardSize = 110.0;
    const cardGap = 16.0;
    const totalHeight = 3 * cardSize + 2 * cardGap;
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
    if (_selectedLeftIndex != null && _selectedLeftIndex! < _leftShapes.length) {
      _leftShapes[_selectedLeftIndex!].deselect();
    }
    _selectedLeftIndex = index;
    _leftShapes[index].select();
    _checkMatch();
  }

  void _onRightSelected(int index) {
    if (_selectedRightIndex != null) {
      for (final s in _rightShapes) {
        if (s.index == _selectedRightIndex) s.deselect();
      }
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

    if (_selectedLeftIndex == _selectedRightIndex) {
      // Correct match!
      _score++;
      _totalResponseTimeMs += responseTime;

      // Mark both as matched
      _leftShapes[_selectedLeftIndex!].markMatched();
      for (final s in _rightShapes) {
        if (s.index == _selectedRightIndex) s.markMatched();
      }

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

      _leftShapes[_selectedLeftIndex!].showError();
      for (final s in _rightShapes) {
        if (s.index == _selectedRightIndex) s.showError();
      }

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
