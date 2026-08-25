import 'dart:async' as async;
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../analytics/enhanced_analytics_mixin.dart';
import '../../analytics/models/models.dart';
import '../../config/difficulty_profile.dart';
import '../../config/game_motion.dart';
import '../sari_sari_sort/components/draggable_item.dart';
import '../sari_sari_sort/sari_sari_sort_game.dart';
import '../shared/answer_label.dart';
import '../shared/game_layout.dart';
import '../shared/ghost_hand.dart';
import 'buddy_art_cache.dart';
import '../shared/game_lifecycle_guard.dart';
import 'components/buddy_component.dart';

enum TulongDropOutcome { correct, wrongItem, wrongRecipient, motorMiss }

class TulongRequest {
  const TulongRequest({required this.buddyIndex, required this.item});
  final int buddyIndex;
  final StoreItemData item;
}

/// Small, separately testable accumulator for the game's diagnostic metrics.
class TulongKaibiganMetrics {
  int correctRecipients = 0;
  int wrongRecipients = 0;
  int bubbleRecallErrors = 0;
  final List<int> dragHesitationsMs = [];
  int promptLevelUsed = 0;

  void record(TulongDropOutcome outcome, {required bool bubbleWasVisible}) {
    if (outcome == TulongDropOutcome.correct) correctRecipients++;
    if (outcome == TulongDropOutcome.wrongRecipient) wrongRecipients++;
    if (!bubbleWasVisible &&
        (outcome == TulongDropOutcome.wrongItem ||
            outcome == TulongDropOutcome.wrongRecipient)) {
      bubbleRecallErrors++;
    }
  }

  double get wrongRecipientRate {
    final opportunities = correctRecipients + wrongRecipients;
    return opportunities == 0 ? 0 : wrongRecipients / opportunities;
  }

  double get averageDragHesitationMs =>
      dragHesitationsMs.isEmpty
          ? 0
          : dragHesitationsMs.reduce((a, b) => a + b) /
              dragHesitationsMs.length;
}

class TulongKaibiganGame extends FlameGame
    with GameLifecycleGuard, DragCallbacks, EnhancedGameplayAnalyticsMixin {
  TulongKaibiganGame({
    required this.onStepChanged,
    required this.onGameComplete,
    required this.childId,
    this.totalRounds = 4,
    this.itemsPerRound = 3,
    this.gameVersion,
    this.strings = const AppStrings(GameLanguage.english),
    this.profile = DifficultyProfile.medium,
    this.onCorrectDrop,
    this.onWrongAnswer,
    this.onPlayCorrectSfx,
    this.onPlayWrongSfx,
    this.onPlayDragSfx,
    this.onPlayDropSfx,
    this.onPlayLevelCompleteSfx,
    this.onPlayGameCompleteSfx,
    this.onPlayCorrectVo,
    this.onPlayWrongVo,
    this.onPlayRequestVo,
    this.onPlayThankYouVo,
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
  })
  onGameComplete;
  final String childId;
  final int totalRounds;
  final int itemsPerRound;
  final String? gameVersion;
  final AppStrings strings;
  final DifficultyProfile profile;
  final VoidCallback? onCorrectDrop;
  final VoidCallback? onWrongAnswer;
  final VoidCallback? onPlayCorrectSfx;
  final VoidCallback? onPlayWrongSfx;
  final VoidCallback? onPlayDragSfx;
  final VoidCallback? onPlayDropSfx;
  final VoidCallback? onPlayLevelCompleteSfx;
  final VoidCallback? onPlayGameCompleteSfx;
  final AnswerLabelCallback? onPlayCorrectVo;
  final VoidCallback? onPlayWrongVo;
  final AnswerLabelCallback? onPlayRequestVo;
  final VoidCallback? onPlayThankYouVo;
  final VoidCallback? onPlayTransitionVo;
  final VoidCallback? onPlayCelebrationVo;

  final TulongKaibiganMetrics socialMetrics = TulongKaibiganMetrics();
  final List<BuddyComponent> _buddies = [];
  final List<DraggableItem> _items = [];
  final Set<String> _usedItems = {};
  final math.Random _random = math.Random();
  List<TulongRequest> _requests = [];
  int _round = 0;
  int _requestIndex = 0;
  int _score = 0;
  int _plainErrors = 0;
  int _totalResponseTimeMs = 0;
  int _errorsThisTrial = 0;
  int _hintsThisRound = 0;
  DateTime? _requestShownAt;
  DraggableItem? _draggingItem;
  async.Timer? _bubbleTimer;
  async.Timer? _idleTimer;
  GhostHand? _ghostHand;

  int get _tier => profile.level.clamp(1, 3);
  bool get _mayHint =>
      !profile.noHints &&
      (profile.unlimitedHints ||
          _hintsThisRound < (profile.hintsPerRound ?? 0));
  TulongRequest get _activeRequest => _requests[_requestIndex];

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await TulongBuddyArt.ensureLoaded();
    analyticsInitialize(
      gameId: 'tulong_kaibigan',
      childId: childId,
      totalRounds: totalRounds,
      gameVersion: gameVersion ?? '1.0.0',
    );
    analyticsStartSession();
    _buildBuddies();
    _setupRound();
  }

  // ── Layout ───────────────────────────────────────────────────────────
  //
  // The field is split into two columns, so the child reads the request on the
  // left and answers it on the right:
  //
  //   ├─ kTopOverlayBand ───────────────────────────────────────────────┤
  //   │                                                                 │
  //   │   ┌── character ──┐  ┌─────────── options ─────────────┐        │
  //   │   │   bubble      │  │   ┌─────┐   ┌─────┐             │        │
  //   │   │   buddy       │  │   └─────┘   └─────┘             │        │
  //   │   └───────────────┘  └─────────────────────────────────┘        │
  //   ├─ bottom inset ──────────────────────────────────────────────────┤
  //
  // Every position below is derived from the live canvas, never from a fixed
  // pixel budget: this game runs on a 2400x1600 tablet and on a 800x360 phone,
  // and it previously pinned the buddy to the right edge and the tray to a
  // fraction of the *raw* screen height, which put the bottom row under the
  // tablet's navigation bar.

  /// The area a game object may occupy: below the Flutter overlay strip and
  /// above the bottom safe area, inset from both side edges.
  @visibleForTesting
  static Rect playAreaFor(Vector2 canvas) {
    final inset = math.min(canvas.x * 0.04, 36.0);
    final top = kTopOverlayBand + 8;
    final bottom = canvas.y - math.max(canvas.y * 0.05, 16.0);
    return Rect.fromLTRB(
      inset,
      top,
      math.max(canvas.x - inset, inset + 1),
      math.max(bottom, top + 1),
    );
  }

  /// The left column: 42% of the width, minus a bottom reserve so the app's
  /// mascot does not stand on the character.
  ///
  /// A tier-3 round puts two buddies here; they split this column rather than
  /// widening it, so the answer cards keep their side of the field whatever the
  /// difficulty.
  @visibleForTesting
  static Rect characterRegionFor(Vector2 canvas) {
    final play = playAreaFor(canvas);
    final mascotReserve = math.min(kBottomMascotBand, play.height * 0.22);
    return Rect.fromLTRB(
      play.left,
      play.top,
      play.left + play.width * 0.42,
      math.max(play.bottom - mascotReserve, play.top + 1),
    );
  }

  /// The right column: 57% of the width, leaving a gutter between the two.
  @visibleForTesting
  static Rect optionsRegionFor(Vector2 canvas) {
    final play = playAreaFor(canvas);
    return Rect.fromLTRB(
      play.right - play.width * 0.57,
      play.top,
      play.right,
      play.bottom,
    );
  }

  /// The largest character box with the sprite's own proportions that fits
  /// [column], centred in it. Capped so a big tablet does not blow the buddy up
  /// to fill half the screen.
  @visibleForTesting
  static Vector2 buddyBoxFor(Rect column) {
    // The sprite cell is 406x490 and only the lower 79% of the box holds the
    // body (the rest is the request bubble), so a box this shape wastes no
    // room around the character.
    const ratio = 0.655;
    var h = math.min(column.height, 460.0);
    var w = h * ratio;
    if (w > column.width) {
      w = column.width;
      h = w / ratio;
    }
    return Vector2(math.max(w, 1), math.max(h, 1));
  }

  /// Square card slots for [count] options, laid out inside [region] and
  /// guaranteed to stay within it.
  ///
  /// Two cards go side by side on a wide region and stack on a tall one; three
  /// go in a row when there is room and otherwise fall back to a 2+1 grid whose
  /// last row is centred.
  @visibleForTesting
  static List<Rect> layoutOptionSlots({
    required Rect region,
    required int count,
    double maxCardSide = 200,
  }) {
    if (count <= 0 || region.width <= 0 || region.height <= 0) return const [];
    final columns = _optionColumnsFor(count, region);
    final rows = (count / columns).ceil();
    const gapFactor = 0.18;
    final byWidth = region.width / (columns + gapFactor * (columns - 1));
    final byHeight = region.height / (rows + gapFactor * (rows - 1));
    final side = math.min(math.min(byWidth, byHeight), maxCardSide);
    final gap = side * gapFactor;
    final gridHeight = rows * side + (rows - 1) * gap;
    final top = region.top + (region.height - gridHeight) / 2;

    final slots = <Rect>[];
    for (var i = 0; i < count; i++) {
      final row = i ~/ columns;
      final inRow = math.min(columns, count - row * columns);
      final rowWidth = inRow * side + (inRow - 1) * gap;
      final left = region.left + (region.width - rowWidth) / 2;
      slots.add(
        Rect.fromLTWH(
          left + (i % columns) * (side + gap),
          top + row * (side + gap),
          side,
          side,
        ),
      );
    }
    return slots;
  }

  static int _optionColumnsFor(int count, Rect region) {
    if (count <= 1) return 1;
    final ratio = region.width / region.height;
    if (count == 2) return ratio >= 1.0 ? 2 : 1;
    return ratio >= 1.6 ? 3 : 2;
  }

  void _buildBuddies() {
    final count = _tier == 3 ? 2 : 1;
    for (var i = 0; i < count; i++) {
      final buddy = BuddyComponent(
        kind: i == 0 ? BuddyKind.bps : BuddyKind.reiz,
        position: Vector2.zero(),
        size: Vector2.all(1),
      );
      _buddies.add(buddy);
      add(buddy);
    }
    _layoutBuddies();
  }

  /// Centres each buddy vertically in its share of the character column.
  void _layoutBuddies() {
    if (_buddies.isEmpty || size.x <= 0 || size.y <= 0) return;
    final region = characterRegionFor(size);
    final columnWidth = region.width / _buddies.length;
    final gutter = _buddies.length > 1 ? columnWidth * 0.08 : 0.0;
    for (var i = 0; i < _buddies.length; i++) {
      final column = Rect.fromLTWH(
        region.left + i * columnWidth + gutter / 2,
        region.top,
        columnWidth - gutter,
        region.height,
      );
      final box = buddyBoxFor(column);
      _buddies[i]
        ..size = box
        ..position = Vector2(
          column.center.dx - box.x / 2,
          region.center.dy - box.y / 2,
        );
    }
  }

  /// Places the answer cards into the option column.
  void _layoutItems() {
    if (_items.isEmpty || size.x <= 0 || size.y <= 0) return;
    final slots = layoutOptionSlots(
      region: optionsRegionFor(size),
      count: _items.length,
    );
    if (slots.length != _items.length) return;
    for (var i = 0; i < _items.length; i++) {
      final slot = slots[i];
      final item =
          _items[i]
            ..size = Vector2(slot.width, slot.height)
            ..homePosition = Vector2(slot.left, slot.top);
      // A card under the finger keeps whatever position the drag gave it;
      // snapping it back mid-gesture would read as it escaping the child's grip.
      if (item != _draggingItem) item.position = item.homePosition.clone();
    }
  }

  void _setupRound() {
    _cancelTimers();
    _hintsThisRound = 0;
    _requests = buildRequestPlan(
      tier: _tier,
      count: itemsPerRound,
      random: _random,
      excludedNames: _usedItems,
    );
    _usedItems.addAll(_requests.map((r) => r.item.name));
    _requestIndex = 0;
    analyticsStartRound(roundNumber: _round + 1);
    _setupTrial();
  }

  void _setupTrial() {
    for (final item in _items) item.removeFromParent();
    _items.clear();
    _ghostHand?.removeFromParent();
    _ghostHand = null;
    _errorsThisTrial = 0;

    final request = _activeRequest;
    for (var i = 0; i < _buddies.length; i++) {
      final buddy = _buddies[i];
      buddy.dimmed = false;
      buddy.pose = BuddyPose.present;
      if (i == request.buddyIndex) {
        buddy.showRequest(request.item);
      } else {
        buddy.hideRequest();
      }
    }

    final options = _trayFor(request.item);
    // A trial can be set up before the canvas has a size (a zero-sized region
    // yields no slots). Park the cards off-screen rather than indexing past the
    // end of an empty list; [_layoutItems] places them the moment a real size
    // arrives via [onGameResize].
    final slots = layoutOptionSlots(
      region: optionsRegionFor(size),
      count: options.length,
    );
    for (var i = 0; i < options.length; i++) {
      final data = options[i];
      final slot = i < slots.length ? slots[i] : Rect.zero;
      final item = DraggableItem(
        data: data,
        color: data.color,
        onPickedUp: _onPickedUp,
        onDropped: _onDropped,
        language: strings.language,
        position: Vector2(slot.left, slot.top),
        size: Vector2(math.max(slot.width, 1), math.max(slot.height, 1)),
      );
      _items.add(item);
      add(item);
    }

    _requestShownAt = DateTime.now();
    analyticsShowStimulus();
    analyticsAddRoundData('request_buddy', request.buddyIndex);
    analyticsAddRoundData('request_item', request.item.name);
    onPlayRequestVo?.call(AnswerLabel(item: request.item.name));

    if (_tier == 3 && !GameMotion.reduced) {
      _bubbleTimer = async.Timer(const Duration(seconds: 2), () {
        if (isMounted) _buddies[request.buddyIndex].hideRequest();
      });
    }
    _startIdleTimer();
  }

  List<StoreItemData> _trayFor(StoreItemData requested) => buildOptions(
    requested: requested,
    optionCount: optionCountForTier(_tier),
    random: _random,
  );

  void _onPickedUp(DraggableItem item) {
    _draggingItem = item;
    _idleTimer?.cancel();
    _hidePrompts();
    onPlayDragSfx?.call();
    final started = _requestShownAt;
    if (started != null) {
      socialMetrics.dragHesitationsMs.add(
        DateTime.now().difference(started).inMilliseconds,
      );
    }
  }

  void _onDropped(DraggableItem item, Vector2 point) {
    _draggingItem = null;
    onPlayDropSfx?.call();
    BuddyComponent? target;
    var targetIndex = -1;
    for (var i = 0; i < _buddies.length; i++) {
      if (_buddies[i].accepts(point)) {
        target = _buddies[i];
        targetIndex = i;
        break;
      }
    }
    final bubbleVisible = _buddies[_activeRequest.buddyIndex].bubbleVisible;
    final outcome = evaluateDrop(
      item: item.data,
      targetBuddyIndex: targetIndex,
      request: _activeRequest,
    );
    socialMetrics.record(outcome, bubbleWasVisible: bubbleVisible);

    if (outcome == TulongDropOutcome.motorMiss) {
      item.returnHome();
      _startIdleTimer();
      return;
    }
    analyticsRecordValidAction();

    if (outcome == TulongDropOutcome.correct) {
      final responseMs =
          _requestShownAt == null
              ? 0
              : DateTime.now().difference(_requestShownAt!).inMilliseconds;
      _score++;
      _totalResponseTimeMs += responseMs;
      analyticsRecordCorrect(
        extraData: {
          'item': item.data.name,
          'recipient': targetIndex,
          'response_time_ms': responseMs,
        },
      );
      onCorrectDrop?.call();
      onPlayCorrectSfx?.call();
      onPlayCorrectVo?.call(AnswerLabel(item: item.data.name));
      onPlayThankYouVo?.call();
      target!.celebrate();
      item.lockInto(target.handCenter, onSettled: item.removeFromParent);
      Future.delayed(const Duration(milliseconds: 700), _advanceRequest);
      return;
    }

    _errorsThisTrial++;
    if (outcome == TulongDropOutcome.wrongRecipient) {
      analyticsAddRoundData(
        'wrong_recipient_attempts',
        socialMetrics.wrongRecipients,
      );
      analyticsRecordRetry();
    } else {
      _plainErrors++;
      analyticsRecordWrong(
        extraData: {
          'item': item.data.name,
          'expected_item': _activeRequest.item.name,
          'recipient': targetIndex,
        },
      );
      analyticsRecordRetry();
    }
    if (!bubbleVisible) {
      analyticsAddRoundData(
        'bubble_recall_errors',
        socialMetrics.bubbleRecallErrors,
      );
    }
    onPlayWrongSfx?.call();
    onPlayWrongVo?.call();
    onWrongAnswer?.call();
    target?.reassure();
    item.showError();
    Future.delayed(const Duration(milliseconds: 450), () {
      if (!isMounted) return;
      item.returnHome();
      _showEscalatingPrompt();
      _startIdleTimer();
    });
  }
  void _advanceRequest() {
    if (!isLifecycleActive) return;
    _requestIndex++;
    if (_requestIndex < _requests.length) {
      _setupTrial();
      return;
    }
    analyticsCompleteRound(successful: true);
    _round++;
    onStepChanged(_round);
    if (_round >= totalRounds) {
      _completeGame();
    } else {
      onPlayLevelCompleteSfx?.call();
      onPlayTransitionVo?.call();
      guardedDelay(const Duration(milliseconds: 700), _setupRound);
    }
  }

  void _completeGame() {
    if (!tryBeginCompletion()) return;
    _cancelTimers();
    onPlayGameCompleteSfx?.call();
    onPlayCelebrationVo?.call();
    analyticsMarkCompleted();
    analyticsAddGameSpecificMetric(
      'wrongRecipientRate', socialMetrics.wrongRecipientRate,
    );
    analyticsAddGameSpecificMetric(
      'dragHesitationMs', socialMetrics.averageDragHesitationMs,
    );
    analyticsAddGameSpecificMetric(
      'bubbleRecallErrors', socialMetrics.bubbleRecallErrors,
    );
    analyticsAddGameSpecificMetric(
      'promptLevelUsed', socialMetrics.promptLevelUsed,
    );
    analyticsCompleteSession();
    guardedDelay(const Duration(milliseconds: 600), () {
      onGameComplete(
        score: _score,
        totalItems: totalRounds * itemsPerRound,
        errorCount: _plainErrors,
        totalResponseTimeMs: _totalResponseTimeMs,
        analytics: analyticsSession,
      );
    });
  }

  void _showEscalatingPrompt() {
    if (profile == DifficultyProfile.assessment || !_mayHint) return;
    _hintsThisRound++;
    final level = _errorsThisTrial.clamp(1, 4);
    socialMetrics.promptLevelUsed = math.max(
      socialMetrics.promptLevelUsed,
      level,
    );
    final requester = _buddies[_activeRequest.buddyIndex];
    requester.pulseBubble();
    if (level >= 2 && _buddies.length > 1) {
      for (var i = 0; i < _buddies.length; i++) {
        _buddies[i].dimmed = i != _activeRequest.buddyIndex;
      }
    }
    final correct = _items.firstWhere(
      (i) => i.data.name == _activeRequest.item.name,
    );
    if (level >= 3)
      correct.add(
        ScaleEffect.to(Vector2.all(1.12), EffectController(duration: 0.25)),
      );
    if (level >= 4 || (profile == DifficultyProfile.medium && !_mayHint)) {
      _ghostHand?.removeFromParent();
      _ghostHand = GhostHand.drag(
        from: correct.position + correct.size / 2,
        to: requester.handCenter,
        handSize: correct.size.x * 0.65,
      );
      add(_ghostHand!);
    }
    analyticsRecordHint(hintType: 'social_prompt_$level');
  }

  void _hidePrompts() {
    _ghostHand?.removeFromParent();
    _ghostHand = null;
    for (final buddy in _buddies) buddy.dimmed = false;
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    final delay = _mayHint ? profile.idleHintDelay : profile.reorientDelay;
    _idleTimer = async.Timer(delay, () {
      if (!isMounted) return;
      _errorsThisTrial++;
      _showEscalatingPrompt();
      _startIdleTimer();
    });
  }

  void _cancelTimers() {
    _bubbleTimer?.cancel();
    _idleTimer?.cancel();
  }

  @visibleForTesting
  static TulongDropOutcome evaluateDrop({
    required StoreItemData item,
    required int targetBuddyIndex,
    required TulongRequest request,
  }) {
    if (targetBuddyIndex < 0) return TulongDropOutcome.motorMiss;
    if (item.name == request.item.name &&
        targetBuddyIndex != request.buddyIndex) {
      return TulongDropOutcome.wrongRecipient;
    }
    if (item.name != request.item.name) return TulongDropOutcome.wrongItem;
    return TulongDropOutcome.correct;
  }

  /// How many answer cards a single trial shows.
  ///
  /// Deliberately *not* [itemsPerRound] — that is how many requests the buddy
  /// makes before the round ends, and reusing it for the tray is what made an
  /// easy round show a single card that was always the right one, i.e. a choice
  /// with nothing to choose between. Two options on easy, three above it.
  @visibleForTesting
  static int optionCountForTier(int tier) => tier <= 1 ? 2 : 3;

  /// The answer cards for one trial: [requested] exactly once, plus unique
  /// distractors, shuffled so the correct card is never in a learnable spot.
  ///
  /// Distractors are drawn from the requested item's own shelf first, so the
  /// wrong answers are things the buddy might plausibly have asked for rather
  /// than an obvious odd-one-out.
  @visibleForTesting
  static List<StoreItemData> buildOptions({
    required StoreItemData requested,
    required int optionCount,
    math.Random? random,
  }) {
    final rng = random ?? math.Random();
    final target = optionCount.clamp(2, 3);
    final sameShelf = <StoreItemData>[];
    final elsewhere = <StoreItemData>[];
    for (final item in SariSariSortGame.catalogue.values.expand((i) => i)) {
      if (item.name == requested.name) continue;
      (item.category == requested.category ? sameShelf : elsewhere).add(item);
    }
    sameShelf.shuffle(rng);
    elsewhere.shuffle(rng);

    final chosen = <String>{requested.name};
    final options = <StoreItemData>[requested];
    for (final item in [...sameShelf, ...elsewhere]) {
      if (options.length >= target) break;
      if (chosen.add(item.name)) options.add(item);
    }
    options.shuffle(rng);
    return options;
  }

  @visibleForTesting
  static List<TulongRequest> buildRequestPlan({
    required int tier,
    required int count,
    math.Random? random,
    Set<String> excludedNames = const {},
  }) {
    final rng = random ?? math.Random();
    var pool =
        SariSariSortGame.catalogue.values
            .expand((items) => items)
            .where((item) => !excludedNames.contains(item.name))
            .toList();
    if (pool.length < count) {
      pool =
          SariSariSortGame.catalogue.values.expand((items) => items).toList();
    }
    pool.shuffle(rng);
    return List.generate(
      count,
      (index) => TulongRequest(
        buddyIndex: tier == 3 ? index % 2 : 0,
        item: pool[index % pool.length],
      ),
    );
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    analyticsRecordTouch(
      Offset(event.canvasPosition.x, event.canvasPosition.y),
      isValid: false,
    );
  }

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    _layoutBuddies();
    _layoutItems();
  }

  @override
  void onRemove() {
    invalidateLifecycle();
    _cancelTimers();
    super.onRemove();
  }
}
