import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';

import 'components/instruction_shape.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';

/// Do What I Say — instruction-following game with XGBoost-ready analytics.
///
/// Displays shapes and a text instruction like "Tap the RED circle".
/// The child taps the correct shape. Tracks comprehensive analytics for ML analysis.
class DoWhatISayGame extends FlameGame with TapCallbacks, EnhancedGameplayAnalyticsMixin {
  DoWhatISayGame({
    required this.totalRounds,
    required this.onStepChanged,
    required this.onGameComplete,
    required this.onInstructionChanged,
    required this.childId,
    this.gameVersion,
  });

  final int totalRounds;
  final String childId;
  final String? gameVersion;
  final void Function(int currentStep) onStepChanged;
  final void Function({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
    required Map<String, dynamic> extras,
    GameSessionMetrics? analytics,
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

    // Initialize and start analytics session
    analyticsInitialize(
      gameId: 'do_what_i_say',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion ?? '1.0.0',
    );
    analyticsStartSession();

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

    // Start round and show stimulus
    analyticsStartRound(roundNumber: _currentRound + 1);
    analyticsShowStimulus();

    // Record instruction as a prompt
    analyticsRecordPrompt(promptType: 'verbal_instruction');

    // Add round-specific data
    analyticsAddRoundData('shape_count', _shapes.length);
    analyticsAddRoundData('target_shape', target.shapeType);
    analyticsAddRoundData('target_color', target.colorName);
  }

  void _onShapeTapped(int index) {
    final target = _shapes[_targetIndex];

    if (index == _targetIndex) {
      // Correct!
      _score++;

      // Record valid action on first tap
      analyticsRecordValidAction();

      // Record correct response with details
      analyticsRecordCorrect(extraData: {
        'target_shape': target.shapeType,
        'target_color': target.colorName,
        'distractor_count': _shapes.length - 1,
      });

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

      // Complete round
      analyticsCompleteRound(successful: true);
      analyticsAddRoundData('instruction_followed', true);

      if (_currentRound >= totalRounds) {
        // Game complete
        analyticsMarkCompleted();
        analyticsCompleteSession();

        // Add game-specific metrics
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

        analyticsAddGameSpecificMetric('preferred_mode', preferredMode);
        analyticsAddGameSpecificMetric('avg_response_time_ms',
          _totalResponseTimeMs / (_score > 0 ? _score : 1));
        analyticsAddGameSpecificMetric('max_shape_count',
          4 + ((totalRounds - 1) ~/ 2).clamp(0, 2));

        Future.delayed(const Duration(milliseconds: 600), () {
          onGameComplete(
            score: _score,
            totalItems: totalRounds,
            errorCount: _errorCount,
            totalResponseTimeMs: _totalResponseTimeMs,
            extras: {'preferred_mode': preferredMode},
            analytics: analyticsSession,
          );
        });
      } else {
        Future.delayed(const Duration(milliseconds: 800), _setupRound);
      }
    } else {
      // Wrong - tapped wrong shape
      _errorCount++;

      final tappedShape = _shapes[index];

      // Record wrong response with details
      analyticsRecordWrong(extraData: {
        'tapped_shape': tappedShape.shapeType,
        'tapped_color': tappedShape.colorName,
        'target_shape': target.shapeType,
        'target_color': target.colorName,
        'error_type': tappedShape.shapeType == target.shapeType
          ? 'color_error'
          : tappedShape.colorName == target.colorName
            ? 'shape_error'
            : 'both_error',
      });

      _shapes[index].showWrong();
    }
  }
}
