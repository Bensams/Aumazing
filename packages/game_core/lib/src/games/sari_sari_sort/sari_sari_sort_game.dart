import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_ui/shared_ui.dart';

import 'components/category_bin.dart';
import '../shared/answer_label.dart';
import 'components/draggable_item.dart';
import '../shared/ghost_hand.dart';
import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/adaptive_difficulty.dart';
import '../../config/difficulty_profile.dart';
import '../shared/game_layout.dart';

/// The three sari-sari store categories the child sorts items into.
///
/// Slugs intentionally mirror the concept document
/// (food / drinks / toiletries) so telemetry lines up with the planned
/// XGBoost feature set.
enum StoreCategory {
  food('food', 'Pagkain', '🍱', Color(0xFFFF8C42)),
  drinks('drinks', 'Inumin', '🥤', Color(0xFF42B4E8)),
  toiletries('toiletries', 'Gamit', '🧼', Color(0xFF5DAF8E));

  const StoreCategory(this.slug, this.label, this.emoji, this.color);

  final String slug;
  final String label;
  final String emoji;
  final Color color;
}

/// "Sari-Sari Store Sorting" — a drag-and-drop categorisation game set in a
/// Filipino neighbourhood store.
///
/// Each round the child is given a tray of items (kendi, tinapay, gatas …) and
/// drags each one into the correct category basket (Pagkain / Inumin / Gamit).
/// Correct drops lock the item into the basket; wrong drops shake, snap back,
/// and surface a hint highlighting the right basket.
///
/// Targets Play Skills (categorisation, matching, multi-step instructions) and
/// Communication (item identification), and emits the same XGBoost-ready
/// telemetry as the assessment games via [EnhancedGameplayAnalyticsMixin].
class SariSariSortGame extends FlameGame
    with DragCallbacks, EnhancedGameplayAnalyticsMixin {
  SariSariSortGame({
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.totalRounds = 3,
    this.itemsPerRound = 3,
    this.gameVersion,
    this.strings = const AppStrings(GameLanguage.english),
    this.profile = DifficultyProfile.medium,
    this.onCorrectDrop,
    this.onWrongAnswer,
    // Audio event callbacks (optional, wired by screen wrappers).
    this.onPlayCorrectSfx,
    this.onPlayWrongSfx,
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

  /// Fired on each correct drop (used by the Flutter layer for haptics).
  final void Function()? onCorrectDrop;

  /// Fired on each wrong drop, alongside the wrong SFX and the encouraging
  /// voice line. The Flutter layer uses it for the mascot's reaction, so the
  /// character answers a mistake the same way the audio does.
  final void Function()? onWrongAnswer;

  // ── Audio event callbacks ────────────────────────────────────────────
  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayDragSfx;
  final VoidCallback? onPlayDropSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;
  /// Immediate feedback on a correct sort: the item that went in the right
  /// basket, so the app can name it back ("Gatas"). Praise waits for the end
  /// of the game.
  final AnswerLabelCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final VoidCallback? onPlayInstructionVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;

  final int totalRounds;
  final int itemsPerRound;
  final String childId;
  final String? gameVersion;

  /// Localized strings (English / Tagalog / Cebuano) for on-screen labels.
  final AppStrings strings;

  /// Hint/guidance policy for the selected difficulty tier (ABA prompt
  /// hierarchy — see [DifficultyProfile]).
  final DifficultyProfile profile;

  /// The localized basket label for a category, following [strings].
  String _binLabel(StoreCategory category) {
    switch (category) {
      case StoreCategory.food:
        return strings.binFood;
      case StoreCategory.drinks:
        return strings.binDrinks;
      case StoreCategory.toiletries:
        return strings.binToiletries;
    }
  }

  // ── Game state ───────────────────────────────────────────────────────
  int _currentRound = 0;
  int _score = 0;
  int _errorCount = 0;
  int _totalResponseTimeMs = 0;
  int _hintCount = 0;
  DateTime? _itemStartTime;
  bool _firstInputRecorded = false;

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

  final List<CategoryBin> _bins = [];
  final List<DraggableItem> _items = [];

  /// Where the child is currently holding an item, as a fraction of the game's
  /// size — (0,0) is the top-left corner, (1,1) the bottom-right; null when
  /// nothing is held.
  ///
  /// The Flutter layer feeds this to the mascot so the character watches the
  /// item travel to the basket. Normalised here rather than passed as pixels
  /// because the mascot has no idea how big the game surface is, and a
  /// [ValueNotifier] rather than a callback so only the character rebuilds on
  /// it — this changes every frame of a drag.
  final ValueNotifier<Offset?> dragFocus = ValueNotifier<Offset?>(null);

  Timer? _noResponseTimer;

  /// Item catalogue, grouped by category. Filipino sari-sari staples.
  static const Map<StoreCategory, List<StoreItemData>> _catalogue = {
    StoreCategory.food: [
      StoreItemData(name: 'Tinapay', emoji: '🍞', category: StoreCategory.food, color: Color(0xFFD9A05B)),   // bread tan
      StoreItemData(name: 'Biskwit', emoji: '🍪', category: StoreCategory.food, color: Color(0xFFC68A4E)),   // biscuit brown
      StoreItemData(name: 'Kendi', emoji: '🍬', category: StoreCategory.food, color: Color(0xFFFF7EB0)),     // candy pink
      StoreItemData(name: 'Saging', emoji: '🍌', category: StoreCategory.food, color: Color(0xFFF5D547)),    // banana yellow
      StoreItemData(name: 'Mansanas', emoji: '🍎', category: StoreCategory.food, color: Color(0xFFE0413E)),  // apple red
    ],
    StoreCategory.drinks: [
      StoreItemData(name: 'Tubig', emoji: '💧', category: StoreCategory.drinks, color: Color(0xFF8FD2EF)),    // water light blue
      StoreItemData(name: 'Gatas', emoji: '🥛', category: StoreCategory.drinks, color: Color(0xFFF1EEE2)),    // milk cream
      StoreItemData(name: 'Juice', emoji: '🧃', category: StoreCategory.drinks, color: Color(0xFFFFA64D)),    // juice orange
      StoreItemData(name: 'Softdrink', emoji: '🥤', category: StoreCategory.drinks, color: Color(0xFFD64545)), // cola red
      StoreItemData(name: 'Kape', emoji: '☕', category: StoreCategory.drinks, color: Color(0xFF7A5230)),     // coffee brown
    ],
    StoreCategory.toiletries: [
      StoreItemData(name: 'Sabon', emoji: '🧼', category: StoreCategory.toiletries, color: Color(0xFF8BC36A)),  // soap green
      StoreItemData(name: 'Sipilyo', emoji: '🪥', category: StoreCategory.toiletries, color: Color(0xFF45C4C0)), // toothbrush teal
      StoreItemData(name: 'Tisyu', emoji: '🧻', category: StoreCategory.toiletries, color: Color(0xFFF1EEE2)),  // tissue white
      StoreItemData(name: 'Syampu', emoji: '🧴', category: StoreCategory.toiletries, color: Color(0xFFB088D9)), // shampoo purple
    ],
  };

  /// Tracks recently used items per category to reduce repetition.
  final Set<String> _usedItems = {};

  @override
  Color backgroundColor() => const Color(0x00000000); // transparent

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    analyticsInitialize(
      gameId: 'sari_sari_sort',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion ?? '1.0.0',
    );
    analyticsStartSession();

    _buildBins();
    onPlayInstructionVo?.call();
    _setupRound();
  }

  // ── Layout ───────────────────────────────────────────────────────────

  /// Width of a category bin. Shared so the item tray can be sized against
  /// the space the bins leave it.
  double get _binWidth => math.min(size.x / 4.2, size.y / 1.9);

  /// Y of the top of the bin row — the floor the draggable tray must clear.
  double get _binTop => size.y - _binWidth * 0.95 - size.y * 0.06;

  void _buildBins() {
    final gameW = size.x;

    final binW = _binWidth;
    final binH = binW * 0.95;
    final binY = _binTop;
    final gap = (gameW - 3 * binW) / 4;

    final categories = StoreCategory.values;
    for (var i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final x = gap + i * (binW + gap);
      final bin = CategoryBin(
        category: cat,
        label: _binLabel(cat),
        emoji: cat.emoji,
        color: cat.color,
        position: Vector2(x, binY),
        size: Vector2(binW, binH),
      );
      _bins.add(bin);
      add(bin);
    }
  }

  void _setupRound() {
    _cancelNoResponseTimer();

    for (final item in _items) {
      item.removeFromParent();
    }
    _items.clear();
    _hideHints();
    _firstInputRecorded = false;
    // _hintCount is the session total reported as `hint_count` at the end, so
    // it deliberately survives the round reset — clearing it here meant the
    // metric only ever described the last round. _hintsUsedThisRound is the
    // per-round budget and is the one that starts over.
    _hintsUsedThisRound = 0;
    _consecutiveIdleHints = 0;
    _errorsSinceLastCorrect = 0;
    _adaptive.startRound(); // any step-down only lasts one round

    final roundItems = _pickRoundItems();

    final gameW = size.x;
    final gameH = size.y;
    final trayAvail = _binTop - kTopOverlayBand;
    var itemSize = math.min(gameW / 6.5, gameH / 3.6);
    if (itemSize > trayAvail * 0.92) itemSize = trayAvail * 0.92;
    final gap = itemSize * 0.4;
    final totalW = roundItems.length * itemSize + (roundItems.length - 1) * gap;
    final startX = (gameW - totalW) / 2;
    final trayY = kTopOverlayBand + (trayAvail - itemSize) / 2;

    for (var i = 0; i < roundItems.length; i++) {
      final data = roundItems[i];
      final x = startX + i * (itemSize + gap);
      final item = DraggableItem(
        data: data,
        color: data.color,
        onPickedUp: _onItemPickedUp,
        onDropped: _onItemDropped,
        onMoved: _onItemMoved,
        position: Vector2(x, trayY),
        size: Vector2.all(itemSize),
      );
      _items.add(item);
      add(item);
    }

    _itemStartTime = DateTime.now();

    analyticsStartRound(roundNumber: _currentRound + 1);
    analyticsShowStimulus();
    analyticsAddRoundData('items_in_round', roundItems.length);

    _startNoResponseTimer();
  }

  /// Picks [itemsPerRound] items with a spread of categories, avoiding recent
  /// repeats. Guarantees at least one item from a non-repeating category mix.
  List<StoreItemData> _pickRoundItems() {
    final rng = math.Random();

    // Reset the used-pool when most items have been shown.
    final totalItems =
        _catalogue.values.fold<int>(0, (sum, l) => sum + l.length);
    if (_usedItems.length > totalItems - itemsPerRound) {
      _usedItems.clear();
    }

    final picked = <StoreItemData>[];
    final categories = StoreCategory.values.toList()..shuffle(rng);

    // First pass: one item from each category (round-robin) for variety.
    var catIndex = 0;
    var safety = 0;
    while (picked.length < itemsPerRound && safety < 200) {
      safety++;
      final cat = categories[catIndex % categories.length];
      catIndex++;
      final pool = _catalogue[cat]!
          .where((d) => !_usedItems.contains(d.name))
          .where((d) => !picked.contains(d))
          .toList();
      if (pool.isEmpty) continue;
      final choice = pool[rng.nextInt(pool.length)];
      picked.add(choice);
      _usedItems.add(choice.name);
    }

    // Fallback (shouldn't trigger) — top up from the full catalogue.
    if (picked.length < itemsPerRound) {
      final all = _catalogue.values.expand((l) => l).toList()..shuffle(rng);
      for (final d in all) {
        if (picked.length >= itemsPerRound) break;
        if (!picked.contains(d)) picked.add(d);
      }
    }

    picked.shuffle(rng);
    return picked;
  }

  // ── Drag outcome logic ───────────────────────────────────────────────

  void _onItemPickedUp(DraggableItem item) {
    _cancelNoResponseTimer();
    _hideHints();
    _consecutiveIdleHints = 0; // child re-engaged — reset hint escalation
    onPlayDragSfx?.call();
  }

  /// Null once the item is let go — the character stops tracking and returns
  /// to its rest pose.
  void _onItemMoved(Vector2? center) {
    if (center == null || size.x <= 0 || size.y <= 0) {
      dragFocus.value = null;
      return;
    }
    dragFocus.value = Offset(
      (center.x / size.x).clamp(0.0, 1.0),
      (center.y / size.y).clamp(0.0, 1.0),
    );
  }

  void _onItemDropped(DraggableItem item, Vector2 dropCenter) {
    onPlayDropSfx?.call();

    // Find a bin under the item's center.
    CategoryBin? targetBin;
    for (final bin in _bins) {
      if (bin.containsPoint(dropCenter)) {
        targetBin = bin;
        break;
      }
    }

    // Dropped outside every bin — neutral, just return it to the tray.
    if (targetBin == null) {
      item.returnHome();
      _startNoResponseTimer();
      return;
    }

    if (!_firstInputRecorded) {
      analyticsRecordValidAction();
      _firstInputRecorded = true;
    }

    final responseTime = _itemStartTime != null
        ? DateTime.now().difference(_itemStartTime!).inMilliseconds
        : 0;

    final correct = targetBin.category == item.data.category;

    if (correct) {
      _score++;
      _totalResponseTimeMs += responseTime;
      _errorsSinceLastCorrect = 0;
      _adaptive.recordCorrect();

      analyticsRecordCorrect(extraData: {
        'item': item.data.name,
        'category': item.data.category.slug,
        'response_time_ms': responseTime,
      });

      onCorrectDrop?.call();
      onPlayCorrectSfx?.call();
      onPlayCorrectVo?.call(AnswerLabel(item: item.data.name));

      final binCenter = targetBin.position + targetBin.size / 2;
      _items.remove(item);
      item.lockInto(binCenter, onSettled: item.removeFromParent);

      if (_items.isEmpty) {
        _onRoundComplete();
      } else {
        // Reset response timing for the next item in the tray.
        _itemStartTime = DateTime.now();
        _firstInputRecorded = false;
        analyticsShowStimulus();
        _startNoResponseTimer();
      }
    } else {
      _errorCount++;
      _errorsSinceLastCorrect++;

      // Adaptive stepping: repeated struggle steps the tier down (more
      // support) for the rest of this round.
      if (_adaptive.recordError()) {
        analyticsAddRoundData('difficulty_step_down', _tier.level);
      }

      analyticsRecordWrong(extraData: {
        'item': item.data.name,
        'expected_category': item.data.category.slug,
        'dropped_category': targetBin.category.slug,
      });
      analyticsRecordRetry();

      onPlayWrongSfx?.call();
      onPlayWrongVo?.call();
      onWrongAnswer?.call();

      item.showError();
      Future.delayed(const Duration(milliseconds: 450), () {
        if (!isMounted) return;
        item.returnHome();
        // Answer hint only when the difficulty tier's budget allows it
        // (Easy: always; Medium: while budget lasts; Hard: never).
        if (_hintBudgetLeft) {
          _showCorrectBinHint(item.data.category);
          // Easy tier: after repeated errors, escalate to the guided
          // gesture demo showing exactly how to drag this item.
          if (_tier.guidedDemo && _errorsSinceLastCorrect >= 2) {
            _showGestureDemo(item);
          }
        }
        _itemStartTime = DateTime.now();
        Future.delayed(const Duration(seconds: 3), () {
          if (!isMounted) return;
          _hideHints();
          _startNoResponseTimer();
        });
      });
    }
  }

  void _onRoundComplete() {
    _cancelNoResponseTimer();
    analyticsCompleteRound(successful: true);

    _currentRound++;
    onStepChanged(_currentRound);

    if (_currentRound >= totalRounds) {
      onPlayGameCompleteSfx?.call();
      onPlayCelebrationVo?.call();

      analyticsMarkCompleted();
      analyticsAddGameSpecificMetric(
        'avg_sort_time_ms',
        _totalResponseTimeMs / (_score > 0 ? _score : 1),
      );
      analyticsAddGameSpecificMetric(
        'sorting_accuracy',
        _score / ((_score + _errorCount) > 0 ? _score + _errorCount : 1),
      );
      analyticsAddGameSpecificMetric('hint_count', _hintCount);
      analyticsCompleteSession();

      Future.delayed(const Duration(milliseconds: 600), () {
        onGameComplete(
          score: _score,
          totalItems: totalRounds * itemsPerRound,
          errorCount: _errorCount,
          totalResponseTimeMs: _totalResponseTimeMs,
          analytics: analyticsSession,
        );
      });
    } else {
      onPlayLevelCompleteSfx?.call();
      onPlayTransitionVo?.call();
      Future.delayed(const Duration(milliseconds: 800), _setupRound);
    }
  }

  // ── Hints / idle timer ───────────────────────────────────────────────

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

  void _showIdleHint() {
    if (_items.isEmpty) return;

    // No answer hints available (Hard, or Medium budget spent): re-play the
    // instruction to re-orient attention, but never reveal the answer.
    if (_tier.noHints || !_hintBudgetLeft) {
      onPlayInstructionVo?.call();
      analyticsRecordHint(hintType: 'reorient_instruction');
      _startNoResponseTimer();
      return;
    }

    _consecutiveIdleHints++;

    // Hint the correct bin for the first remaining item.
    final item = _items.first;
    _showCorrectBinHint(item.data.category);

    // Easy tier: still idle after a glow hint → escalate to the guided
    // gesture demo (ghost hand dragging the item into its bin).
    if (_tier.guidedDemo && _consecutiveIdleHints >= 2) {
      _showGestureDemo(item);
    }

    Future.delayed(const Duration(seconds: 3), () {
      if (!isMounted) return;
      _hideHints();
      _startNoResponseTimer();
    });
  }

  void _showCorrectBinHint(StoreCategory category) {
    for (final bin in _bins) {
      if (bin.category == category) {
        bin.showHint();
        break;
      }
    }
    _hintCount++;
    _hintsUsedThisRound++;
    analyticsRecordHint(hintType: 'category_bin_hint');
  }

  /// Ghost-hand demo dragging [item] from its tray slot into the correct bin.
  void _showGestureDemo(DraggableItem item) {
    CategoryBin? bin;
    for (final b in _bins) {
      if (b.category == item.data.category) {
        bin = b;
        break;
      }
    }
    if (bin == null) return;

    _ghostHand?.removeFromParent(); // never more than one demo at a time
    final hand = GhostHand.drag(
      from: item.position + item.size / 2,
      to: bin.position + bin.size / 2,
      handSize: item.size.x * 0.7,
    );
    _ghostHand = hand;
    add(hand);
    analyticsRecordHint(hintType: 'gesture_demo');
  }

  /// Takes every prompt off the screen — the basket glow and the ghost hand.
  ///
  /// The hand used to be left running, because it removes itself when its
  /// demo finishes. But the demo is only over on its own schedule: a child who
  /// picks the item up mid-demo is then dragging it while a second, ghostly
  /// hand drags the same item somewhere else. Whoever is being shown what to
  /// do has already started doing it, so the demo stops.
  void _hideHints() {
    for (final bin in _bins) {
      bin.hideHint();
    }
    if (_ghostHand?.isMounted ?? false) _ghostHand?.removeFromParent();
    _ghostHand = null;
  }

  // ── Analytics: record drags that miss every item as random touches ───

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    // Reaches the game only when no item consumed the drag → off-target touch.
    analyticsRecordTouch(
      Offset(event.canvasPosition.x, event.canvasPosition.y),
      isValid: false,
    );
  }

  @override
  void onRemove() {
    _cancelNoResponseTimer();
    dragFocus.dispose();
    super.onRemove();
  }
}
