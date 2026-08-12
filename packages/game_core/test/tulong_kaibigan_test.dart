import 'dart:math' as math;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final catalogue = SariSariSortGame.catalogue.values.expand((v) => v).toList();

  test('tier 3 alternates buddies without repeating a requested item', () {
    for (var seed = 0; seed < 50; seed++) {
      final plan = TulongKaibiganGame.buildRequestPlan(
        tier: 3,
        count: 4,
        random: math.Random(seed),
      );
      expect(plan.map((r) => r.item.name).toSet(), hasLength(plan.length));
      expect(plan.map((r) => r.buddyIndex), [0, 1, 0, 1]);
      for (var i = 1; i < plan.length; i++) {
        if (plan[i].buddyIndex != plan[i - 1].buddyIndex) {
          expect(plan[i].item.name, isNot(plan[i - 1].item.name));
        }
      }
    }
  });

  test('right item to wrong buddy is recipient telemetry, not plain error', () {
    final request = TulongRequest(buddyIndex: 0, item: catalogue.first);
    final outcome = TulongKaibiganGame.evaluateDrop(
      item: request.item,
      targetBuddyIndex: 1,
      request: request,
    );
    final metrics = TulongKaibiganMetrics()
      ..record(outcome, bubbleWasVisible: false);

    expect(outcome, TulongDropOutcome.wrongRecipient);
    expect(metrics.wrongRecipients, 1);
    expect(metrics.wrongRecipientRate, 1);
    expect(metrics.bubbleRecallErrors, 1);
  });

  test('a motor miss remains neutral', () {
    final request = TulongRequest(buddyIndex: 0, item: catalogue.first);
    expect(
      TulongKaibiganGame.evaluateDrop(
        item: request.item,
        targetBuddyIndex: -1,
        request: request,
      ),
      TulongDropOutcome.motorMiss,
    );
  });

  test('shared item card follows the fingertip absolutely', () async {
    final game = FlameGame()..onGameResize(Vector2(800, 600));
    final item = DraggableItem(
      data: catalogue.first,
      color: catalogue.first.color,
      onPickedUp: (_) {},
      onDropped: (_, __) {},
      position: Vector2(100, 100),
      size: Vector2.all(120),
    );
    await game.add(item);
    await game.ready();

    item.onDragStart(DragStartEvent(
      1,
      game,
      DragStartDetails(globalPosition: const Offset(105, 105)),
    ));
    for (var i = 0; i < 20; i++) item.update(1 / 60);
    item.onDragUpdate(DragUpdateEvent(
      1,
      game,
      DragUpdateDetails(globalPosition: const Offset(520, 430)),
    ));
    item.update(1 / 60);

    expect(item.visualCenter.x, closeTo(520, 0.5));
    expect(item.visualCenter.y, closeTo(430, 0.5));
  });
}
