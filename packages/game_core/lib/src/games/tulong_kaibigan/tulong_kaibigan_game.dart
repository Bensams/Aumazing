import 'dart:async' as async;
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
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

  double get averageDragHesitationMs => dragHesitationsMs.isEmpty
      ? 0
      : dragHesitationsMs.reduce((a, b) => a + b) /
          dragHesitationsMs.length;
}

class TulongKaibiganGame extends FlameGame
    with DragCallbacks, EnhancedGameplayAnalyticsMixin {
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
  }) onGameComplete;
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
  async.Timer? _bubbleTimer;
  async.Timer? _idleTimer;
  GhostHand? _ghostHand;

  int get _tier => profile.level.clamp(1, 3);
  bool get _mayHint => !profile.noHints &&
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

  void _buildBuddies() {
    final count = _tier == 3 ? 2 : 1;
    final buddyW = math.min(size.x * (count == 2 ? 0.28 : 0.34), 310.0);
    // The tray the child drags from needs the bottom of the field, but taking
    // a flat 120px for it collapsed the buddy on a short canvas: at 960x300
    // that left an 84px-tall box, so even drawn at the right proportions the
    // buddy was a thumbnail. A proportional reserve keeps the character
    // legible on a phone and still leaves the tray its room on a tablet.
    final playfield = size.y - kTopOverlayBand;
    final buddyH = playfield * 0.78;
    for (var i = 0; i < count; i++) {
      final x = count == 1
          ? size.x - buddyW - size.x * 0.06
          : size.x * (i == 0 ? 0.04 : 0.68);
      final buddy = BuddyComponent(
        kind: i == 0 ? BuddyKind.bps : BuddyKind.reiz,
        position: Vector2(x, kTopOverlayBand + 8),
        size: Vector2(buddyW, buddyH),
      );
      _buddies.add(buddy);
      add(buddy);
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

    final tray = _trayFor(request.item);
    final itemSize = math.min(size.y * 0.24, size.x / 6.2);
    final gap = itemSize * 0.18;
    final totalWidth = tray.length * itemSize + (tray.length - 1) * gap;
    final startX = (size.x - totalWidth) / 2;
    final y = size.y - itemSize - size.y * 0.035;
    for (var i = 0; i < tray.length; i++) {
      final data = tray[i];
      final item = DraggableItem(
        data: data,
        color: data.color,
        onPickedUp: _onPickedUp,
        onDropped: _onDropped,
        language: strings.language,
        position: Vector2(startX + i * (itemSize + gap), y),
        size: Vector2.all(itemSize),
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

  List<StoreItemData> _trayFor(StoreItemData requested) {
    final desired = _tier == 1 ? 1 : (_tier == 2 ? itemsPerRound.clamp(2, 3) : 4);
    final all = SariSariSortGame.catalogue.values.expand((items) => items).toList()
      ..shuffle(_random);
    final tray = <StoreItemData>[requested];
    for (final item in all) {
      if (tray.length >= desired) break;
      if (item.name != requested.name) tray.add(item);
    }
    tray.shuffle(_random);
    return tray;
  }

  void _onPickedUp(DraggableItem item) {
    _idleTimer?.cancel();
    _hidePrompts();
    onPlayDragSfx?.call();
    final started = _requestShownAt;
    if (started != null) {
      socialMetrics.dragHesitationsMs
          .add(DateTime.now().difference(started).inMilliseconds);
    }
  }

  void _onDropped(DraggableItem item, Vector2 point) {
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
      final responseMs = _requestShownAt == null
          ? 0
          : DateTime.now().difference(_requestShownAt!).inMilliseconds;
      _score++;
      _totalResponseTimeMs += responseMs;
      analyticsRecordCorrect(extraData: {
        'item': item.data.name,
        'recipient': targetIndex,
        'response_time_ms': responseMs,
      });
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
      analyticsAddRoundData('wrong_recipient_attempts', socialMetrics.wrongRecipients);
      analyticsRecordRetry();
    } else {
      _plainErrors++;
      analyticsRecordWrong(extraData: {
        'item': item.data.name,
        'expected_item': _activeRequest.item.name,
        'recipient': targetIndex,
      });
      analyticsRecordRetry();
    }
    if (!bubbleVisible) {
      analyticsAddRoundData('bubble_recall_errors', socialMetrics.bubbleRecallErrors);
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
    if (!isMounted) return;
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
      Future.delayed(const Duration(milliseconds: 700), _setupRound);
    }
  }

  void _completeGame() {
    _cancelTimers();
    onPlayGameCompleteSfx?.call();
    onPlayCelebrationVo?.call();
    analyticsMarkCompleted();
    analyticsAddGameSpecificMetric(
        'wrongRecipientRate', socialMetrics.wrongRecipientRate);
    analyticsAddGameSpecificMetric(
        'dragHesitationMs', socialMetrics.averageDragHesitationMs);
    analyticsAddGameSpecificMetric(
        'bubbleRecallErrors', socialMetrics.bubbleRecallErrors);
    analyticsAddGameSpecificMetric(
        'promptLevelUsed', socialMetrics.promptLevelUsed);
    analyticsCompleteSession();
    Future.delayed(const Duration(milliseconds: 600), () {
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
    socialMetrics.promptLevelUsed = math.max(socialMetrics.promptLevelUsed, level);
    final requester = _buddies[_activeRequest.buddyIndex];
    requester.pulseBubble();
    if (level >= 2 && _buddies.length > 1) {
      for (var i = 0; i < _buddies.length; i++) {
        _buddies[i].dimmed = i != _activeRequest.buddyIndex;
      }
    }
    final correct = _items.firstWhere((i) => i.data.name == _activeRequest.item.name);
    if (level >= 3) correct.add(ScaleEffect.to(Vector2.all(1.12), EffectController(duration: 0.25)));
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
    if (item.name == request.item.name && targetBuddyIndex != request.buddyIndex) {
      return TulongDropOutcome.wrongRecipient;
    }
    if (item.name != request.item.name) return TulongDropOutcome.wrongItem;
    return TulongDropOutcome.correct;
  }

  @visibleForTesting
  static List<TulongRequest> buildRequestPlan({
    required int tier,
    required int count,
    math.Random? random,
    Set<String> excludedNames = const {},
  }) {
    final rng = random ?? math.Random();
    var pool = SariSariSortGame.catalogue.values
        .expand((items) => items)
        .where((item) => !excludedNames.contains(item.name))
        .toList();
    if (pool.length < count) {
      pool = SariSariSortGame.catalogue.values.expand((items) => items).toList();
    }
    pool.shuffle(rng);
    return List.generate(count, (index) => TulongRequest(
          buddyIndex: tier == 3 ? index % 2 : 0,
          item: pool[index % pool.length],
        ));
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
  void onRemove() {
    _cancelTimers();
    super.onRemove();
  }
}
