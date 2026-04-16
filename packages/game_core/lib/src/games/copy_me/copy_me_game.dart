import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import 'package:shared_ui/shared_ui.dart';
import 'components/sequence_shape.dart';

/// Copy Me — a "Simon Says" style sequence memory game.
///
/// The app highlights shapes in an increasing sequence and the child
/// must reproduce the sequence by tapping in order.
class CopyMeGame extends FlameGame with TapCallbacks {
  CopyMeGame({
    required this.totalRounds,
    required this.onStepChanged,
    required this.onGameComplete,
  });

  final int totalRounds;
  final void Function(int currentStep) onStepChanged;
  final void Function({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
  }) onGameComplete;

  // ── State ───────────────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;
  int _retries = 0;
  DateTime? _inputStartTime;

  final List<SequenceShape> _shapes = [];
  List<int> _sequence = [];
  int _inputIndex = 0;
  bool _demonstrating = false;
  bool _inputPhase = false;

  /// Notify Flutter layer about phase changes
  void Function(bool isDemoPhase)? onPhaseChanged;

  static const _shapeData = [
    (CopyMeShapeType.circle, AppColors.mint, 'Circle'),
    (CopyMeShapeType.star, AppColors.butterYellow, 'Star'),
    (CopyMeShapeType.heart, AppColors.peach, 'Heart'),
    (CopyMeShapeType.diamond, AppColors.skyBlue, 'Diamond'),
  ];

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _layoutShapes();
    _startRound();
  }

  void _layoutShapes() {
    final gameW = size.x;
    final gameH = size.y;
    const cardSize = 110.0;
    const gap = 24.0;
    const totalW = 4 * cardSize + 3 * gap;
    final startX = (gameW - totalW) / 2;
    final centerY = gameH / 2 - cardSize / 2;

    for (var i = 0; i < 4; i++) {
      final data = _shapeData[i];
      final shape = SequenceShape(
        shapeType: data.$1,
        shapeColor: data.$2,
        index: i,
        onTapped: _onShapeTapped,
        position: Vector2(startX + i * (cardSize + gap), centerY),
        size: Vector2.all(cardSize),
      );
      _shapes.add(shape);
      add(shape);
    }
  }

  void _startRound() {
    _inputIndex = 0;
    _inputPhase = false;

    // Build sequence: length = round + 1 (round 0 → 1 item, etc.)
    final rng = math.Random();
    final len = (_currentRound + 1).clamp(1, 5);
    _sequence = List.generate(len, (_) => rng.nextInt(4));

    // Disable input during demo
    for (final s in _shapes) {
      s.inputEnabled = false;
    }

    _demonstrating = true;
    onPhaseChanged?.call(true);
    _playDemoSequence();
  }

  Future<void> _playDemoSequence() async {
    await Future.delayed(const Duration(milliseconds: 500));

    for (final idx in _sequence) {
      if (!isMounted) return;
      _shapes[idx].highlight();
      await Future.delayed(const Duration(milliseconds: 700));
    }

    if (!isMounted) return;
    _demonstrating = false;
    _inputPhase = true;
    _inputStartTime = DateTime.now();
    onPhaseChanged?.call(false);

    for (final s in _shapes) {
      s.inputEnabled = true;
    }
  }

  void _onShapeTapped(int index) {
    if (!_inputPhase || _demonstrating) return;

    if (index == _sequence[_inputIndex]) {
      // Correct
      _shapes[index].showCorrect();
      _inputIndex++;

      if (_inputIndex >= _sequence.length) {
        // Sequence complete — this round was successful
        _score++;
        if (_inputStartTime != null) {
          _totalResponseTimeMs +=
              DateTime.now().difference(_inputStartTime!).inMilliseconds;
        }

        _inputPhase = false;
        for (final s in _shapes) {
          s.inputEnabled = false;
        }

        _currentRound++;
        onStepChanged(_currentRound);

        if (_currentRound >= totalRounds) {
          Future.delayed(const Duration(milliseconds: 600), () {
            onGameComplete(
              score: _score,
              totalItems: totalRounds,
              errorCount: _errorCount,
              totalResponseTimeMs: _totalResponseTimeMs,
            );
          });
        } else {
          Future.delayed(const Duration(milliseconds: 800), _startRound);
        }
      }
    } else {
      // Wrong
      _shapes[index].showWrong();
      _errorCount++;
      _retries++;

      // Reset input — child retries this sequence
      _inputIndex = 0;
    }
  }

  @override
  void render(Canvas canvas) {
    // Demo phase label
    if (_demonstrating) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'Watch carefully…',
          style: TextStyle(
            color: Color(0xFF9B82C4),
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.x / 2 - tp.width / 2, 20));
    } else if (_inputPhase) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'Your turn! Tap the shapes!',
          style: TextStyle(
            color: Color(0xFF5DAF8E),
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.x / 2 - tp.width / 2, 20));
    }

    super.render(canvas);
  }
}
