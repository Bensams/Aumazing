import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';

import 'components/instruction_shape.dart';

/// Do What I Say — instruction-following game.
///
/// Displays shapes and a text instruction like "Tap the RED circle".
/// The child taps the correct shape. Tracks accuracy, response time,
/// and preferred instruction mode.
class DoWhatISayGame extends FlameGame with TapCallbacks {
  DoWhatISayGame({
    required this.totalRounds,
    required this.onStepChanged,
    required this.onGameComplete,
    required this.onInstructionChanged,
  });

  final int totalRounds;
  final void Function(int currentStep) onStepChanged;
  final void Function({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required Map<String, dynamic> extras,
  }) onGameComplete;

  /// Called when the instruction text changes so the Flutter layer can display it.
  final void Function(String instruction) onInstructionChanged;

  // ── State ───────────────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;
  DateTime? _roundStartTime;

  final List<InstructionShape> _shapes = [];
  int _targetIndex = -1;

  // Instruction mode tracking
  int _visualCorrect = 0;
  int _verbalCorrect = 0;
  int _combinedCorrect = 0;

  static const _colorOptions = [
    (Color(0xFFE88888), 'red'),
    (Color(0xFF88B8E8), 'blue'),
    (Color(0xFF88E8A8), 'green'),
    (Color(0xFFE8D888), 'yellow'),
    (Color(0xFFD8A8E8), 'purple'),
    (Color(0xFFE8A888), 'orange'),
  ];

  static const _shapeTypes = ['circle', 'star', 'triangle', 'diamond'];

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _setupRound();
  }

  void _setupRound() {
    // Remove old shapes
    for (final s in _shapes) {
      s.removeFromParent();
    }
    _shapes.clear();

    final rng = math.Random();
    final count = 4 + (_currentRound ~/ 2).clamp(0, 2); // 4-6 shapes

    // Pick random shapes
    final items = <(String, Color, String)>[];
    for (var i = 0; i < count; i++) {
      final shapeType = _shapeTypes[rng.nextInt(_shapeTypes.length)];
      final colorData = _colorOptions[rng.nextInt(_colorOptions.length)];
      items.add((shapeType, colorData.$1, colorData.$2));
    }

    // Layout shapes in a responsive grid
    final gameW = size.x;
    final gameH = size.y;
    final cols = count <= 4 ? 4 : 3;
    final rows = (count / cols).ceil();
    final cardSize = math.min(gameW / (cols + 1.5), gameH / (rows + 1.5));
    final gap = cardSize * 0.2;
    final totalW = cols * cardSize + (cols - 1) * gap;
    final totalH = rows * cardSize + (rows - 1) * gap;
    final startX = (gameW - totalW) / 2;
    final startY = (gameH - totalH) / 2 + gameH * 0.03;

    for (var i = 0; i < items.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final x = startX + col * (cardSize + gap);
      final y = startY + row * (cardSize + gap);
      final item = items[i];

      final shape = InstructionShape(
        shapeType: item.$1,
        shapeColor: item.$2,
        colorName: item.$3,
        sizeCategory: SizeCategory.big,
        index: i,
        onTapped: _onShapeTapped,
        position: Vector2(x, y),
        size: Vector2.all(cardSize),
      );
      _shapes.add(shape);
      add(shape);
    }

    // Pick target
    _targetIndex = rng.nextInt(_shapes.length);
    final target = _shapes[_targetIndex];

    // Generate instruction
    final instruction = 'Tap the ${target.colorName} ${target.shapeType}';
    onInstructionChanged(instruction);

    _roundStartTime = DateTime.now();
  }

  void _onShapeTapped(int index) {
    if (index == _targetIndex) {
      // Correct!
      _score++;
      _shapes[index].showCorrect();

      // Track mode (simplified — always "combined" in v1)
      _combinedCorrect++;

      if (_roundStartTime != null) {
        _totalResponseTimeMs +=
            DateTime.now().difference(_roundStartTime!).inMilliseconds;
      }

      for (final s in _shapes) {
        s.inputEnabled = false;
      }

      _currentRound++;
      onStepChanged(_currentRound);

      if (_currentRound >= totalRounds) {
        Future.delayed(const Duration(milliseconds: 600), () {
          final total = _visualCorrect + _verbalCorrect + _combinedCorrect;
          String preferredMode = 'combined';
          if (total > 0) {
            if (_visualCorrect > _verbalCorrect &&
                _visualCorrect > _combinedCorrect) {
              preferredMode = 'visual';
            } else if (_verbalCorrect > _visualCorrect &&
                _verbalCorrect > _combinedCorrect) {
              preferredMode = 'verbal';
            }
          }

          onGameComplete(
            score: _score,
            totalItems: totalRounds,
            errorCount: _errorCount,
            totalResponseTimeMs: _totalResponseTimeMs,
            extras: {'preferred_mode': preferredMode},
          );
        });
      } else {
        Future.delayed(const Duration(milliseconds: 800), _setupRound);
      }
    } else {
      // Wrong
      _errorCount++;
      _shapes[index].showWrong();
    }
  }
}
