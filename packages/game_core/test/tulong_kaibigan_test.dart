import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:game_core/src/games/shared/game_layout.dart';

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
    final metrics =
        TulongKaibiganMetrics()..record(outcome, bubbleWasVisible: false);

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

  // ── Answer options ─────────────────────────────────────────────────

  test('easy shows two options, medium and hard show three', () {
    expect(TulongKaibiganGame.optionCountForTier(1), 2);
    expect(TulongKaibiganGame.optionCountForTier(2), 3);
    expect(TulongKaibiganGame.optionCountForTier(3), 3);
  });

  test(
    'every tray holds exactly one correct answer and unique distractors',
    () {
      for (var seed = 0; seed < 60; seed++) {
        final rng = math.Random(seed);
        final requested = catalogue[seed % catalogue.length];
        for (final tier in [1, 2, 3]) {
          final options = TulongKaibiganGame.buildOptions(
            requested: requested,
            optionCount: TulongKaibiganGame.optionCountForTier(tier),
            random: rng,
          );

          expect(
            options,
            hasLength(TulongKaibiganGame.optionCountForTier(tier)),
          );
          expect(options.length, inInclusiveRange(2, 3));
          expect(
            options.where((o) => o.name == requested.name),
            hasLength(1),
            reason: 'the requested item must appear exactly once',
          );
          expect(
            options.map((o) => o.name).toSet(),
            hasLength(options.length),
            reason: 'no duplicate answers',
          );
        }
      }
    },
  );

  test('the correct answer does not always sit in the same slot', () {
    final requested = catalogue.first;
    final indices = <int>{};
    for (var seed = 0; seed < 40; seed++) {
      final options = TulongKaibiganGame.buildOptions(
        requested: requested,
        optionCount: 3,
        random: math.Random(seed),
      );
      indices.add(options.indexWhere((o) => o.name == requested.name));
    }
    expect(indices, containsAll([0, 1, 2]));
  });

  test('an out-of-range option count is clamped to a real choice', () {
    final options = TulongKaibiganGame.buildOptions(
      requested: catalogue.first,
      optionCount: 1,
      random: math.Random(7),
    );
    expect(options, hasLength(2));
    expect(options.where((o) => o.name == catalogue.first.name), hasLength(1));
  });

  // ── Responsive layout ──────────────────────────────────────────────

  // The Xiaomi Pad 6 in landscape (1800x2880 at density 400 -> 1152x720
  // logical), a 16:9 phone and a very short landscape canvas.
  final canvases = <String, Vector2>{
    'tablet landscape': Vector2(1152, 720),
    'phone landscape': Vector2(800, 360),
    'short landscape': Vector2(960, 300),
  };

  canvases.forEach((label, canvas) {
    test('$label keeps every option card inside the safe play area', () {
      final play = TulongKaibiganGame.playAreaFor(canvas);
      expect(play.top, greaterThanOrEqualTo(kTopOverlayBand));
      expect(play.bottom, lessThan(canvas.y));

      for (final count in [2, 3]) {
        final region = TulongKaibiganGame.optionsRegionFor(canvas);
        final slots = TulongKaibiganGame.layoutOptionSlots(
          region: region,
          count: count,
        );
        expect(slots, hasLength(count));
        for (final slot in slots) {
          expect(slot.left, greaterThanOrEqualTo(region.left - 0.01));
          expect(slot.right, lessThanOrEqualTo(region.right + 0.01));
          expect(slot.top, greaterThanOrEqualTo(play.top - 0.01));
          expect(slot.bottom, lessThanOrEqualTo(play.bottom + 0.01));
          expect(slot.width, greaterThan(0));
          expect(slot.width, closeTo(slot.height, 0.01));
        }
      }
    });

    test('$label puts the character left of the answer choices', () {
      final options = TulongKaibiganGame.optionsRegionFor(canvas);
      final character = TulongKaibiganGame.characterRegionFor(canvas);
      expect(character.right, lessThanOrEqualTo(options.left));

      // One buddy takes the whole column, two split it — either way the box
      // stays inside its share and never reaches the cards.
      for (final buddies in [1, 2]) {
        final column = Rect.fromLTWH(
          character.left,
          character.top,
          character.width / buddies,
          character.height,
        );
        final box = TulongKaibiganGame.buddyBoxFor(column);
        expect(box.x, lessThanOrEqualTo(column.width + 0.01));
        expect(box.y, lessThanOrEqualTo(column.height + 0.01));
        expect(column.left + box.x, lessThanOrEqualTo(options.left));
      }
    });

    test('$label gives the character 40-45% of the width', () {
      final play = TulongKaibiganGame.playAreaFor(canvas);
      final character = TulongKaibiganGame.characterRegionFor(canvas);
      final options = TulongKaibiganGame.optionsRegionFor(canvas);
      expect(character.width / play.width, inInclusiveRange(0.40, 0.45));
      expect(options.width / play.width, inInclusiveRange(0.55, 0.60));
    });

    test('$label never lets an option card overlap another', () {
      for (final count in [2, 3]) {
        final slots = TulongKaibiganGame.layoutOptionSlots(
          region: TulongKaibiganGame.optionsRegionFor(canvas),
          count: count,
        );
        for (var i = 0; i < slots.length; i++) {
          for (var j = i + 1; j < slots.length; j++) {
            expect(slots[i].overlaps(slots[j]), isFalse);
          }
        }
      }
    });
    test('$label keeps a held card narrower than the buddy', () {
      // Two buddies splitting the character column is the narrowest case; the
      // box keeps the sprite's own 406x490 proportions, so its width is the
      // character's drawn width (the body fills the box's width exactly).
      final character = TulongKaibiganGame.characterRegionFor(canvas);
      final columnWidth = character.width / 2;
      final gutter = columnWidth * 0.08;
      final buddy = TulongKaibiganGame.buddyBoxFor(
        Rect.fromLTWH(
          character.left,
          character.top,
          columnWidth - gutter,
          character.height,
        ),
      );

      for (final count in [2, 3]) {
        final slots = TulongKaibiganGame.layoutOptionSlots(
          region: TulongKaibiganGame.optionsRegionFor(canvas),
          count: count,
        );
        for (final slot in slots) {
          final scale = TulongKaibiganGame.draggedCardScaleFor(
            cardSide: slot.width,
            buddyWidth: buddy.x,
          );
          expect(
            slot.width * scale,
            lessThan(buddy.x + 0.01),
            reason:
                'a held card ($count options) would fully cover the '
                'character on $label',
          );
          expect(
            scale,
            inInclusiveRange(
              TulongKaibiganGame.minDraggedCardScale,
              TulongKaibiganGame.maxDraggedCardScale,
            ),
            reason: 'held card scale out of range on $label',
          );
        }
      }
    });
  });

  test('two cards stack when the option column is taller than it is wide', () {
    final tall = const Rect.fromLTWH(0, 0, 200, 600);
    final slots = TulongKaibiganGame.layoutOptionSlots(region: tall, count: 2);
    expect(slots[0].left, closeTo(slots[1].left, 0.01));
    expect(slots[0].bottom, lessThanOrEqualTo(slots[1].top));
  });

  test('three cards fall back to a centred 2+1 grid on a narrow column', () {
    final narrow = const Rect.fromLTWH(0, 0, 300, 400);
    final slots = TulongKaibiganGame.layoutOptionSlots(
      region: narrow,
      count: 3,
    );
    expect(slots[0].top, closeTo(slots[1].top, 0.01));
    expect(slots[2].top, greaterThan(slots[0].bottom - 0.01));
    // The lone card on the second row is centred under the pair above it.
    expect(
      slots[2].center.dx,
      closeTo((slots[0].center.dx + slots[1].center.dx) / 2, 0.01),
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

    item.onDragStart(
      DragStartEvent(
        1,
        game,
        DragStartDetails(globalPosition: const Offset(105, 105)),
      ),
    );
    for (var i = 0; i < 20; i++) item.update(1 / 60);
    item.onDragUpdate(
      DragUpdateEvent(
        1,
        game,
        DragUpdateDetails(globalPosition: const Offset(520, 430)),
      ),
    );
    item.update(1 / 60);

    expect(item.visualCenter.x, closeTo(520, 0.5));
    expect(item.visualCenter.y, closeTo(430, 0.5));
  });

  group('buddy drop targets', () {
    // Without loaded art the drawn body falls back to the body box: the full
    // component width, starting below the request bubble.
    BuddyComponent buddyAt(double left) => BuddyComponent(
      kind: BuddyKind.bps,
      position: Vector2(left, 0),
      size: Vector2(200, 400),
    );
    const bodyTop = 400 * 0.30 * 0.70;
    const bodyHeight = 400 - bodyTop;

    test('a drop anywhere on the drawn body is accepted', () {
      final buddy = buddyAt(0);
      // Left and right edges of the body, and its full vertical span from the
      // shoulders to the feet — all of it is "handing it to the buddy".
      for (final point in [
        Vector2(1, bodyTop + bodyHeight * 0.25),
        Vector2(199, bodyTop + bodyHeight * 0.25),
        Vector2(100, bodyTop + bodyHeight * 0.22),
        Vector2(100, bodyTop + bodyHeight * 0.99),
        Vector2(1, bodyTop + bodyHeight * 0.95),
      ]) {
        expect(
          buddy.accepts(point),
          isTrue,
          reason: '$point is on the buddy but was read as a motor miss',
        );
      }
    });

    test('a drop well clear of the buddy is still a miss', () {
      final buddy = buddyAt(0);
      expect(buddy.accepts(Vector2(600, 200)), isFalse);
      expect(buddy.accepts(Vector2(100, -200)), isFalse);
    });

    test('the accept zone reaches past the drawn body', () {
      final buddy = buddyAt(0);
      // 16% of the longer side (400) is 64px of slack on every edge.
      expect(buddy.accepts(Vector2(-40, bodyTop + bodyHeight * 0.60)), isTrue);
      expect(buddy.accepts(Vector2(240, bodyTop + bodyHeight * 0.60)), isTrue);
    });

    test('an overlapping drop goes to the nearer buddy', () {
      // Tier 3: two buddies side by side, close enough that the tolerance makes
      // their zones overlap in the gutter between them.
      final left = buddyAt(0);
      final right = buddyAt(210);
      final gutter = Vector2(206, bodyTop + bodyHeight * 0.60);
      expect(left.accepts(gutter), isTrue);
      expect(right.accepts(gutter), isTrue);
      expect(
        right.distanceTo(gutter)!,
        lessThan(left.distanceTo(gutter)!),
        reason: 'a drop in the gutter belongs to the buddy it landed nearest',
      );
    });

    test('distanceTo is null exactly when the drop misses', () {
      final buddy = buddyAt(0);
      expect(buddy.distanceTo(Vector2(600, 200)), isNull);
      expect(
        buddy.distanceTo(Vector2(100, bodyTop + bodyHeight * 0.60)),
        closeTo(0, 0.01),
      );
    });
  });
}
